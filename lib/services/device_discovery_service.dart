import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:http/http.dart' as http;
import '../models/device_info.dart';
import '../utils/platform_utils.dart';
import 'transfer_service.dart';

class DeviceDiscoveryService {
  static const String _discoveryEndpoint = '/api/discovery';
  static const String _prefsKey = 'known_devices';
  static const Duration _broadcastInterval = Duration(seconds: 5);
  static const Duration _timeout = Duration(seconds: 2);

  final TransferService _transferService;
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final _deviceStreamController = StreamController<List<DeviceInfo>>.broadcast();

  Timer? _broadcastTimer;
  RawDatagramSocket? _socket;
  bool _isRunning = false;
  String? _deviceId;
  String _deviceName = 'Unknown Device';

  DeviceDiscoveryService(this._transferService) {
    _init();
  }

  Stream<List<DeviceInfo>> get devicesStream => _deviceStreamController.stream;
  List<DeviceInfo> get discoveredDevices => _discoveredDevices.values.toList();
  bool get isRunning => _isRunning;
  String get deviceId => _deviceId ?? '';

  Future<void> _init() async {
    _deviceId = await _getOrCreateDeviceId();
    _deviceName = await _getDeviceName();
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');

    if (id == null) {
      id = 'device_${Random().nextInt(10000)}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', id);
    }

