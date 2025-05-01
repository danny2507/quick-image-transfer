import 'dart:io';
import 'package:flutter/foundation.dart';

class PlatformUtils {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool get isMobile =>
      Platform.isAndroid || Platform.isIOS;

  static bool get isWindows => Platform.isWindows;

  static bool get isAndroid => Platform.isAndroid;

  static String getPlatformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}