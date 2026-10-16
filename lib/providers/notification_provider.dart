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
  static const String _keyDeletedNotifs = 'voidflix_deleted_notifications';
  static const MethodChannel _nativeChannel = MethodChannel('org.voidflix/notifications');

  final ApiService _apiService = ApiService();

  List<AppNotification> _notifications = [];
  final Set<String> _deletedIds = {};
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

    final savedDeleted = prefs.getStringList(_keyDeletedNotifs) ?? [];
    _deletedIds.addAll(savedDeleted);

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
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    try {
      final List<AppNotification> list = [];
      final Set<String> seenItemIds = {};

      // 1. Fetch live admin broadcasts & automated push from Mission Control
      await RemoteConfigService.fetchConfig();
      final adminBroadcasts = RemoteConfigService.cachedNotifications;

      for (final n in adminBroadcasts) {
        final notifId = 'admin_${n.id}';
        // Skip deleted notifications
        if (_deletedIds.contains(notifId)) continue;
        // Skip notifications older than 14 days
        if (n.sentAt.isBefore(now.subtract(const Duration(days: 14)))) continue;
        // Respect targeting: skip notifications targeted strictly to web browsers
        if (n.target.toLowerCase() == 'web') continue;

        final sentEpoch = n.sentAt.millisecondsSinceEpoch;
        final isSeen = _lastSeenEpoch >= sentEpoch;
        seenItemIds.add(notifId);

        list.add(
          AppNotification(
            id: notifId,
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
        if (!_deletedIds.contains(topId)) {
          seenItemIds.add(topId);
          list.add(
            AppNotification(
              id: topId,
              title: '🔥 #1 Trending Today: ${top.title}',
              message: 'Stream the most watched title right now on Voidflix with zero wait time.',
              timestamp: now,
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
      }

      // Add upcoming movie updates (pruning old or deleted ones)
      for (final item in upcoming.take(6)) {
        final upId = 'upcoming_${item.id}';
        if (_deletedIds.contains(upId)) continue;

        final releaseDate = item.releaseDate ?? '';
        final itemTimestamp = DateTime.tryParse(releaseDate) ?? now;
        // Don't show releases older than 7 days
        if (itemTimestamp.isBefore(sevenDaysAgo)) continue;

        seenItemIds.add(upId);
        list.add(
          AppNotification(
            id: upId,
            title: '🎬 Coming Soon: ${item.title}',
            message: releaseDate.isNotEmpty
                ? 'Arriving in theaters & streaming on $releaseDate. Tap for details!'
                : 'Added to upcoming premieres list.',
            timestamp: itemTimestamp,
            mediaItem: item,
            isRead: _lastSeenEpoch >= itemTimestamp.millisecondsSinceEpoch,
          ),
        );
      }

      // Fire Welcome to Voidflix device status bar notification on first launch
      final welcomeSent = prefs.getBool(_keyWelcomeSent) ?? false;
      if (!welcomeSent && !_deletedIds.contains('welcome')) {
        await prefs.setBool(_keyWelcomeSent, true);
        await showDeviceNotification(
          id: 1001,
          title: '🎉 Welcome to Voidflix!',
          body: 'Enjoy unlimited 4K Ultra HD movies, series & live IPTV channels with zero ads.',
        );
      }

      // Sort notifications by timestamp descending (newest first)
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _notifications = list.take(20).toList();
    } catch (err) {
      debugPrint('NotificationProvider error: $err');
      if (!_deletedIds.contains('welcome')) {
        _notifications = [
          AppNotification(
            id: 'welcome',
            title: '🎉 Welcome to Voidflix!',
            message: 'Enjoy unlimited HD movies, TV shows, and Live IPTV channels on Voidflix.',
            timestamp: DateTime.now(),
            isRead: false,
          ),
        ];
      } else {
        _notifications = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete an individual notification and persist its ID so it never resurfaces
  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    _deletedIds.add(id);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyDeletedNotifs, _deletedIds.toList());
    } catch (e) {
      debugPrint('Error saving deleted notification: $e');
    }
  }

  /// Clear all notifications and mark as caught up
  Future<void> clearAllNotifications() async {
    for (final n in _notifications) {
      _deletedIds.add(n.id);
    }
    _notifications.clear();
    _lastSeenEpoch = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySeenTimestamp, _lastSeenEpoch);
      await prefs.setStringList(_keyDeletedNotifs, _deletedIds.toList());
    } catch (e) {
      debugPrint('Error clearing notifications: $e');
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
