import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// VoidCast: Realtime TV & Mobile Connect, Streaming Beam & Remote Control
class VoidCastService extends ChangeNotifier {
  static final VoidCastService _instance = VoidCastService._internal();
  factory VoidCastService() => _instance;
  VoidCastService._internal();

  static const String serverHost = '103.30.211.131';
  static const int serverPort = 8000;
  static const String prefLastTvCodeKey = 'voidflix_last_paired_tv_code';
  static const String prefLastTvNameKey = 'voidflix_last_paired_tv_name';

  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _pollTimer;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isHostingTv = false;
  bool get isHostingTv => _isHostingTv;

  String? _roomCode;
  String? get roomCode => _roomCode;

  String _connectedTvName = 'Android TV';
  String get connectedTvName => _connectedTvName;

  String _myDeviceName = 'Mobile Device';
  String get myDeviceName => _myDeviceName;

  // TV Playback State
  Map<String, dynamic> _tvState = {
    'status': 'idle',
    'title': '',
    'poster': '',
    'tmdbId': '',
    'mediaType': 'movie',
    'currentTime': 0.0,
    'duration': 0.0,
    'isPlaying': false,
    'season': 1,
    'episode': 1,
    'volume': 1.0,
  };
  Map<String, dynamic> get tvState => _tvState;

  // Command stream consumed by TV UI & Player
  final StreamController<Map<String, dynamic>> _commandController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCommand => _commandController.stream;