    return id;
  }

  Future<String> _getDeviceName() async {
    try {
      if (Platform.isWindows) {
        return Platform.localHostname;
      } else if (Platform.isAndroid) {
        final prefs = await SharedPreferences.getInstance();
        var customName = prefs.getString('device_name');
        if (customName != null && customName.isNotEmpty) {
          return customName;
        }

        // Default to something identifiable
        return 'Android-${Random().nextInt(1000)}';
      }
    } catch (e) {
      print('Error getting device name: $e');
    }

    return '${PlatformUtils.getPlatformName()}-Device';
  }

  Future<void> setCustomDeviceName(String name) async {
    if (name.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
    _deviceName = name;

    // If discovery is running, update broadcasts
    if (_isRunning) {
      _stopBroadcast();
      _startBroadcast();
    }
  }

  Future<void> startDiscovery() async {
    if (_isRunning) return;
    _isRunning = true;

    // Load previously discovered devices
    await _loadKnownDevices();

    // Emit initial devices
    _notifyDevicesChanged();

    // Start listening for broadcasts
    await _startListening();

    // Start broadcasting this device
    _startBroadcast();

    // Manual scan for devices on current subnet
    _scanLocalNetwork();
  }

  Future<void> stopDiscovery() async {
    if (!_isRunning) return;
    _isRunning = false;

    _stopBroadcast();
    await _stopListening();

    // Save discovered devices
    await _saveKnownDevices();
  }

  Future<void> _loadKnownDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);

      if (jsonStr != null) {
        final List<dynamic> devicesList = jsonDecode(jsonStr);
        for (var device in devicesList) {
          final deviceInfo = DeviceInfo.fromJson(device);
          _discoveredDevices[deviceInfo.id] = deviceInfo;
        }
      }
    } catch (e) {
      print('Error loading known devices: $e');
    }
  }

  Future<void> _saveKnownDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _discoveredDevices.values.map((d) => d.toJson()).toList();
      await prefs.setString(_prefsKey, jsonEncode(jsonList));
    } catch (e) {
      print('Error saving known devices: $e');
    }
  }

  Future<void> _startListening() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8081);

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            _handleDiscoveryMessage(message, datagram.address.address);
          }
        }
      });

      print('Listening for device broadcasts on port 8081');
    } catch (e) {
      print('Error starting discovery listener: $e');
    }
  }

  Future<void> _stopListening() async {
    _socket?.close();
    _socket = null;
  }

  void _startBroadcast() {
    _broadcastTimer?.cancel();

    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) async {
      _sendBroadcast();

      // Also check device ports in our discovered list
      for (var device in _discoveredDevices.values) {
        _pingDevice(device);
      }
    });

    // Send first broadcast immediately
    _sendBroadcast();
  }

  void _stopBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  Future<void> _sendBroadcast() async {
    try {
      if (_socket == null) return;

      final serverAddress = await _transferService.getServerAddress();
      final port = _transferService.serverPort;

      if (serverAddress == null) return;

      final broadcastMsg = jsonEncode({
        'id': _deviceId,
        'name': _deviceName,
        'ipAddress': serverAddress,
        'port': port,
        'deviceType': PlatformUtils.getPlatformName(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      final broadcastBytes = utf8.encode(broadcastMsg);

      // Send to subnet broadcast address
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // Only IPv4 addresses
          if (addr.type == InternetAddressType.IPv4) {
            // Calculate broadcast address
            final broadcastAddress = _calculateBroadcastAddress(addr.address, 4);
            _socket!.send(broadcastBytes, InternetAddress(broadcastAddress), 8081);
          }
        }
      }
    } catch (e) {
      print('Error sending broadcast: $e');
    }
  }

  String _calculateBroadcastAddress(String ipAddress, int prefixLength) {
    // Parse the IP address
    final parts = ipAddress.split('.');
    if (parts.length != 4) return '255.255.255.255';

    // Convert to binary
    var binary = '';
    for (var part in parts) {
      var binPart = int.parse(part).toRadixString(2).padLeft(8, '0');
      binary += binPart;
    }

    // Create network part and host part
    var networkPart = binary.substring(0, prefixLength);
    var hostPart = '1' * (32 - prefixLength);

    // Combine to get broadcast address in binary
    var broadcastBinary = networkPart + hostPart;

    // Convert back to decimal
    var result = [];
    for (var i = 0; i < 4; i++) {
      var chunk = broadcastBinary.substring(i * 8, (i + 1) * 8);
      result.add(int.parse(chunk, radix: 2));
    }

    return result.join('.');
  }

  void _handleDiscoveryMessage(String message, String sourceIp) {
    try {
      final data = jsonDecode(message);

      // Ignore our own broadcasts
      if (data['id'] == _deviceId) return;

      final device = DeviceInfo(
        id: data['id'],
        name: data['name'],
        ipAddress: data['ipAddress'] ?? sourceIp,
        port: data['port'] ?? 8080,
        deviceType: data['deviceType'],
        lastSeen: DateTime.now().toIso8601String(),
      );

      _addOrUpdateDevice(device);
    } catch (e) {
      print('Error processing discovery message: $e');
    }
  }

  void _addOrUpdateDevice(DeviceInfo device) {
    bool isNewDevice = !_discoveredDevices.containsKey(device.id);
    _discoveredDevices[device.id] = device;

    if (isNewDevice) {
      _notifyDevicesChanged();
    }
  }

  void _notifyDevicesChanged() {
    if (!_deviceStreamController.isClosed) {
      _deviceStreamController.add(_discoveredDevices.values.toList());
    }
  }

  Future<void> _scanLocalNetwork() async {
    try {
      final networkInfo = NetworkInfo();
      final ip = await networkInfo.getWifiIP();
      if (ip == null) return;

      // Get the subnet prefix
      final parts = ip.split('.');
      final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

      // Scan common ports in the subnet
      for (int i = 1; i < 255; i++) {
        final targetIp = '$prefix.$i';

        // Skip our own IP
        if (targetIp == ip) continue;

        // Try common ports
        _checkDevicePort(targetIp, 8080);
      }
    } catch (e) {
      print('Error scanning network: $e');
    }
  }

  Future<void> _pingDevice(DeviceInfo device) async {
    _checkDevicePort(device.ipAddress, device.port);
  }

  Future<void> _checkDevicePort(String ip, int port) async {
    try {
      // Try to connect with a short timeout
      final uri = Uri.parse('http://$ip:$port$_discoveryEndpoint');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        try {
          final deviceData = jsonDecode(response.body);
          final device = DeviceInfo(
            id: deviceData['id'],
            name: deviceData['name'],
            ipAddress: ip,
            port: port,
            deviceType: deviceData['deviceType'],
            lastSeen: DateTime.now().toIso8601String(),
          );

          _addOrUpdateDevice(device);
        } catch (e) {
          print('Error processing device info from $ip:$port: $e');
        }
      }
    } catch (e) {
      // Connection failed or timed out (normal for most IPs)
    }
  }

  bool removeDevice(String deviceId) {
    final removed = _discoveredDevices.remove(deviceId) != null;
    if (removed) {
      _notifyDevicesChanged();
      _saveKnownDevices();
    }
    return removed;
  }

  void dispose() {
    stopDiscovery();
    _deviceStreamController.close();
  }
}