import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class WatchlistProvider extends ChangeNotifier {
  static const String _legacyKey = 'flowflix_watchlist';
  String _activeProfileId = 'default';
  List<MediaItem> _items = [];
  bool _isLoaded = false;

  List<MediaItem> get items => _items;
  List<MediaItem> get watchlist => _items;
  bool get isLoaded => _isLoaded;
  String get activeProfileId => _activeProfileId;

  String _getKey(String profileId) => 'flowflix_watchlist_$profileId';

  WatchlistProvider({String initialProfileId = 'default'}) {
    _activeProfileId = profileIdOrFallback(initialProfileId);
    loadWatchlist();
  }

  static String profileIdOrFallback(String? id) =>
      (id != null && id.trim().isNotEmpty) ? id.trim() : 'default';

  Future<void> setProfile(String profileId) async {
    final cleanId = profileIdOrFallback(profileId);
    if (_activeProfileId == cleanId && _isLoaded) return;
    _activeProfileId = cleanId;
    await loadWatchlist();
  }

  Future<void> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(_activeProfileId);
    var jsonString = prefs.getString(key);

    // If empty for this profile, check legacy key if on default profile
    if (jsonString == null && _activeProfileId == 'default') {
      jsonString = prefs.getString(_legacyKey);
    }

    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _items = decoded.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        _items = [];
      }
    } else {
      _items = [];
    }
    _isLoaded = true;
    notifyListeners();
  }

  bool isInWatchlist(int id) {
    return _items.any((item) => item.id == id);
  }

  Future<void> toggleWatchlist(MediaItem item) async {
    if (isInWatchlist(item.id)) {
      _items.removeWhere((i) => i.id == item.id);
    } else {
      _items.insert(0, item);
    }
    notifyListeners();
    await _saveToPrefs();
  }

  Future<void> clearWatchlist() async {
    _items.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(_activeProfileId));
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _items.map((e) => e.toJson()).toList();
    await prefs.setString(_getKey(_activeProfileId), jsonEncode(jsonList));
  }
}
