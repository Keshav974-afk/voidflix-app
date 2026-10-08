import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_progress.dart';

class HistoryProvider extends ChangeNotifier {
  static const String _legacyKey = 'flowflix_watch_progress';
  String _activeProfileId = 'default';
  List<WatchProgress> _history = [];
  bool _isLoaded = false;

  List<WatchProgress> get history => _history;
  bool get isLoaded => _isLoaded;
  String get activeProfileId => _activeProfileId;

  String _getKey(String profileId) => 'flowflix_watch_progress_$profileId';

  HistoryProvider({String initialProfileId = 'default'}) {
    _activeProfileId = profileIdOrFallback(initialProfileId);
    loadHistory();
  }

  static String profileIdOrFallback(String? id) =>
      (id != null && id.trim().isNotEmpty) ? id.trim() : 'default';

  Future<void> setProfile(String profileId) async {
    final cleanId = profileIdOrFallback(profileId);
    if (_activeProfileId == cleanId && _isLoaded) return;
    _activeProfileId = cleanId;
    await loadHistory();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(_activeProfileId);
    var jsonString = prefs.getString(key);

    if (jsonString == null && _activeProfileId == 'default') {
      jsonString = prefs.getString(_legacyKey);
    }

    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _history = decoded.map((e) => WatchProgress.fromJson(e as Map<String, dynamic>)).toList();
        _history.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
      } catch (e) {
        _history = [];
      }
    } else {
      _history = [];
    }
    _isLoaded = true;
    notifyListeners();
  }

  WatchProgress? getProgress(int id) {
    return _history.where((item) => item.id == id).firstOrNull;
  }

  Future<void> saveProgress(WatchProgress progress) async {
    _history.removeWhere((item) => item.id == progress.id);
    _history.insert(0, progress);
    notifyListeners();
    await _saveToPrefs();
  }

  Future<void> removeProgress(int id) async {
    _history.removeWhere((item) => item.id == id);
    notifyListeners();
    await _saveToPrefs();
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(_activeProfileId));
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _history.map((e) => e.toJson()).toList();
    await prefs.setString(_getKey(_activeProfileId), jsonEncode(jsonList));
  }
}
