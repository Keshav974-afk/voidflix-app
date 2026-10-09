import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final MediaItem? mediaItem;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.mediaItem,
    this.isRead = false,
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
    _lastSeenEpoch = prefs.getInt(_keySeenTimestamp) ?? 0;
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
      final upcoming = await _apiService.getUpcomingMovies();
      final trending = await _apiService.getTrendingAll();

      final List<AppNotification> list = [];

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

      // Add trending top pick notification
      if (trending.isNotEmpty) {
        final top = trending.first;
        final topId = 'top_${top.id}';
        list.insert(
          0,
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
    } catch (_) {
      // Fallback notifications if network is offline
      _notifications = [
        AppNotification(
          id: 'welcome',
          title: '🎉 Welcome to Voidflix!',
          message: 'Enjoy unlimited HD movies, TV shows, and Live IPTV channels on Voidflix.',
          timestamp: DateTime.now(),
          isRead: false,
        ),
      ];

      final welcomeSent = prefs.getBool(_keyWelcomeSent) ?? false;
      if (!welcomeSent) {
        await prefs.setBool(_keyWelcomeSent, true);
        await showDeviceNotification(
          id: 1001,
          title: '🎉 Welcome to Voidflix!',
          body: 'Enjoy unlimited HD movies, TV shows, and Live IPTV channels on Voidflix.',
        );
      }
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
        body: 'You will receive alerts for new 4K releases and trending shows.',
      );
    }
  }
}
