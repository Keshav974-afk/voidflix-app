import 'dart:io';
import 'package:flutter/foundation.dart';

class AppLogger {
  static final AppLogger instance = AppLogger._internal();
  factory AppLogger() => instance;
  AppLogger._internal();

  File? _logFile;
  File? _tempLogFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final tempDir = Directory.systemTemp;
      _tempLogFile = File('${tempDir.path}/voidflix.log');

      if (Platform.isWindows) {
        final localAppData = Platform.environment['LOCALAPPDATA'];
        if (localAppData != null && localAppData.isNotEmpty) {
          final dir = Directory('$localAppData/Voidflix');
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          _logFile = File('${dir.path}/voidflix.log');
        }
      }

      log('AppLogger', '=== Voidflix Session Started (${DateTime.now().toIso8601String()}) ===');
      log('AppLogger', 'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    } catch (e) {
      debugPrint('[AppLogger] Failed to initialize file logger: $e');
    }
  }

  void log(String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$tag] $message';
    debugPrint(line);

    try {
      _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}

    try {
      _tempLogFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void error(String tag, String message, [dynamic error, StackTrace? stack]) {
    final errStr = error != null ? ' | Error: $error' : '';
    final stackStr = stack != null ? '\n$stack' : '';
    log(tag, 'ERROR: $message$errStr$stackStr');
  }

  String? get logFilePath => _logFile?.path ?? _tempLogFile?.path;
}
