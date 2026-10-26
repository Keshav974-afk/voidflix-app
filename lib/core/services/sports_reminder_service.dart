import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/sports_match.dart';
import '../../providers/notification_provider.dart';

/// Manages kick-off alert reminders for scheduled sports matches.
class SportsReminderService {
  static final SportsReminderService _instance = SportsReminderService._internal();
  factory SportsReminderService() => _instance;
  SportsReminderService._internal() {
    init();
  }

  static const String _prefsKey = 'voidflix_sports_match_reminders';
  final Set<String> _remindedIds = {};
  final Map<String, Timer> _scheduledTimers = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? [];
      _remindedIds.addAll(list);
      _initialized = true;
    } catch (_) {}
  }

  bool isReminded(String matchId) {
    return _remindedIds.contains(matchId);
  }

  Future<bool> toggleReminder({
    required BuildContext context,
    required SportsMatch match,
    NotificationProvider? notifProvider,
  }) async {
    await init();
    final id = match.id;
    final bool enable;

    if (_remindedIds.contains(id)) {
      _remindedIds.remove(id);
      _scheduledTimers[id]?.cancel();
      _scheduledTimers.remove(id);
      enable = false;
    } else {
      _remindedIds.add(id);
      _scheduleLocalAlert(match, notifProvider);
      enable = true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _remindedIds.toList());
    } catch (_) {}

    HapticFeedback.lightImpact();
    return enable;
  }

  void _scheduleLocalAlert(SportsMatch match, NotificationProvider? notifProvider) {
    final now = DateTime.now();
    if (now.isAfter(match.startDateTime)) return;

    final diff = match.startDateTime.difference(now);
    _scheduledTimers[match.id]?.cancel();

    _scheduledTimers[match.id] = Timer(diff, () async {
      _remindedIds.remove(match.id);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_prefsKey, _remindedIds.toList());
      } catch (_) {}

      notifProvider?.showDeviceNotification(
        id: match.id.hashCode.abs() % 100000,
        title: match.title,
        body: 'Live match broadcast has started. Stream is now available.',
      );
    });
  }
}
