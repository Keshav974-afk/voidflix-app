import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WatchPartyMember {
  final String id;
  final String name;
  final bool isHost;
  final int lastSeen;

  const WatchPartyMember({
    required this.id,
    required this.name,
    required this.isHost,
    required this.lastSeen,
  });

  factory WatchPartyMember.fromJson(Map<String, dynamic> json) {
    return WatchPartyMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Friend',
      isHost: json['isHost'] as bool? ?? false,
      lastSeen: json['lastSeen'] as int? ?? 0,
    );
  }
}

class WatchPartyMessage {
  final String id;
  final String sender;
  final String text;
  final int timestamp;

  const WatchPartyMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
  });

  factory WatchPartyMessage.fromJson(Map<String, dynamic> json) {
    return WatchPartyMessage(
      id: json['id'] as String? ?? '',
      sender: json['sender'] as String? ?? 'User',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

class WatchPartyRoom {
  final String roomCode;
  final String hostId;
  final int mediaId;
  final String mediaTitle;
  final String mediaType;
  final int season;
  final int episode;
  final String server;
  final bool isPlaying;
  final double currentTime;
  final int updatedAt;
  final List<WatchPartyMember> members;
  final List<WatchPartyMessage> messages;

  const WatchPartyRoom({
    required this.roomCode,
    required this.hostId,
    required this.mediaId,
    required this.mediaTitle,
    required this.mediaType,
    required this.season,
    required this.episode,
    required this.server,
    required this.isPlaying,
    required this.currentTime,
    required this.updatedAt,
    required this.members,
    required this.messages,
  });

  factory WatchPartyRoom.fromJson(Map<String, dynamic> json) {
    final media = (json['media'] as Map<String, dynamic>?) ?? {};
    final playback = (json['playback'] as Map<String, dynamic>?) ?? {};
    final membersList = (json['members'] as List<dynamic>?) ?? [];
    final messagesList = (json['messages'] as List<dynamic>?) ?? [];

    return WatchPartyRoom(
      roomCode: json['roomCode'] as String? ?? '',
      hostId: json['hostId'] as String? ?? '',
      mediaId: media['mediaId'] as int? ?? 0,
      mediaTitle: media['mediaTitle'] as String? ?? 'Untitled',
      mediaType: media['mediaType'] as String? ?? 'movie',
      season: media['season'] as int? ?? 1,
      episode: media['episode'] as int? ?? 1,
      server: media['server'] as String? ?? 'Vidrock',
      isPlaying: playback['isPlaying'] as bool? ?? false,
      currentTime: (playback['currentTime'] as num?)?.toDouble() ?? 0.0,
      updatedAt: playback['updatedAt'] as int? ?? 0,
      members: membersList.map((m) => WatchPartyMember.fromJson(m as Map<String, dynamic>)).toList(),
      messages: messagesList.map((m) => WatchPartyMessage.fromJson(m as Map<String, dynamic>)).toList(),
    );
  }

  /// Calculates expected current time with drift compensation
  double getDriftCompensatedTime() {
    if (!isPlaying || updatedAt <= 0) return currentTime;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedSec = (now - updatedAt) / 1000.0;
    if (elapsedSec > 0 && elapsedSec < 15.0) {
      return currentTime + elapsedSec;
    }
    return currentTime;
  }
}

class WatchPartyService {
  static const String _apiBase = 'https://voidflix.org/api/public/party';
  final http.Client _client = http.Client();

  Future<WatchPartyRoom?> createRoom({
    required int mediaId,
    required String mediaTitle,
    required String mediaType,
    int season = 1,
    int episode = 1,
    String server = 'Vidrock',
    required String memberId,
    required String memberName,
    bool isPlaying = true,
    double currentTime = 0.0,
  }) async {
    try {
      final uri = Uri.parse('$_apiBase?action=create');
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mediaId': mediaId,
          'mediaTitle': mediaTitle,
          'mediaType': mediaType,
          'season': season,
          'episode': episode,
          'server': server,
          'memberId': memberId,
          'memberName': memberName,
          'isPlaying': isPlaying,
          'currentTime': currentTime,
        }),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['room'] != null) {
          return WatchPartyRoom.fromJson(data['room'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('WatchPartyService: createRoom error: $e');
    }
    return null;
  }

  Future<WatchPartyRoom?> getRoom(String roomCode) async {
    try {
      final cleanCode = roomCode.trim().toUpperCase();
      final uri = Uri.parse('$_apiBase?room=$cleanCode');
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['room'] != null) {
          return WatchPartyRoom.fromJson(data['room'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('WatchPartyService: getRoom error: $e');
    }
    return null;
  }

  Future<WatchPartyRoom?> joinRoom({
    required String roomCode,
    required String memberId,
    required String memberName,
  }) async {
    try {
      final cleanCode = roomCode.trim().toUpperCase();
      final uri = Uri.parse('$_apiBase?action=join');
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomCode': cleanCode,
          'memberId': memberId,
          'memberName': memberName,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['room'] != null) {
          return WatchPartyRoom.fromJson(data['room'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('WatchPartyService: joinRoom error: $e');
    }
    return null;
  }

  Future<WatchPartyRoom?> syncPlayback({
    required String roomCode,
    required String memberId,
    required bool isPlaying,
    required double currentTime,
    String? chatText,
    String? chatSender,
  }) async {
    try {
      final cleanCode = roomCode.trim().toUpperCase();
      final uri = Uri.parse('$_apiBase?action=sync');
      final payload = <String, dynamic>{
        'roomCode': cleanCode,
        'memberId': memberId,
        'isPlaying': isPlaying,
        'currentTime': currentTime,
      };
      if (chatText != null && chatSender != null) {
        payload['chatText'] = chatText;
        payload['chatSender'] = chatSender;
      }

      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['room'] != null) {
          return WatchPartyRoom.fromJson(data['room'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> leaveRoom(String roomCode, String memberId) async {
    try {
      final cleanCode = roomCode.trim().toUpperCase();
      final uri = Uri.parse('$_apiBase?action=leave');
      await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomCode': cleanCode,
          'memberId': memberId,
        }),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
