import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// TV device discovered over local Wi-Fi network signals (zero VPS required)
class DiscoveredTv {
  final String name;
  final String ip;
  final int port;
  final String code;
  final DateTime lastSeen;

  const DiscoveredTv({
    required this.name,
    required this.ip,
    required this.port,
    required this.code,
    required this.lastSeen,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredTv && runtimeType == other.runtimeType && ip == other.ip && port == other.port;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode;
}

/// VoidCast: Realtime TV & Mobile Connect, Streaming Beam & Remote Control
/// Supports both Direct Local Network Signals (LAN Wi-Fi) and Cloud Relay Fallback
class VoidCastService extends ChangeNotifier {
  static final VoidCastService _instance = VoidCastService._internal();
  factory VoidCastService() => _instance;
  VoidCastService._internal();

  static const String serverHost = '103.30.211.131';
  static const int serverPort = 8000;
  static const int localBroadcastPort = 8088;
  static const String prefLastTvCodeKey = 'voidflix_last_paired_tv_code';
  static const String prefLastTvNameKey = 'voidflix_last_paired_tv_name';

  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  Timer? _localBeaconTimer;
  Timer? _discoveryPruneTimer;

  RawDatagramSocket? _udpSocket;
  HttpServer? _localHttpServer;
  final List<WebSocket> _localTvClients = [];

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isLocalConnection = false;
  bool get isLocalConnection => _isLocalConnection;

  bool _isExplicitlyDisconnected = false;

  bool _isHostingTv = false;
  bool get isHostingTv => _isHostingTv;

  String? _roomCode;
  String? get roomCode => _roomCode;

  String? _localTvIp;
  int _localTvPort = 8088;

  String _connectedTvName = 'Android TV';
  String get connectedTvName => _connectedTvName;

  String _myDeviceName = 'Mobile Device';
  String get myDeviceName => _myDeviceName;

  final List<DiscoveredTv> _discoveredTvs = [];
  List<DiscoveredTv> get discoveredTvs => List.unmodifiable(_discoveredTvs);

  bool _isScanningLocal = false;
  bool get isScanningLocal => _isScanningLocal;

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
  // --- LOCAL NETWORK DISCOVERY (Wi-Fi) ---
  // ==========================================

  /// Start scanning the local Wi-Fi network for Voidflix TV beacons
  Future<void> startLocalDiscovery() async {
    if (_isScanningLocal) return;
    _isScanningLocal = true;
    _discoveredTvs.clear();
    notifyListeners();

    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // random ephemeral port for scanning
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            _handleIncomingUdpPacket(datagram);
          }
        }
      });

      // Broadcast search ping immediately and every 3 seconds
      _sendDiscoveryPing();
      _localBeaconTimer?.cancel();
      _localBeaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isScanningLocal) {
          _sendDiscoveryPing();
        }
      });

      // Prune devices not seen in last 10 seconds
      _discoveryPruneTimer?.cancel();
      _discoveryPruneTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        final now = DateTime.now();
        final beforeCount = _discoveredTvs.length;
        _discoveredTvs.removeWhere((tv) => now.difference(tv.lastSeen).inSeconds > 10);
        if (_discoveredTvs.length != beforeCount) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[VoidCast] Local discovery start error: $e');
    }
  }

  void stopLocalDiscovery() {
    _isScanningLocal = false;
    _localBeaconTimer?.cancel();
    _discoveryPruneTimer?.cancel();
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
    notifyListeners();
  }

  void _sendDiscoveryPing() {
    try {
      final pingMsg = utf8.encode(jsonEncode({'type': 'voidcast_discover'}));
      _udpSocket?.send(pingMsg, InternetAddress('255.255.255.255'), localBroadcastPort);
    } catch (_) {}
  }

  void _handleIncomingUdpPacket(Datagram datagram) {
    try {
      final msg = utf8.decode(datagram.data);
      final json = jsonDecode(msg) as Map<String, dynamic>;
      if (json['type'] == 'voidcast_tv_beacon') {
        final name = json['name']?.toString() ?? 'Voidflix Android TV';
        final port = (json['port'] as num?)?.toInt() ?? 8088;
        final code = json['code']?.toString() ?? '';
        final ip = datagram.address.address;

        final newTv = DiscoveredTv(
          name: name,
          ip: ip,
          port: port,
          code: code,
          lastSeen: DateTime.now(),
        );

        final idx = _discoveredTvs.indexWhere((t) => t.ip == ip && t.port == port);
        if (idx >= 0) {
          _discoveredTvs[idx] = newTv;
        } else {
          _discoveredTvs.add(newTv);
          debugPrint('[VoidCast] Discovered Local TV: $name at $ip:$port (code: $code)');
        }
        notifyListeners();
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

    // 1. Start local LAN server on TV port 8088
    await _startLocalTvServer(localBroadcastPort);

    // 2. Start UDP beacon broadcasting local network signals
    _startLocalBeaconBroadcast();

    // 3. Connect to cloud relay for optional cross-network pairing
    await _connectWebSocket(role: 'tv', code: _roomCode!, device: _myDeviceName);
    notifyListeners();
    return _roomCode!;
  }

  Future<void> _startLocalTvServer(int port) async {
    try {
      await _localHttpServer?.close(force: true);
      _localHttpServer = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      debugPrint('[VoidCast] TV Local HTTP & WS Server listening on port $port');

      _localHttpServer!.listen((HttpRequest request) async {
        // Add CORS headers for any local web clients
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }

        final path = request.uri.path;

        // WebSocket endpoint for direct LAN connection
        if (path == '/ws') {
          try {
            final ws = await WebSocketTransformer.upgrade(request);
            _localTvClients.add(ws);
            debugPrint('[VoidCast] Local phone connected directly over Wi-Fi!');

            // Send initial state
            ws.add(jsonEncode({
              'type': 'room_synced',
              'paired': true,
              'device_name': _myDeviceName,
              'state': _tvState,
            }));

            ws.listen(
              (data) => _handleIncomingMessage(data, 'tv'),
              onDone: () => _localTvClients.remove(ws),
              onError: (_) => _localTvClients.remove(ws),
            );
          } catch (e) {
            debugPrint('[VoidCast] WS upgrade error: $e');
          }
          return;
        }

        // HTTP Status check
        if (path == '/api/status' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'paired': true,
            'device_name': _myDeviceName,
            'code': _roomCode,
            'state': _tvState,
          }));
          await request.response.close();
          return;
        }

        // Direct HTTP Command Execution
        if (path == '/api/command' && request.method == 'POST') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final action = json['action']?.toString() ?? '';
            final payload = json['payload'] as Map<String, dynamic>? ?? {};

            _commandController.add({
              'action': action,
              'payload': payload,
            });

            if (action == 'play' && onRemotePlayRequested != null) {
              onRemotePlayRequested!(payload);
            } else if (action == 'key' && onRemoteDpadKey != null) {
              final k = payload['key']?.toString() ?? '';
              if (k.isNotEmpty) onRemoteDpadKey!(k);
            }

            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'success': true}));
          } catch (_) {
            request.response.statusCode = HttpStatus.badRequest;
          }
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
    } catch (e) {
      debugPrint('[VoidCast] Failed to bind local TV server: $e');
    }
  }

  void _startLocalBeaconBroadcast() async {
    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        localBroadcastPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      // Listen for incoming discovery requests from mobile devices
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            try {
              final str = utf8.decode(datagram.data);
              final json = jsonDecode(str) as Map<String, dynamic>;
              if (json['type'] == 'voidcast_discover') {
                _sendLocalTvBeacon(targetAddress: datagram.address);
              }
            } catch (_) {}
          }
        }
      });

      // Broadcast beacon periodically every 2.5s
      _localBeaconTimer?.cancel();
      _localBeaconTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        _sendLocalTvBeacon();
      });
    } catch (e) {
      debugPrint('[VoidCast] Failed to start UDP beacon broadcast: $e');
    }
  }

  void _sendLocalTvBeacon({InternetAddress? targetAddress}) {
    if (!_isHostingTv) return;
    try {
      final beaconData = utf8.encode(jsonEncode({
        'type': 'voidcast_tv_beacon',
        'name': _myDeviceName,
        'port': localBroadcastPort,
        'code': _roomCode ?? '',
      }));

      final addr = targetAddress ?? InternetAddress('255.255.255.255');
      _udpSocket?.send(beaconData, addr, localBroadcastPort);
    } catch (_) {}
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

    // Send to local LAN clients
    for (final client in _localTvClients) {
      try {
        client.add(jsonEncode(payload));
      } catch (_) {}
    }

    // Send to cloud relay
    _send(payload);
  }

  // ==========================================
  // --- DIRECT LOCAL WI-FI CONNECT ---
  // ==========================================

  /// Connects directly to TV over local Wi-Fi signals (zero VPS required)
  Future<bool> connectToLocalTv(DiscoveredTv tv) async {
    _isExplicitlyDisconnected = false;
    _roomCode = tv.code;
    _connectedTvName = tv.name;
    _localTvIp = tv.ip;
    _localTvPort = tv.port;
    _isLocalConnection = true;
    _isHostingTv = false;

    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}

    try {
      final wsUri = Uri.parse('ws://${tv.ip}:${tv.port}/ws');
      debugPrint('[VoidCast] Connecting directly to local TV at $wsUri ...');

      _socket = await WebSocket.connect(wsUri.toString()).timeout(
        const Duration(seconds: 3),
      );

      _isConnected = true;
      notifyListeners();

      _socket!.listen(
        (data) => _handleIncomingMessage(data, 'remote'),
        onError: (err) {
          debugPrint('[VoidCast] Local WS error: $err');
          _onSocketClosed('remote', tv.code, _myDeviceName);
        },
        onDone: () {
          debugPrint('[VoidCast] Local WS closed.');
          _onSocketClosed('remote', tv.code, _myDeviceName);
        },
        cancelOnError: false,
      );

      // Keepalive Ping every 15s
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _send({'type': 'ping'});
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        if (tv.code.isNotEmpty) await prefs.setString(prefLastTvCodeKey, tv.code);
        await prefs.setString(prefLastTvNameKey, tv.name);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[VoidCast] Direct local Wi-Fi connect failed: $e, falling back to code pairing');
      if (tv.code.isNotEmpty) {
        return connectToTv(tv.code);
      }
      return false;
    }
  }

  // ==========================================
  // --- CODE PAIRING (Local + Cloud Fallback) ---
  // ==========================================

  Future<bool> connectToTv(String rawCode, {String? mobileName}) async {
    final cleanCode = rawCode.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (cleanCode.length != 6) return false;

    _isExplicitlyDisconnected = false;
    _roomCode = cleanCode;
    _myDeviceName = mobileName ?? 'Voidflix Phone';
    _isHostingTv = false;
    _isLocalConnection = false;

    // Check if we already have this TV discovered locally on Wi-Fi
    final matchingLocal = _discoveredTvs.where((t) => t.code == cleanCode).toList();
    if (matchingLocal.isNotEmpty) {
      debugPrint('[VoidCast] Code matches local TV on Wi-Fi! Connecting directly over LAN.');
      return connectToLocalTv(matchingLocal.first);
    }

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
    _isExplicitlyDisconnected = true;
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
    _roomCode = null;
    _isLocalConnection = false;
    _localTvIp = null;
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
    if (!_isConnected) return;

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
    _reconnectTimer?.cancel();
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

      if (type == 'room_synced') {
        // Strictly check if an actual TV is connected
        final isPaired = map['paired'] == true || role == 'tv';
        _isConnected = isPaired;
        if (map['device_name'] != null && map['device_name'].toString().isNotEmpty) {
          _connectedTvName = map['device_name'].toString();
        }
        if (map['state'] is Map) {
          _tvState = Map<String, dynamic>.from(map['state'] as Map);
        }
        notifyListeners();
      } else if (type == 'tv_connected') {
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

    // NEVER reconnect if explicitly disconnected or code cleared
    if (_isExplicitlyDisconnected || _roomCode == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (!_isExplicitlyDisconnected && _roomCode == code) {
        if (_isLocalConnection && _localTvIp != null) {
          final matching = _discoveredTvs.where((t) => t.ip == _localTvIp).toList();
          if (matching.isNotEmpty) {
            connectToLocalTv(matching.first);
            return;
          }
        }
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

    // If connected directly over local Wi-Fi, send direct HTTP command to local TV
    if (_isLocalConnection && _localTvIp != null) {
      http.post(
        Uri.parse('http://$_localTvIp:$_localTvPort/api/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'payload': data}),
      ).catchError((_) => http.Response('', 500));
    } else if (_roomCode != null) {
      // Cloud fallback command
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
        final isPaired = data['paired'] == true || role == 'tv';
        if (!isPaired && role == 'remote') {
          _isConnected = false;
          notifyListeners();
          return false;
        }

        _isConnected = true;
        if (data['device_name'] != null) _connectedTvName = data['device_name'];
        if (data['state'] is Map) _tvState = Map<String, dynamic>.from(data['state']);
        notifyListeners();

        // Polling loop
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          if (_isExplicitlyDisconnected || _roomCode == null) {
            _pollTimer?.cancel();
            return;
          }
          try {
            final pollRes = await http.get(
              Uri.parse('http://$serverHost:$serverPort/api/tv/state/$code'),
            );
            if (pollRes.statusCode == 200) {
              final pollData = jsonDecode(pollRes.body) as Map<String, dynamic>;
              if (pollData['paired'] == true && pollData['state'] is Map) {
                _tvState = Map<String, dynamic>.from(pollData['state']);
                notifyListeners();
              } else if (pollData['paired'] != true && role == 'remote') {
                _isConnected = false;
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
