import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../models/transfer_history.dart';
import '../services/transfer_service.dart';

class TransferHistoryScreen extends StatefulWidget {
  final TransferService transferService;

  const TransferHistoryScreen({
    Key? key,
    required this.transferService,
  }) : super(key: key);

  @override
  _TransferHistoryScreenState createState() => _TransferHistoryScreenState();
}

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  TransferHistory? _history;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = await widget.transferService.getTransferHistory();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear History',
            onPressed: _confirmClearHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildHistoryList(),
    );
  }

  Widget _buildHistoryList() {
    if (_history == null || _history!.entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No transfer history',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your file transfer history will appear here',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final sortedEntries = _history!.sortedByTime.entries;
    final dateFormat = DateFormat('MMM d, yyyy - h:mm a');

    return ListView.builder(
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Icon(
              entry.direction == 'sent' ? Icons.upload : Icons.download,
              color: entry.successful ? Colors.green : Colors.red,
              size: 28,
            ),
            title: Text(
              entry.fileName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateFormat.format(entry.timestamp)),
                Text(
                  '${entry.direction == 'sent' ? 'To' : 'From'}: ${entry.targetDevice.name}',
                ),
                Text(_formatFileSize(entry.fileSize)),
                if (!entry.successful && entry.errorMessage != null)
                  Text(
                    'Error: ${entry.errorMessage}',
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
            isThreeLine: true,
            trailing: entry.successful
                ? IconButton(
              icon: Icon(
                Platform.isWindows ? Icons.folder_open : Icons.open_in_new,
              ),
              tooltip: 'Open file location',
              onPressed: () => _openFile(entry.filePath),
            )
                : null,
            onTap: () => _showTransferDetails(entry),
          ),
        );
      },
    );
  }

  void _showTransferDetails(TransferHistoryEntry entry) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Transfer Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailItem('File', entry.fileName),
                _detailItem('Size', _formatFileSize(entry.fileSize)),
                _detailItem('Date', DateFormat('MMM d, yyyy').format(entry.timestamp)),
                _detailItem('Time', DateFormat('h:mm:ss a').format(entry.timestamp)),
                _detailItem('Direction', entry.direction == 'sent' ? 'Sent' : 'Received'),
                _detailItem('Device', entry.targetDevice.name),
                _detailItem('Device Type', entry.targetDevice.deviceType),
                _detailItem('IP Address', entry.targetDevice.ipAddress),
                _detailItem('Status', entry.successful ? 'Successful' : 'Failed'),
                if (!entry.successful && entry.errorMessage != null)
                  _detailItem('Error', entry.errorMessage!),
                _detailItem('Path', entry.filePath),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
            if (entry.successful)
              TextButton(
                onPressed: () {
                  _openFile(entry.filePath);
                  Navigator.pop(context);
                },
                child: Text(Platform.isWindows ? 'Open Location' : 'Open'),
              ),
          ],
        );
      },
    );
  }

  Widget _detailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16),
          ),
          const Divider(),
        ],
      ),
    );
  }

  String _formatFileSize(int sizeInBytes) {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    } else if (sizeInBytes < 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  void _openFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      if (Platform.isWindows) {
        // On Windows, open the file explorer to the file location
        final directory = path.substring(0, path.lastIndexOf('\\'));
        Process.run('explorer.exe', [directory]);
      } else if (Platform.isAndroid) {
        // On Android, you'd use intent to open the file
        // This requires using a package like url_launcher or open_file
      }
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('File Not Found'),
          content: const Text('The file no longer exists at the specified location.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text(
          'This will clear your transfer history. The files themselves will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await widget.transferService.clearTransferHistory();
              _loadHistory();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}