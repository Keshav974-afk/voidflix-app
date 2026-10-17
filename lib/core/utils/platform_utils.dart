import 'dart:io';
import 'package:flutter/foundation.dart';

class PlatformUtils {
  /// Whether the platform officially supports `package:webview_flutter`
  static bool get isWebViewSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Whether running on a desktop operating system (Windows, Linux, macOS)
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether running specifically on Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;
}
