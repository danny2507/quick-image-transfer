import 'dart:convert';
import 'device_info.dart';

class TransferHistoryEntry {
  final String id;
  final DateTime timestamp;
  final String fileName;
  final int fileSize;
  final String filePath;
  final String direction; // "sent" or "received"
  final DeviceInfo targetDevice;
  final bool successful;
  final String? errorMessage;

  TransferHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.fileName,
    required this.fileSize,
    required this.filePath,
    required this.direction,
    required this.targetDevice,
    required this.successful,
    this.errorMessage,
  });

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TransferHistoryEntry(
      id: json['id'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      fileName: json['fileName'] ?? '',
      fileSize: json['fileSize'] ?? 0,
      filePath: json['filePath'] ?? '',
      direction: json['direction'] ?? '',
      targetDevice: DeviceInfo.fromJson(json['targetDevice'] ?? {}),
      successful: json['successful'] ?? false,
      errorMessage: json['errorMessage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'fileName': fileName,
      'fileSize': fileSize,
      'filePath': filePath,
      'direction': direction,
      'targetDevice': targetDevice.toJson(),
      'successful': successful,
      'errorMessage': errorMessage,
    };
  }
}

class TransferHistory {
  final List<TransferHistoryEntry> entries;

  TransferHistory({
    required this.entries,
  });

  factory TransferHistory.empty() {
    return TransferHistory(entries: []);
  }

  factory TransferHistory.fromJson(String jsonStr) {
    final List<dynamic> jsonList = json.decode(jsonStr);
    return TransferHistory(
      entries: jsonList
          .map((e) => TransferHistoryEntry.fromJson(e))
          .toList(),
    );
  }

  String toJson() {
    return json.encode(entries.map((e) => e.toJson()).toList());
  }

  TransferHistory addEntry(TransferHistoryEntry entry) {
    return TransferHistory(
      entries: [...entries, entry],
    );
  }

  TransferHistory get sortedByTime {
    final sortedEntries = [...entries];
    sortedEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return TransferHistory(entries: sortedEntries);
  }
}