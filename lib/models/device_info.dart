class DeviceInfo {
  final String id;
  final String name;
  final String ipAddress;
  final int port;
  final String deviceType; // "Android", "Windows", etc.
  final String? lastSeen;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.port,
    required this.deviceType,
    this.lastSeen,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Device',
      ipAddress: json['ipAddress'] ?? '',
      port: json['port'] ?? 8080,
      deviceType: json['deviceType'] ?? 'Unknown',
      lastSeen: json['lastSeen'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ipAddress': ipAddress,
      'port': port,
      'deviceType': deviceType,
      'lastSeen': lastSeen,
    };
  }

  String get addressAndPort => '$ipAddress:$port';

  @override
  String toString() => '$name ($deviceType) - $ipAddress:$port';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}