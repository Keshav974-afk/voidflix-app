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

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

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
      if (prefs.containsKey(_prefKey)) {
        _isTvMode = prefs.getBool(_prefKey) ?? false;
      } else {
        // Auto-enable TV mode if running on genuine TV hardware
        _isTvMode = _isHardwareTv;
      }
    } catch (_) {
      _isTvMode = _isHardwareTv;
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setTvMode(bool enabled) async {
    if (_isTvMode == enabled) return;
    _isTvMode = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}
  }

  Future<void> toggleTvMode() async {
    await setTvMode(!_isTvMode);
  }
}
