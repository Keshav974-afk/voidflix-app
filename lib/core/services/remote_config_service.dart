import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Remote configuration model received from Voidflix Mission Control Admin Panel
class RemoteAppUpdate {
  final String version;
  final int buildNumber;
  final String title;
  final List<String> releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;
  final bool enabled;

  RemoteAppUpdate({
    required this.version,
    required this.buildNumber,
    required this.title,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.forceUpdate,
    required this.enabled,
  });

  factory RemoteAppUpdate.fromJson(Map<String, dynamic> json) {
    return RemoteAppUpdate(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int? ?? 1,
      title: json['title'] as String? ?? '',
      releaseNotes: (json['releaseNotes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      downloadUrl: json['downloadUrl'] as String? ?? '/Voidflix.apk',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

class RemotePromoBanner {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String? imageUrl;
  final String actionText;
  final String actionUrl;
  final bool enabled;

  RemotePromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.imageUrl,
    required this.actionText,
    required this.actionUrl,
    required this.enabled,
  });

  factory RemotePromoBanner.fromJson(Map<String, dynamic> json) {
    return RemotePromoBanner(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      badge: json['badge'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      actionText: json['actionText'] as String? ?? 'Open',
      actionUrl: json['actionUrl'] as String? ?? '/',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class RemoteConfigService {
  static const String configEndpoint = 'https://voidflix.org/api/public/config';

  static RemoteAppUpdate? cachedUpdate;
  static List<RemotePromoBanner> cachedBanners = [];
  static Map<String, String> serverStatuses = {};
  static bool maintenanceMode = false;
  static String? maintenanceMessage;

  /// Fetches unified configuration from Voidflix Mission Control
  static Future<bool> fetchConfig() async {
    try {
      final res = await http
          .get(Uri.parse(configEndpoint))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        // 1. App Update Notice
        if (data['appUpdate'] is Map<String, dynamic>) {
          cachedUpdate = RemoteAppUpdate.fromJson(data['appUpdate']);
        }

        // 2. Promotional Banners
        if (data['banners'] is List) {
          cachedBanners = (data['banners'] as List)
              .filter((b) => b is Map<String, dynamic>)
              .map((b) => RemotePromoBanner.fromJson(b as Map<String, dynamic>))
              .toList();
        }

        // 3. Server Controls & Killswitch
        if (data['serverControls'] is Map<String, dynamic>) {
          final sc = data['serverControls'] as Map<String, dynamic>;
          maintenanceMode = sc['maintenanceMode'] as bool? ?? false;
          maintenanceMessage = sc['maintenanceMessage'] as String?;
          final rawStatuses = sc['serverStatuses'] as Map<String, dynamic>?;
          if (rawStatuses != null) {
            serverStatuses = rawStatuses.map((k, v) => MapEntry(k, v.toString()));
          }
        }

        debugPrint('RemoteConfigService: Successfully fetched configuration from Mission Control.');
        return true;
      }
    } catch (e) {
      debugPrint('RemoteConfigService: Error fetching config: $e');
    }
    return false;
  }

  /// Checks if an individual server has been turned OFF from Admin Control
  static bool isServerOnline(String serverName) {
    if (maintenanceMode) return false;
    for (final entry in serverStatuses.entries) {
      if (serverName.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value.toLowerCase() == 'online';
      }
    }
    return true;
  }
}

extension _IterableFilter<E> on Iterable<E> {
  Iterable<E> filter(bool Function(E element) test) => where(test);
}
