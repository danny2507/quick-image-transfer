import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses;

      // Check Android version
      final androidVersion = int.tryParse(Platform.operatingSystemVersion
          .split(' ')
          .first
          .split('.')
          .first) ?? 0;

      if (androidVersion >= 13) {
        // Android 13+ (API 33+)
        statuses = await [
          Permission.photos,
          Permission.camera,
        ].request();
      } else {
        // Android 12 and below
        statuses = await [
          Permission.storage,
          Permission.camera,
        ].request();
      }

      return statuses.values.every((status) => status.isGranted);
    }

    return true; // Windows doesn't need runtime permissions
  }
}