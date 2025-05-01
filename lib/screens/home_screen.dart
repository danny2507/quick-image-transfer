import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/transfer_service.dart';
import '../services/permission_service.dart';
import '../services/device_discovery_service.dart';
import '../utils/file_utils.dart';
import '../utils/platform_utils.dart';
import '../models/device_info.dart';
import 'qr_scanner_screen.dart';
import 'device_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TransferService _service = TransferService();
  late final DeviceDiscoveryService _discoveryService = DeviceDiscoveryService(_service);

  String? _serverAddress;
  bool _isServer = false;
  bool _isLoading = false;
  String? _selectedImagePath;
  DeviceInfo? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _checkPermissions();

    // Start device discovery if we're on Android
    if (PlatformUtils.isMobile) {
      _discoveryService.startDiscovery();
    }
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      await PermissionService.requestPermissions();
    }
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Transfer'),
        actions: [
          if (_isServer)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopServer,
              tooltip: 'Stop server',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedImagePath != null)
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.file(
                  File(_selectedImagePath!),
                  fit: BoxFit.contain,
                ),
              ),
            ),

          Expanded(
            flex: _selectedImagePath != null ? 2 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (PlatformUtils.isDesktop && !_isServer)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Receive Images'),
                    onPressed: _startReceiving,
                  ),

                if (PlatformUtils.isDesktop && _isServer && _serverAddress != null)
                  Column(
                    children: [
                      Text('Server running at $_serverAddress',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      QrImageView(
                        data: _serverAddress!,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ],
                  ),

                if (PlatformUtils.isMobile)
                  Column(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Select Image'),
                        onPressed: _selectImage,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.devices),
                        label: Text(_selectedDevice == null
                            ? 'Select Device'
                            : 'Send to ${_selectedDevice!.name}'),
                        onPressed: _openDeviceList,
                      ),

                      // Show QR scan button if no device or server address is selected
                      if (_serverAddress == null && _selectedDevice == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Scan QR Code'),
                            onPressed: _scanQRCode,
                          ),
                        ),

                      // Send button should appear if we have both an image and either a device or server address
                      if (_selectedImagePath != null && (_selectedDevice != null || _serverAddress != null))
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.send),
                            label: const Text('Send Image'),
                            onPressed: _sendImage,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startReceiving() async {
    setState(() => _isLoading = true);
    try {
      _serverAddress = await _service.startServer();
      _isServer = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting server: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _stopServer() async {
    setState(() => _isLoading = true);
    await _service.stopServer();
    if (mounted) {
      setState(() {
        _isServer = false;
        _serverAddress = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectImage() async {
    if (PlatformUtils.isMobile) {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false, // Optimize for faster loading
      );

      if (image != null && mounted) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } else {
      // Desktop implementation
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'images',
        extensions: <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );

      if (file != null && mounted) {
        setState(() {
          _selectedImagePath = file.path;
        });
      }
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _serverAddress = result;

        // When scanning a QR code, clear any selected devices
        // Since we're directly using the server address
        _selectedDevice = null;
      });

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to server: $_serverAddress')),
      );
    }
  }

  void _openDeviceList() async {
    // Make sure discovery is running
    if (!_discoveryService.isRunning) {
      _discoveryService.startDiscovery();
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceListScreen(
          discoveryService: _discoveryService,
          onDeviceSelected: (device) {
            setState(() {
              _selectedDevice = device;
              _serverAddress = device.addressAndPort;
            });
          },
        ),
      ),
    );

    // If we got a direct result (some implementations might return the device)
    if (result is DeviceInfo && mounted) {
      setState(() {
        _selectedDevice = result;
        _serverAddress = result.addressAndPort;
      });
    }
  }

  Future<void> _sendImage() async {
    if (_serverAddress == null || _selectedImagePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server address or image not selected')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await _service.sendImage(
        _serverAddress!,
        _selectedImagePath!,
        _selectedDevice,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? _selectedDevice != null
                ? 'Image sent successfully to ${_selectedDevice!.name}!'
                : 'Image sent successfully!'
                : 'Failed to send image'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Utility method to show an error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Show a confirmation dialog with options
  Future<bool> _showConfirmationDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}