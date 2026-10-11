import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_config_service.dart';

/// App Analytics & Telemetry Service for Voidflix
/// Registers the user device, tracks active app usage, and reports version compliance.
class AppAnalyticsService {
  static const String _pingEndpoint = 'https://voidflix.org/api/public/analytics/ping';
  static const String _deviceUuidKey = 'voidflix_device_uuid';

  static String? _cachedDeviceId;

  /// Retrieves or generates a unique, persistent Device ID for this installation
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceUuidKey);
    if (id == null || id.isEmpty) {
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString(_deviceUuidKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// Sends a lightweight heartbeat ping to Voidflix Mission Control
  static Future<bool> sendPing() async {
    try {
      final deviceId = await getDeviceId();
      final osVersion = Platform.operatingSystemVersion;
      final platform = Platform.operatingSystem;

      final body = jsonEncode({
        'deviceId': deviceId,
        'appVersion': RemoteConfigService.currentAppVersion,
        'deviceModel': 'Android Mobile Device',
        'osVersion': osVersion,
        'platform': platform,
      });

      final res = await http
          .post(
            Uri.parse(_pingEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint('AppAnalyticsService: Ping successful (Total Downloads: ${data['totalDownloads']})');
        return true;
      }
    } catch (e) {
      debugPrint('AppAnalyticsService: Ping error: $e');
    }
    return false;
  }
}
