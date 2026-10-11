import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_config_service.dart';

/// App Analytics & Deep Hardware Fingerprinting Service for Voidflix
/// Extracts stable hardware identifiers so devices are counted as exactly 1
/// regardless of IP switches (cellular, Wi-Fi, VPNs, travelling).
class AppAnalyticsService {
  static const String _pingEndpoint = 'https://voidflix.org/api/public/analytics/ping';
  static const String _deviceUuidKey = 'voidflix_device_uuid';
  static const MethodChannel _nativeChannel = MethodChannel('org.voidflix/notifications');

  static String? _cachedDeviceId;
  static String? get cachedDeviceId => _cachedDeviceId;
  static Map<String, dynamic>? _cachedFingerprint;

  /// Retrieves or creates an unforgeable, persistent Device Hardware Fingerprint
  static Future<Map<String, dynamic>> getHardwareFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceUuidKey);

    Map<String, dynamic> nativeDetails = {};
    try {
      final res = await _nativeChannel.invokeMethod('getDeviceFingerprint');
      if (res is Map) {
        nativeDetails = Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('Error reading native device fingerprint: $e');
    }

    final androidId = (nativeDetails['androidId'] ?? '').toString();
    final model = (nativeDetails['model'] ?? '').toString();
    final brand = (nativeDetails['brand'] ?? '').toString();
    final board = (nativeDetails['board'] ?? '').toString();
    final hardware = (nativeDetails['hardware'] ?? '').toString();
    final abis = (nativeDetails['abis'] ?? '').toString();
    final release = (nativeDetails['release'] ?? '').toString();
    final sdkInt = (nativeDetails['sdkInt'] ?? '').toString();
    final screenW = (nativeDetails['screenWidth'] ?? '').toString();
    final screenH = (nativeDetails['screenHeight'] ?? '').toString();

    // If no UUID yet, generate a stable one incorporating androidId if available
    if (id == null || id.isEmpty) {
      if (androidId.isNotEmpty && androidId != '9774d56d682e549c') {
        id = 'dev_aid_${androidId.toLowerCase()}';
      } else {
        id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      }
      await prefs.setString(_deviceUuidKey, id);
    }
    _cachedDeviceId = id;

    // Generate stable hardware hash
    final rawHardwareString = '$id|$androidId|$brand|$model|$board|$hardware|$screenW x $screenH';
    final hardwareHash = 'hw_${rawHardwareString.hashCode.abs().toRadixString(16)}';

    _cachedFingerprint = {
      'fingerprintId': id,
      'deviceId': id,
      'hardwareHash': hardwareHash,
      'androidId': androidId,
      'brand': brand,
      'model': model.isNotEmpty ? model : 'Android Device',
      'board': board,
      'hardware': hardware,
      'cpuAbi': abis,
      'screenResolution': screenW.isNotEmpty && screenH.isNotEmpty ? '${screenW}x$screenH' : '1080x2400',
      'osVersion': release.isNotEmpty ? 'Android $release (API $sdkInt)' : Platform.operatingSystemVersion,
      'platform': 'android',
      'timezone': DateTime.now().timeZoneName,
      'locale': Platform.localeName,
    };

    return _cachedFingerprint!;
  }

  /// Sends a rich heartbeat ping with deep device fingerprint to Voidflix Mission Control
  static Future<bool> sendPing() async {
    try {
      final fp = await getHardwareFingerprint();
      final deviceId = fp['deviceId'] as String;
      final model = fp['model'] as String;
      final brand = fp['brand'] as String;
      final osVersion = fp['osVersion'] as String;

      final deviceDisplay = brand.isNotEmpty && !model.toLowerCase().contains(brand.toLowerCase())
          ? '$brand $model'
          : model;

      final body = jsonEncode({
        'deviceId': deviceId,
        'fingerprintId': deviceId,
        'hardwareHash': fp['hardwareHash'],
        'appVersion': RemoteConfigService.currentAppVersion,
        'deviceModel': deviceDisplay,
        'osVersion': osVersion,
        'platform': 'android',
        'isNativeApp': true,
        'source': 'voidflix_flutter_app',
        'fingerprint': fp,
      });

      final res = await http
          .post(
            Uri.parse(_pingEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        debugPrint('AppAnalyticsService: Fingerprint ping OK (Device: $deviceId)');
        return true;
      }
    } catch (e) {
      debugPrint('AppAnalyticsService: Ping error: $e');
    }
    return false;
  }
}
