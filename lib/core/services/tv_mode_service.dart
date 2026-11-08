import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TvModeService extends ChangeNotifier {
  static final TvModeService _instance = TvModeService._internal();
  factory TvModeService() => _instance;
  TvModeService._internal();

  static const MethodChannel _platform = MethodChannel('org.voidflix/notifications');
  static const String _prefKey = 'voidflix_tv_mode_enabled';

  bool _isTvMode = false;
  bool get isTvMode => _isTvMode;

  bool _isHardwareTv = false;
  bool get isHardwareTv => _isHardwareTv;

  bool _hasDpadDetected = false;
  bool get hasDpadDetected => _hasDpadDetected;

  bool _initialized = false;
  bool get initialized => _initialized;

  void markDpadUsed() {
    if (!_hasDpadDetected) {
      _hasDpadDetected = true;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;

    // Listen globally for any remote D-pad, arrow key, or game controller input
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);

    try {
      if (Platform.isAndroid) {
        final bool? isTv = await _platform.invokeMethod<bool>('isTelevision');
        _isHardwareTv = isTv == true;
      }
    } catch (e) {
      debugPrint('[TvModeService] Hardware check error: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPref = prefs.getBool(_prefKey);
      if (_isHardwareTv || savedPref == true) {
        _isTvMode = true;
      } else {
        _isTvMode = false;
      }
    } catch (_) {
      _isTvMode = _isHardwareTv;
    }

    if (_isTvMode && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } catch (_) {}
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> restoreSafeOrientations() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        if (_isTvMode || _isHardwareTv) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
        }
      } catch (_) {}
    }
  }

  Future<void> setTvMode(bool enabled) async {
    if (_isTvMode == enabled) return;
    _isTvMode = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}

    await restoreSafeOrientations();
  }

  Future<void> toggleTvMode() async {
    await setTvMode(!_isTvMode);
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.gameButtonSelect ||
          key == LogicalKeyboardKey.numpadEnter ||
          key.keyId == 0x00100000017 || // KEYCODE_DPAD_CENTER
          key.keyId == 23) {
        markDpadUsed();
      }
    }
    return false; // Let Flutter continue normal event processing
  }
}
