import 'package:flutter/material.dart';
import '../models/device_info.dart';
import '../services/device_discovery_service.dart';
import '../utils/platform_utils.dart';

class DeviceListScreen extends StatefulWidget {
  final DeviceDiscoveryService discoveryService;
  final Function(DeviceInfo) onDeviceSelected;

  const DeviceListScreen({
    Key? key,
    required this.discoveryService,
    required this.onDeviceSelected,
  }) : super(key: key);

  @override
  _DeviceListScreenState createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final TextEditingController _deviceNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start discovery if not already running
    if (!widget.discoveryService.isRunning) {
      widget.discoveryService.startDiscovery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              widget.discoveryService.stopDiscovery();
              widget.discoveryService.startDiscovery();
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Your Device Name',
            onPressed: _showDeviceNameDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Your Device: ${PlatformUtils.getPlatformName()} (${widget.discoveryService.deviceId})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DeviceInfo>>(
              stream: widget.discoveryService.devicesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No devices found',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Make sure other devices are on the same network\nand have the app running',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan Again'),
                          onPressed: () {
                            widget.discoveryService.stopDiscovery();
                            widget.discoveryService.startDiscovery();
                          },
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isOnline = true; // Add online check if needed

                    return ListTile(
                      leading: Icon(
                        _getDeviceIcon(device.deviceType),
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                      title: Text(device.name),
                      subtitle: Text('${device.deviceType} - ${device.ipAddress}:${device.port}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          widget.discoveryService.removeDevice(device.id);
                        },
                        tooltip: 'Remove device',
                      ),
                      onTap: () {
                        widget.onDeviceSelected(device);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.computer;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.laptop;
      default:
        return Icons.devices_other;
    }
  }

  void _showDeviceNameDialog() {
    _deviceNameController.text = widget.discoveryService.deviceId;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Your Device Name'),
          content: TextField(
            controller: _deviceNameController,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              hintText: 'Enter a name for your device',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                widget.discoveryService.setCustomDeviceName(
                  _deviceNameController.text.trim(),
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }
}