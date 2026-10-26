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
  final String? arm64Url;
  final String? armeabiUrl;
  final String? x86_64Url;
  final bool forceUpdate;
  final bool enabled;
  final String? publishedAt;

  RemoteAppUpdate({
    required this.version,
    required this.buildNumber,
    required this.title,
    required this.releaseNotes,
    required this.downloadUrl,
    this.arm64Url,
    this.armeabiUrl,
    this.x86_64Url,
    required this.forceUpdate,
    required this.enabled,
    this.publishedAt,
  });

  factory RemoteAppUpdate.fromJson(Map<String, dynamic> json) {
    return RemoteAppUpdate(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int? ?? 1,
      title: json['title'] as String? ?? 'New Voidflix Update',
      releaseNotes: (json['releaseNotes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      downloadUrl: json['downloadUrl'] as String? ?? '/Voidflix.apk',
      arm64Url: json['arm64Url'] as String?,
      armeabiUrl: json['armeabiUrl'] as String?,
      x86_64Url: json['x86_64Url'] as String?,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      publishedAt: json['publishedAt'] as String?,
    );
  }
}

class RemotePromoBanner {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String? rating;
  final String? qualityBadge;
  final String? imageUrl;
  final String? backdropUrl;
  final String actionText;
  final String actionUrl;
  final String? secondaryActionText;
  final String? secondaryActionUrl;
  final String position; // 'popup_modal' | 'featured_section' | 'hero_billboard'
  final String targetPlatform; // 'all' | 'app' | 'web'
  final bool enabled;
  final bool dismissible;

  RemotePromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.rating,
    this.qualityBadge,
    this.imageUrl,
    this.backdropUrl,
    required this.actionText,
    required this.actionUrl,
    this.secondaryActionText,
    this.secondaryActionUrl,
    required this.position,
    this.targetPlatform = 'all',
    required this.enabled,
    required this.dismissible,
  });

  factory RemotePromoBanner.fromJson(Map<String, dynamic> json) {
    return RemotePromoBanner(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      badge: json['badge'] as String? ?? 'FEATURED',
      rating: json['rating'] as String?,
      qualityBadge: json['qualityBadge'] as String?,
      imageUrl: json['imageUrl'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      actionText: json['actionText'] as String? ?? 'Explore',
      actionUrl: json['actionUrl'] as String? ?? '/',
      secondaryActionText: json['secondaryActionText'] as String?,
      secondaryActionUrl: json['secondaryActionUrl'] as String?,
      position: json['position'] as String? ?? 'popup_modal',
      targetPlatform: json['targetPlatform'] as String? ?? 'all',
      enabled: json['enabled'] as bool? ?? true,
      dismissible: json['dismissible'] as bool? ?? true,
    );
  }
}

class RemoteNotificationItem {
  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final String? deepLink;
  final String target;
  final String priority;
  final DateTime sentAt;

  RemoteNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    this.deepLink,
    required this.target,
    required this.priority,
    required this.sentAt,
  });

  factory RemoteNotificationItem.fromJson(Map<String, dynamic> json) {
    return RemoteNotificationItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Voidflix Update',
      body: json['body'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      deepLink: json['deepLink'] as String?,
      target: json['target'] as String? ?? 'all',
      priority: json['priority'] as String? ?? 'normal',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class RemoteConfigService {
  static const String configEndpoint = 'https://voidflix.org/api/public/config';
  static const String currentAppVersion = '0.4.0';
  static const int currentBuildNumber = 5;

  static RemoteAppUpdate? cachedUpdate;
  static List<RemotePromoBanner> cachedBanners = [];
  static List<RemoteNotificationItem> cachedNotifications = [];
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
              .whereType<Map<String, dynamic>>()
              .map((b) => RemotePromoBanner.fromJson(b))
              .toList();
        }

        // 3. Notification History Broadcasts
        if (data['notificationHistory'] is List) {
          cachedNotifications = (data['notificationHistory'] as List)
              .whereType<Map<String, dynamic>>()
              .map((n) => RemoteNotificationItem.fromJson(n))
              .toList();
        }

        // 4. Server Controls & Killswitch
        if (data['serverControls'] is Map<String, dynamic>) {
          final sc = data['serverControls'] as Map<String, dynamic>;
          maintenanceMode = sc['maintenanceMode'] as bool? ?? false;
          maintenanceMessage = sc['maintenanceMessage'] as String?;
          final rawStatuses = sc['serverStatuses'] as Map<String, dynamic>?;
          if (rawStatuses != null) {
            serverStatuses = rawStatuses.map((k, v) => MapEntry(k, v.toString()));
          }
        }

        debugPrint('RemoteConfigService: Synced configuration from Mission Control.');
        return true;
      }
    } catch (e) {
      debugPrint('RemoteConfigService: Error fetching config: $e');
    }
    return false;
  }

  /// Evaluates whether an app update is available
  static bool get isUpdateAvailable {
    final update = cachedUpdate;
    if (update == null || !update.enabled) return false;
    if (update.buildNumber > currentBuildNumber) return true;
    return _isVersionHigher(update.version, currentAppVersion);
  }

  static bool _isVersionHigher(String remote, String current) {
    // If remote is legacy 1.x but current app has transitioned to 0.2+, ignore legacy 1.x
    if (remote.startsWith('1.') && (current.startsWith('0.') || current == '0.2')) {
      return false;
    }
    try {
      final remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Resolves full APK download URL
  static String get resolvedApkUrl {
    final update = cachedUpdate;
    if (update == null) return 'https://voidflix.org/Voidflix.apk';
    final raw = update.downloadUrl;
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return 'https://voidflix.org$raw';
    return 'https://voidflix.org/$raw';
  }

  /// Checks if an active popup banner is pending for mobile app
  static RemotePromoBanner? get activePopupBanner {
    for (final b in cachedBanners) {
      if (b.enabled &&
          b.position == 'popup_modal' &&
          (b.targetPlatform == 'app' || b.targetPlatform == 'all')) {
        return b;
      }
    }
    return null;
  }

  /// Checks if an active hero promotional billboard is configured for mobile app
  static RemotePromoBanner? get activeBillboardBanner {
    for (final b in cachedBanners) {
      if (b.enabled &&
          (b.position == 'hero_billboard' || b.position == 'featured_section') &&
          (b.targetPlatform == 'app' || b.targetPlatform == 'all')) {
        return b;
      }
    }
    return null;
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
