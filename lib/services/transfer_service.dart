import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/device_info.dart';
import '../models/transfer_history.dart';
import '../utils/file_utils.dart';
import '../utils/platform_utils.dart';

class TransferService {
  HttpServer? _server;
  final int _port = 8080;
  final String _discoveryEndpoint = '/api/discovery';
  final String _historyKey = 'transfer_history';
  final Uuid _uuid = const Uuid();
  String? _deviceId;
  String? _deviceName;

  // Get server address (null if server not running)
  Future<String?>? getServerAddress() {
    if (_server == null) return null;
    return NetworkInfo().getWifiIP();
  }

  // Getter for the server port
  int get serverPort => _port;

  Future<String> startServer() async {
    await _initDeviceInfo();

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      _port,
    );

    final networkInfo = NetworkInfo();
    final ip = await networkInfo.getWifiIP();
    return '$ip:${_server?.port}';
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _initDeviceInfo() async {
    if (_deviceId != null) return;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    _deviceName = prefs.getString('device_name');

    if (_deviceId == null) {
      _deviceId = _uuid.v4();
      await prefs.setString('device_id', _deviceId!);
    }

    if (_deviceName == null) {
      _deviceName = PlatformUtils.isWindows ? Platform.localHostname :
      'Android-${_deviceId!.substring(0, 4)}';
      await prefs.setString('device_name', _deviceName!);
    }
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    // Handle discovery endpoint
    if (request.url.path == 'api' && request.url.pathSegments.contains('discovery')) {
      return _handleDiscoveryRequest();
    }

    // Handle file transfer
    if (request.method == 'POST') {
      try {
        // Extract file name from headers
        final fileName = request.headers['file-name'] ??
            'image_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // Read request body
        final bytes = await request.read().expand((element) => element).toList();

        // Get save location
        final saveDir = await FileUtils.getAppSaveDirectory();
        final filePath = await FileUtils.getUniqueFileName('$saveDir/$fileName');
        final file = File(filePath);

        // Save file
        await file.writeAsBytes(bytes);

        // Extract device info from request
        String? sourceDeviceId = request.headers['device-id'];
        String? sourceDeviceName = request.headers['device-name'];
        String? sourceDeviceType = request.headers['device-type'];

        // Create a history entry
        if (sourceDeviceId != null) {
          final sourceDevice = DeviceInfo(
            id: sourceDeviceId,
            name: sourceDeviceName ?? 'Unknown Device',
            ipAddress: request.headers['host'] ?? '',
            port: _port,
            deviceType: sourceDeviceType ?? 'Unknown',
          );

          await _addToTransferHistory(
            fileName: fileName,
            filePath: filePath,
            fileSize: bytes.length,
            direction: 'received',
            targetDevice: sourceDevice,
            successful: true,
          );
        }

        return shelf.Response.ok(json.encode({
          'success': true,
          'message': 'File saved successfully',
          'path': file.path
        }));
      } catch (e) {
        return shelf.Response.internalServerError(
            body: json.encode({
              'success': false,
              'error': e.toString()
            })
        );
      }
    }

    return shelf.Response.notFound('Not found');
  }

  shelf.Response _handleDiscoveryRequest() {
    return shelf.Response.ok(
      json.encode({
        'id': _deviceId,
        'name': _deviceName,
        'deviceType': PlatformUtils.getPlatformName(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<bool> sendImage(String serverAddress, String imagePath, [DeviceInfo? targetDevice]) async {
    await _initDeviceInfo();

    try {
      final file = File(imagePath);
      final fileName = file.path.split(Platform.pathSeparator).last;
      final bytes = await file.readAsBytes();

      final response = await http.post(
        Uri.parse('http://$serverAddress'),
        headers: {
          'Content-Type': 'application/octet-stream',
          'file-name': fileName,
          'device-id': _deviceId ?? '',
          'device-name': _deviceName ?? PlatformUtils.getPlatformName(),
          'device-type': PlatformUtils.getPlatformName(),
        },
        body: bytes,
      );

      final success = response.statusCode == 200;

      // Create history entry
      if (targetDevice != null) {
        await _addToTransferHistory(
          fileName: fileName,
          filePath: imagePath,
          fileSize: bytes.length,
          direction: 'sent',
          targetDevice: targetDevice,
          successful: success,
          errorMessage: success ? null : 'Status code: ${response.statusCode}',
        );
      }

      return success;
    } catch (e) {
      print('Error sending image: $e');

      // Record failure in history if device info is available
      if (targetDevice != null) {
        await _addToTransferHistory(
          fileName: imagePath.split(Platform.pathSeparator).last,
          filePath: imagePath,
          fileSize: File(imagePath).lengthSync(),
          direction: 'sent',
          targetDevice: targetDevice,
          successful: false,
          errorMessage: e.toString(),
        );
      }

      return false;
    }
  }

  Future<TransferHistory> getTransferHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_historyKey);

    if (jsonStr == null || jsonStr.isEmpty) {
      return TransferHistory.empty();
    }

    try {
      return TransferHistory.fromJson(jsonStr);
    } catch (e) {
      print('Error loading transfer history: $e');
      return TransferHistory.empty();
    }
  }

  Future<void> _addToTransferHistory({
    required String fileName,
    required String filePath,
    required int fileSize,
    required String direction,
    required DeviceInfo targetDevice,
    required bool successful,
    String? errorMessage,
  }) async {
    try {
      final history = await getTransferHistory();

      final entry = TransferHistoryEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        fileName: fileName,
        fileSize: fileSize,
        filePath: filePath,
        direction: direction,
        targetDevice: targetDevice,
        successful: successful,
        errorMessage: errorMessage,
      );

      final updatedHistory = history.addEntry(entry);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historyKey, updatedHistory.toJson());
    } catch (e) {
      print('Error adding to transfer history: $e');
    }
  }

  Future<void> clearTransferHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}