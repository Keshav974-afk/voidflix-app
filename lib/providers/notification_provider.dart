import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_service.dart';
import '../core/services/remote_config_service.dart';
import '../models/media_item.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final MediaItem? mediaItem;
  final bool isRead;
  final String? deepLink;
  final String? imageUrl;
  final bool isAdminBroadcast;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.mediaItem,
    this.isRead = false,
    this.deepLink,
    this.imageUrl,
    this.isAdminBroadcast = false,
  });
}

class NotificationProvider extends ChangeNotifier {
  static const String _keySeenTimestamp = 'voidflix_last_seen_notif';
  static const String _keyPushEnabled = 'voidflix_notifications_enabled';
  static const String _keyWelcomeSent = 'voidflix_welcome_notif_sent';
  static const String _keyLastTrendingSent = 'voidflix_last_trending_notified';
  static const MethodChannel _nativeChannel = MethodChannel('org.voidflix/notifications');

  final ApiService _apiService = ApiService();

  List<AppNotification> _notifications = [];
  bool _isLoading = false;
  bool _notificationsEnabled = true;
  int _lastSeenEpoch = 0;

  List<AppNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  bool get notificationsEnabled => _notificationsEnabled;

  int get unreadCount {
    return _notifications.where((n) => !n.isRead).length;
  }

  NotificationProvider() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isFirstRun = !prefs.containsKey(_keySeenTimestamp);

    if (isFirstRun) {
      // For new users, set last seen to NOW so past notifications are never fired or marked unread!
      _lastSeenEpoch = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_keySeenTimestamp, _lastSeenEpoch);

      // Pre-seed all existing notification IDs so no historic alerts trigger
      await RemoteConfigService.fetchConfig();
      for (final n in RemoteConfigService.cachedNotifications) {
        await prefs.setBool('admin_notified_${n.id}', true);
      }
    } else {
      _lastSeenEpoch = prefs.getInt(_keySeenTimestamp) ?? DateTime.now().millisecondsSinceEpoch;
    }

    _notificationsEnabled = prefs.getBool(_keyPushEnabled) ?? true;
    await fetchUpdates();
  }

  /// Sends a real system notification that appears in the device status bar
  Future<void> showDeviceNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_notificationsEnabled) return;

    try {
      await _nativeChannel.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('Error posting native device notification: $e');
    }
  }

  Future<void> fetchUpdates() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    try {
      final List<AppNotification> list = [];

      // 1. Fetch live admin broadcasts & automated push from Mission Control
      await RemoteConfigService.fetchConfig();
      final adminBroadcasts = RemoteConfigService.cachedNotifications;

      for (final n in adminBroadcasts) {
        // Respect targeting: skip notifications targeted strictly to web browsers
        if (n.target.toLowerCase() == 'web') continue;

        final sentEpoch = n.sentAt.millisecondsSinceEpoch;
        final isSeen = _lastSeenEpoch >= sentEpoch;
        list.add(
          AppNotification(
            id: 'admin_${n.id}',
            title: n.title,
            message: n.body,
            timestamp: n.sentAt,
            isRead: isSeen,
            deepLink: n.deepLink,
            imageUrl: n.imageUrl,
            isAdminBroadcast: true,
          ),
        );

        // Only fire native status bar alert if it was dispatched AFTER user's last seen epoch
        final notifiedKey = 'admin_notified_${n.id}';
        if (!prefs.containsKey(notifiedKey) && !isSeen) {
          await prefs.setBool(notifiedKey, true);
          await showDeviceNotification(
            id: n.id.hashCode.abs() % 100000,
            title: n.title,
            body: n.body,
          );
        }
      }

      // 2. Fetch TMDB Upcoming & Trending items
      final upcoming = await _apiService.getUpcomingMovies().catchError((_) => <MediaItem>[]);
      final trending = await _apiService.getTrendingAll().catchError((_) => <MediaItem>[]);

      // Add trending top pick notification
      if (trending.isNotEmpty) {
        final top = trending.first;
        final topId = 'top_${top.id}';
        list.add(
          AppNotification(
            id: topId,
            title: '🔥 #1 Trending Today: ${top.title}',
            message: 'Stream the most watched title right now on Voidflix with zero wait time.',
            timestamp: DateTime.now(),
            mediaItem: top,
            isRead: false,
          ),
        );

        // Fire device status bar notification for new trending title
        final lastTrendingNotif = prefs.getString(_keyLastTrendingSent);
        if (lastTrendingNotif != topId) {
          await prefs.setString(_keyLastTrendingSent, topId);
          await showDeviceNotification(
            id: top.id,
            title: '🔥 #1 Trending on Voidflix: ${top.title}',
            body: 'Stream now in 4K HDR on Voidflix with zero wait time.',
          );
        }
      }

      // Add upcoming movie updates
      for (final item in upcoming.take(6)) {
        final releaseDate = item.releaseDate ?? '';
        list.add(
          AppNotification(
            id: 'upcoming_${item.id}',
            title: '🎬 Coming Soon: ${item.title}',
            message: releaseDate.isNotEmpty
                ? 'Arriving in theaters & streaming on $releaseDate. Tap for details!'
                : 'Added to upcoming premieres list.',
            timestamp: DateTime.tryParse(releaseDate) ?? DateTime.now(),
            mediaItem: item,
            isRead: _lastSeenEpoch >= (DateTime.tryParse(releaseDate)?.millisecondsSinceEpoch ?? 0),
          ),
        );
      }

      // Fire Welcome to Voidflix device status bar notification on first launch
      final welcomeSent = prefs.getBool(_keyWelcomeSent) ?? false;
      if (!welcomeSent) {
        await prefs.setBool(_keyWelcomeSent, true);
        await showDeviceNotification(
          id: 1001,
          title: '🎉 Welcome to Voidflix!',
          body: 'Enjoy unlimited 4K Ultra HD movies, series & live IPTV channels with zero ads.',
        );
      }

      _notifications = list;
    } catch (err) {
      debugPrint('NotificationProvider error: $err');
      _notifications = [
        AppNotification(
          id: 'welcome',
          title: '🎉 Welcome to Voidflix!',
          message: 'Enjoy unlimited HD movies, TV shows, and Live IPTV channels on Voidflix.',
          timestamp: DateTime.now(),
          isRead: false,
        ),
      ];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAllAsRead() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastSeenEpoch = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySeenTimestamp, now);

    _notifications = _notifications
        .map((n) => AppNotification(
              id: n.id,
              title: n.title,
              message: n.message,
              timestamp: n.timestamp,
              mediaItem: n.mediaItem,
              isRead: true,
              deepLink: n.deepLink,
              imageUrl: n.imageUrl,
              isAdminBroadcast: n.isAdminBroadcast,
            ))
        .toList();
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPushEnabled, enabled);

    if (enabled) {
      await showDeviceNotification(
        id: 9999,
        title: '🔔 Voidflix Notifications Active',
        body: 'You will receive alerts for new 4K releases, admin updates, and trending shows.',
      );
    }
  }
}
