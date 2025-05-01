import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  static Future<String> getAppSaveDirectory() async {
    if (Platform.isWindows) {
      final directory = await getDownloadsDirectory();
      return directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else {
      return (await getApplicationDocumentsDirectory()).path;
    }
  }

  static Future<String> getUniqueFileName(String baseName) async {
    final dir = await getAppSaveDirectory();
    final baseFileName = baseName.split('/').last.split('\\').last;
    final path = '$dir/$baseFileName';

    if (!await File(path).exists()) {
      return path;
    }

    // If file exists, add number
    int counter = 1;
    String fileName = baseFileName;
    final extension = fileName.contains('.')
        ? '.${fileName.split('.').last}'
        : '';
    final nameWithoutExtension = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    while (await File('$dir/${nameWithoutExtension}_$counter$extension').exists()) {
      counter++;
    }

    return '$dir/${nameWithoutExtension}_$counter$extension';
  }
}