  // Global navigator key listener hook (for playing from anywhere)
  void Function(Map<String, dynamic> playData)? onRemotePlayRequested;
  void Function(String key)? onRemoteDpadKey;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCode = prefs.getString(prefLastTvCodeKey);
      final lastName = prefs.getString(prefLastTvNameKey);
      if (lastCode != null && lastCode.isNotEmpty) {
        _roomCode = lastCode;
        if (lastName != null) _connectedTvName = lastName;
      }
    } catch (_) {}
  }

  // ==========================================
  // --- TV HOSTING (Android TV / Big Screen) ---
  // ==========================================

  Future<String> startHosting({String? deviceName}) async {
    _isHostingTv = true;
    _myDeviceName = deviceName ?? 'Voidflix Android TV';

    // Generate clean 6-digit code or reuse existing
    if (_roomCode == null || _roomCode!.length != 6) {
      final rng = Random();
      _roomCode = (100000 + rng.nextInt(900000)).toString();
    }

    await _connectWebSocket(role: 'tv', code: _roomCode!, device: _myDeviceName);
    notifyListeners();
    return _roomCode!;
  }

  /// Broadcasts current video player status to all paired mobile remotes
  void broadcastTvPlaybackState({
    required bool isPlaying,
    required double currentTime,
    required double duration,
    required String title,
    String? tmdbId,
    String? mediaType,
    String? poster,
    int season = 1,
    int episode = 1,
  }) {
    if (!_isHostingTv) return;

    _tvState = {
      'status': isPlaying ? 'playing' : 'paused',
      'title': title,
      'poster': poster ?? '',
      'tmdbId': tmdbId ?? '',
      'mediaType': mediaType ?? 'movie',
      'currentTime': currentTime,
      'duration': duration,
      'isPlaying': isPlaying,
      'season': season,
      'episode': episode,
      'volume': _tvState['volume'] ?? 1.0,
    };

    final payload = {
      'type': 'state_update',
      'data': _tvState,
    };

    _send(payload);
  }

  // ==========================================
  // --- MOBILE REMOTE CONTROL ---
  // ==========================================

  Future<bool> connectToTv(String rawCode, {String? mobileName}) async {
    final cleanCode = rawCode.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (cleanCode.length != 6) return false;

    _roomCode = cleanCode;
    _myDeviceName = mobileName ?? 'Voidflix Phone';
    _isHostingTv = false;

    final success = await _connectWebSocket(
      role: 'remote',
      code: cleanCode,
      device: _myDeviceName,
    );

    if (success) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefLastTvCodeKey, cleanCode);
        await prefs.setString(prefLastTvNameKey, _connectedTvName);
      } catch (_) {}
    }

    return success;
  }

  void disconnect() {
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
    notifyListeners();
  }

  /// Beam Movie / Episode to TV
  void playOnTv({
    required String tmdbId,
    required String type,
    required String title,
    String? poster,
    int season = 1,
    int episode = 1,
    double position = 0,
  }) {
    if (!_isConnected || _roomCode == null) return;

    final data = {
      'action': 'play',
      'tmdbId': tmdbId,
      'type': type,
      'title': title,
      'poster': poster ?? '',
      'season': season,
      'episode': episode,
      'position': position,
    };

    _sendCommand('play', data);

    // Optimistically update remote state
    _tvState['title'] = title;
    _tvState['poster'] = poster ?? '';
    _tvState['tmdbId'] = tmdbId;
    _tvState['mediaType'] = type;
    _tvState['isPlaying'] = true;
    _tvState['currentTime'] = position;
    notifyListeners();
  }

  void pauseTv() => _sendCommand('pause', {});
  void resumeTv() => _sendCommand('resume', {});
  void togglePlayPauseTv() {
    if (_tvState['isPlaying'] == true) {
      pauseTv();
    } else {
      resumeTv();
    }
  }

  void seekTv(double seconds) => _sendCommand('seek', {'position': seconds});
  void skipTv(int offsetSeconds) => _sendCommand('skip', {'offset': offsetSeconds});
  void setVolume(double level) {
    _tvState['volume'] = level.clamp(0.0, 1.0);
    _sendCommand('volume', {'level': level.clamp(0.0, 1.0)});
    notifyListeners();
  }

  /// D-Pad remote navigation: 'up', 'down', 'left', 'right', 'select', 'back', 'home'
  void sendDpadKey(String key) => _sendCommand('key', {'key': key});

  /// Remote search keyboard text input to TV
  void sendSearchText(String query) => _sendCommand('search', {'query': query});

  void exitPlayerOnTv() => _sendCommand('exit', {});

  // ==========================================
  // --- WEBSOCKET & NETWORKING ---
  // ==========================================

  Future<bool> _connectWebSocket({
    required String role,
    required String code,
    required String device,
  }) async {
    _pingTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}

    final encodedDevice = Uri.encodeComponent(device);
    final wsUri = Uri.parse(
      'ws://$serverHost:$serverPort/ws/tv-sync/$code?role=$role&device=$encodedDevice',
    );

    try {
      _socket = await WebSocket.connect(wsUri.toString()).timeout(
        const Duration(seconds: 4),
      );

      _isConnected = true;
      notifyListeners();

      _socket!.listen(
        (data) => _handleIncomingMessage(data, role),
        onError: (err) {
          debugPrint('[VoidCast] WS error: $err');
          _onSocketClosed(role, code, device);
        },
        onDone: () {
          debugPrint('[VoidCast] WS closed.');
          _onSocketClosed(role, code, device);
        },
        cancelOnError: false,
      );

      // Keepalive Ping every 25s
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'type': 'ping'});
      });

      return true;
    } catch (e) {
      debugPrint('[VoidCast] WS connection failed: $e, falling back to HTTP sync');
      return _startHttpFallback(role, code);
    }
  }

  void _handleIncomingMessage(dynamic raw, String role) {
    try {
      final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = map['type'] as String? ?? '';

      if (type == 'room_synced' || type == 'tv_connected') {
        _isConnected = true;
        if (map['device_name'] != null && map['device_name'].toString().isNotEmpty) {
          _connectedTvName = map['device_name'].toString();
        }
        if (map['state'] is Map) {
          _tvState = Map<String, dynamic>.from(map['state'] as Map);
        }
        notifyListeners();
      } else if (type == 'tv_disconnected') {
        if (role == 'remote') {
          _isConnected = false;
          notifyListeners();
        }
      } else if (type == 'state_update') {
        if (map['state'] is Map) {
          _tvState = Map<String, dynamic>.from(map['state'] as Map);
          notifyListeners();
        }
      } else if (type == 'command') {
        // TV received remote control command!
        final action = map['action'] as String? ?? '';
        final payload = map['payload'] as Map<String, dynamic>? ?? {};

        _commandController.add({
          'action': action,
          'payload': payload,
        });

        if (action == 'play' && onRemotePlayRequested != null) {
          onRemotePlayRequested!(payload);
        } else if (action == 'key' && onRemoteDpadKey != null) {
          final k = payload['key'] as String? ?? '';
          if (k.isNotEmpty) onRemoteDpadKey!(k);
        }
      }
    } catch (e) {
      debugPrint('[VoidCast] JSON parse error: $e');
    }
  }

  void _onSocketClosed(String role, String code, String device) {
    _isConnected = false;
    notifyListeners();
    // Auto-reconnect after 3 seconds if roomCode still active
    Future.delayed(const Duration(seconds: 3), () {
      if (_roomCode == code) {
        _connectWebSocket(role: role, code: code, device: device);
      }
    });
  }

  void _sendCommand(String action, Map<String, dynamic> data) {
    final payload = {
      'type': action,
      'data': data,
    };
    _send(payload);

    // Also send HTTP fallback in background for guaranteed delivery
    if (_roomCode != null) {
      http.post(
        Uri.parse('http://$serverHost:$serverPort/api/tv/command/$_roomCode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'payload': data}),
      ).catchError((_) => http.Response('', 500));
    }
  }

  void _send(Map<String, dynamic> data) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      try {
        _socket!.add(jsonEncode(data));
      } catch (_) {}
    }
  }

  Future<bool> _startHttpFallback(String role, String code) async {
    try {
      final res = await http.get(
        Uri.parse('http://$serverHost:$serverPort/api/tv/state/$code'),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _isConnected = data['paired'] == true || role == 'tv';
        if (data['device_name'] != null) _connectedTvName = data['device_name'];
        if (data['state'] is Map) _tvState = Map<String, dynamic>.from(data['state']);
        notifyListeners();

        // Polling loop
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          try {
            final pollRes = await http.get(
              Uri.parse('http://$serverHost:$serverPort/api/tv/state/$code'),
            );
            if (pollRes.statusCode == 200) {
              final pollData = jsonDecode(pollRes.body) as Map<String, dynamic>;
              if (pollData['state'] is Map) {
                _tvState = Map<String, dynamic>.from(pollData['state']);
                notifyListeners();
              }
            }
          } catch (_) {}
        });

        return true;
      }
    } catch (_) {}
    return false;
  }
}
