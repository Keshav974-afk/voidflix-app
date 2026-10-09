import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/avatar_service.dart';

class UserProfile {
  final String id;
  final String name;
  final int colorIndex;
  final bool isKids;
  final String? pin;
  final String avatar;
  final List<String> preferredLanguages;
  final List<int> preferredGenres;
  final List<String> favoriteActors;
  final List<String> favoriteTitles;
  final bool hasCompletedOnboarding;

  const UserProfile({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    this.isKids = false,
    this.pin,
    this.avatar = '🍿',
    this.preferredLanguages = const [],
    this.preferredGenres = const [],
    this.favoriteActors = const [],
    this.favoriteTitles = const [],
    this.hasCompletedOnboarding = false,
  });

  bool get isLocked => pin != null && pin!.trim().isNotEmpty;

  UserProfile copyWith({
    String? id,
    String? name,
    int? colorIndex,
    bool? isKids,
    String? pin,
    String? avatar,
    List<String>? preferredLanguages,
    List<int>? preferredGenres,
    List<String>? favoriteActors,
    List<String>? favoriteTitles,
    bool? hasCompletedOnboarding,
    bool clearPin = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      isKids: isKids ?? this.isKids,
      pin: clearPin ? null : (pin ?? this.pin),
      avatar: avatar ?? this.avatar,
      preferredLanguages: preferredLanguages ?? this.preferredLanguages,
      preferredGenres: preferredGenres ?? this.preferredGenres,
      favoriteActors: favoriteActors ?? this.favoriteActors,
      favoriteTitles: favoriteTitles ?? this.favoriteTitles,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'colorIndex': colorIndex,
      'isKids': isKids,
      'pin': pin,
      'avatar': avatar,
      'preferredLanguages': preferredLanguages,
      'preferredGenres': preferredGenres,
      'favoriteActors': favoriteActors,
      'favoriteTitles': favoriteTitles,
      'hasCompletedOnboarding': hasCompletedOnboarding,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? 'Profile',
      colorIndex: json['colorIndex'] as int? ?? 0,
      isKids: json['isKids'] as bool? ?? false,
      pin: json['pin'] as String?,
      avatar: json['avatar'] as String? ?? '🍿',
      preferredLanguages: (json['preferredLanguages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      preferredGenres: (json['preferredGenres'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      favoriteActors: (json['favoriteActors'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      favoriteTitles: (json['favoriteTitles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }
}

class ProfileProvider extends ChangeNotifier {
  static const String _keyProfile = 'voidflix_active_profile';
  static const String _keyProfilesList = 'voidflix_profiles_list';
  static const String _keyServer = 'voidflix_active_server_index';
  static const String _keyGlobalOnboarding = 'voidflix_global_onboarding_completed';

  static const List<List<Color>> avatarGradients = [
    [Color(0xFFE50914), Color(0xFF831010)], // 0: Red / Rose
    [Color(0xFF3B82F6), Color(0xFF1E1B4B)], // 1: Blue / Indigo
    [Color(0xFF10B981), Color(0xFF134E4A)], // 2: Emerald / Teal
    [Color(0xFFF59E0B), Color(0xFF7C2D12)], // 3: Amber / Orange
    [Color(0xFFD946EF), Color(0xFF581C87)], // 4: Fuchsia / Purple
    [Color(0xFF06B6D4), Color(0xFF0C4A6E)], // 5: Cyan / Sky
  ];

  static const List<String> avatarIcons = [
    '🍿', '🎬', '⚡', '🧸', '🚀', '🔥', '👑', '🎭', '👾', '🌟'
  ];

  List<UserProfile> _profiles = [];
  UserProfile? _activeProfile;
  int _selectedServerIndex = 0;
  bool _profileChosenInSession = false;
  bool _globalOnboardingCompleted = false;
  bool _isLoaded = false;

  List<UserProfile> get profiles => List.unmodifiable(_profiles);
  List<UserProfile> get availableProfiles => profiles;
  bool get hasProfiles => _profiles.isNotEmpty;
  bool get isLoaded => _isLoaded;
  bool get globalOnboardingCompleted => _globalOnboardingCompleted;

  UserProfile get activeProfile =>
      _activeProfile ??
      (_profiles.isNotEmpty
          ? _profiles.first
          : const UserProfile(id: 'guest', name: 'User', colorIndex: 0));

  UserProfile? get activeProfileOrNull => _activeProfile;
  int get selectedServerIndex => _selectedServerIndex;
  bool get profileChosenInSession => _profileChosenInSession;

  ProfileProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _globalOnboardingCompleted = prefs.getBool(_keyGlobalOnboarding) ?? false;

    final savedListStr = prefs.getString(_keyProfilesList);
    if (savedListStr != null && savedListStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedListStr) as List<dynamic>;
        final loaded = decoded.map((e) => UserProfile.fromJson(e as Map<String, dynamic>)).toList();
        if (loaded.isNotEmpty) {
          _profiles = loaded;
        }
      } catch (e) {
        debugPrint('Error parsing saved profiles: $e');
      }
    }

    if (_profiles.isNotEmpty) {
      final profileId = prefs.getString(_keyProfile);
      if (profileId != null) {
        final found = _profiles.where((p) => p.id == profileId).firstOrNull;
        _activeProfile = found ?? _profiles.first;
      } else {
        _activeProfile = _profiles.first;
      }
    } else {
      _activeProfile = null;
    }

    _selectedServerIndex = prefs.getInt(_keyServer) ?? 0;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveProfilesList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_keyProfilesList, jsonStr);
  }

  Future<void> setActiveProfile(UserProfile profile) async {
    _activeProfile = profile;
    _profileChosenInSession = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, profile.id);
  }

  void markProfileChosen() {
    _profileChosenInSession = true;
    notifyListeners();
  }

  Future<UserProfile> addProfile({
    required String name,
    required int colorIndex,
    required bool isKids,
    String? pin,
    String? avatar,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final defaultAvatar = AvatarService.defaultFeatured[colorIndex % AvatarService.defaultFeatured.length].url;
    final newProfile = UserProfile(
      id: newId,
      name: name.trim().isEmpty ? 'Profile ${_profiles.length + 1}' : name.trim(),
      colorIndex: colorIndex % avatarGradients.length,
      isKids: isKids,
      pin: (pin != null && pin.trim().isNotEmpty) ? pin.trim() : null,
      avatar: (avatar != null && avatar.trim().isNotEmpty) ? avatar.trim() : defaultAvatar,
    );

    _profiles.add(newProfile);
    if (_activeProfile == null || _profiles.length == 1) {
      _activeProfile = newProfile;
    }

    await _saveProfilesList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, activeProfile.id);

    notifyListeners();
    return newProfile;
  }

  Future<void> updateProfile(
    String id, {
    String? name,
    int? colorIndex,
    bool? isKids,
    String? pin,
    String? avatar,
    bool clearPin = false,
  }) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final old = _profiles[idx];
      final updated = old.copyWith(
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : old.name,
        colorIndex: colorIndex != null ? (colorIndex % avatarGradients.length) : null,
        isKids: isKids,
        pin: pin,
        avatar: avatar,
        clearPin: clearPin,
      );
      _profiles[idx] = updated;
      if (_activeProfile?.id == id) {
        _activeProfile = updated;
      }
      await _saveProfilesList();
      notifyListeners();
    }
  }

  Future<void> lockProfile(String id, String pin) async {
    await updateProfile(id, pin: pin.trim());
  }

  Future<void> unlockProfile(String id) async {
    await updateProfile(id, clearPin: true);
  }

  bool verifyPin(String id, String enteredPin) {
    final profile = _profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) return false;
    if (profile.pin == null || profile.pin!.isEmpty) return true;
    return profile.pin == enteredPin.trim();
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeProfile?.id == id) {
      _activeProfile = _profiles.isNotEmpty ? _profiles.first : null;
      final prefs = await SharedPreferences.getInstance();
      if (_activeProfile != null) {
        await prefs.setString(_keyProfile, _activeProfile!.id);
      } else {
        await prefs.remove(_keyProfile);
      }
    }
    await _saveProfilesList();

    // Clean up profile specific data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('flowflix_watchlist_$id');
    await prefs.remove('flowflix_watch_progress_$id');

    notifyListeners();
  }

  Future<void> setSelectedServer(int index) async {
    _selectedServerIndex = index;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyServer, index);
  }

  Future<UserProfile> completeInitialOnboarding({
    required String name,
    required String avatar,
    required int colorIndex,
    bool isKids = false,
    required List<String> preferredLanguages,
    required List<int> preferredGenres,
    required List<String> favoriteActors,
    required List<String> favoriteTitles,
  }) async {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final profile = UserProfile(
      id: newId,
      name: name.trim().isEmpty ? 'Cinema Explorer' : name.trim(),
      avatar: avatar,
      colorIndex: colorIndex % avatarGradients.length,
      isKids: isKids,
      preferredLanguages: preferredLanguages,
      preferredGenres: preferredGenres,
      favoriteActors: favoriteActors,
      favoriteTitles: favoriteTitles,
      hasCompletedOnboarding: true,
    );

    _profiles = [profile];
    _activeProfile = profile;
    _profileChosenInSession = true;
    _globalOnboardingCompleted = true;

    await _saveProfilesList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, profile.id);
    await prefs.setBool(_keyGlobalOnboarding, true);

    notifyListeners();
    return profile;
  }

  Future<void> updateProfilePreferences(
    String id, {
    List<String>? preferredLanguages,
    List<int>? preferredGenres,
    List<String>? favoriteActors,
    List<String>? favoriteTitles,
  }) async {
    final idx = _profiles.indexWhere((p) => p.id == id);
    if (idx != -1) {
      final old = _profiles[idx];
      final updated = old.copyWith(
        preferredLanguages: preferredLanguages,
        preferredGenres: preferredGenres,
        favoriteActors: favoriteActors,
        favoriteTitles: favoriteTitles,
        hasCompletedOnboarding: true,
      );
      _profiles[idx] = updated;
      if (_activeProfile?.id == id) {
        _activeProfile = updated;
      }
      await _saveProfilesList();
      notifyListeners();
    }
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _profiles.clear();
    _activeProfile = null;
    _selectedServerIndex = 0;
    _profileChosenInSession = false;
    _isLoaded = true;
    notifyListeners();
  }
}
