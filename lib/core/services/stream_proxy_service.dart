import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_logger.dart';

class _ProxySession {
  final String id;
  final String targetUrl;
  final Map<String, String> headers;
  final DateTime createdAt;

  _ProxySession({
    required this.id,
    required this.targetUrl,
    required this.headers,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(hours: 6);
}

class StreamProxyService {
  static final StreamProxyService instance = StreamProxyService._internal();
  factory StreamProxyService() => instance;
  StreamProxyService._internal();

  HttpServer? _server;
  int _port = 0;
  int get port => _port;
  bool get isRunning => _server != null;

  final Map<String, _ProxySession> _sessions = {};
  Timer? _cleanupTimer;
  late final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((cert, host, port) => true)
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 60)
    ..maxConnectionsPerHost = 32;

  int _sessionCounter = 0;

  Future<void> start() async {
    if (_server != null) return;

    try {
      // Bind to any IPv4 (0.0.0.0) on an ephemeral port so both localhost
      // and LAN Smart TVs / DLNA renderers can reach the proxy.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
      AppLogger.instance.log('StreamProxy', 'Started HLS loopback proxy on port $_port');

      _cleanupTimer = Timer.periodic(const Duration(minutes: 15), (_) => _cleanupExpiredSessions());

      _server!.listen(
        _handleRequest,
        onError: (e) {
          AppLogger.instance.error('StreamProxy', 'Server error', e);
        },
      );
    } catch (e) {
      AppLogger.instance.error('StreamProxy', 'Failed to start server', e);
    }
  }

  void _cleanupExpiredSessions() {
    _sessions.removeWhere((key, session) => session.isExpired);
  }

  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
    debugPrint('[StreamProxyService] Stopped');
  }

  String _registerSession(String targetUrl, Map<String, String> headers) {
    _sessionCounter++;
    final sid = 's_${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter';
    _sessions[sid] = _ProxySession(
      id: sid,
      targetUrl: targetUrl,
      headers: Map.from(headers),
    );
    return sid;
  }

  /// Returns a localhost URL suitable for native Windows players (video_player_win)
  Future<String> getProxyUrl(String targetUrl, [Map<String, String>? headers]) async {
    await start();
    final sid = _registerSession(targetUrl, headers ?? {});
    final isM3u8 = targetUrl.toLowerCase().contains('.m3u8') || !targetUrl.toLowerCase().contains('.mp4');
    final endpoint = isM3u8 ? 'stream.m3u8' : 'direct';
    return 'http://127.0.0.1:$_port/$endpoint?sid=$sid';
  }

  /// Returns a LAN URL reachable by Smart TVs and DLNA renderers on the local Wi-Fi
  Future<String> getLanProxyUrl(String targetUrl, [Map<String, String>? headers]) async {
    await start();
    final sid = _registerSession(targetUrl, headers ?? {});
    final lanIp = await _getLocalIpAddress();
    final isM3u8 = targetUrl.toLowerCase().contains('.m3u8') || !targetUrl.toLowerCase().contains('.mp4');
    final endpoint = isM3u8 ? 'stream.m3u8' : 'direct';
    return 'http://$lanIp:$_port/$endpoint?sid=$sid';
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.contains('.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // 1. CORS headers for all responses
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final sid = request.uri.queryParameters['sid'];
    final session = sid != null ? _sessions[sid] : null;

    if (session == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Session expired or invalid');
      await request.response.close();
      return;
    }

    try {
      final rawUrl = request.uri.queryParameters['url'] ?? '';
      final isM3u8 = path.endsWith('.m3u8') ||
          path == '/stream.m3u8' ||
          rawUrl.toLowerCase().contains('.m3u8');

      if (isM3u8) {
        await _handlePlaylistRequest(request, session);
      } else if (path.startsWith('/segment') || path.startsWith('/proxy_resource') || path == '/direct') {
        await _handleSegmentRequest(request, session);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e, stack) {
      AppLogger.instance.error('StreamProxy', 'Request error: $path', e, stack);
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Bad Gateway: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<HttpClientResponse> _fetchWithHeaders(
    Uri uri,
    Map<String, String> headers, {
    String? rangeHeader,
    int maxRedirects = 5,
  }) async {
    Uri currentUri = uri;
    for (int i = 0; i < maxRedirects; i++) {
      final req = await _client.getUrl(currentUri);
      req.followRedirects = false;

      // Inject all required anti-leech headers
      headers.forEach((k, v) {
        req.headers.set(k, v);
      });

      if (rangeHeader != null) {
        req.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }

      final resp = await req.close();
      if (resp.isRedirect && resp.headers.value(HttpHeaders.locationHeader) != null) {
        final loc = resp.headers.value(HttpHeaders.locationHeader)!;
        currentUri = currentUri.resolve(loc);
        await resp.drain();
        continue;
      }
      return resp;
    }
    throw HttpException('Too many redirects while proxying $uri');
  }

  Future<void> _handlePlaylistRequest(HttpRequest request, _ProxySession session) async {
    final rawUrl = request.uri.queryParameters['url'];
    final targetUrl = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : session.targetUrl;
    final targetUri = Uri.parse(targetUrl);

    final upstreamResp = await _fetchWithHeaders(targetUri, session.headers);

    if (upstreamResp.statusCode != HttpStatus.ok) {
      request.response.statusCode = upstreamResp.statusCode;
      await upstreamResp.pipe(request.response);
      return;
    }

    // Read full playlist text
    final playlistContent = await utf8.decodeStream(upstreamResp);

    if (!playlistContent.contains('#EXTM3U')) {
      // Upstream returned non-playlist content; pipe directly
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('application', 'octet-stream');
      request.response.write(playlistContent);
      await request.response.close();
      return;
    }

    // Rewrite playlist lines to point through the proxy
    final lines = playlistContent.split(RegExp(r'\r?\n'));
    final rewritten = StringBuffer();
    final sid = session.id;

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.writeln(line);
        continue;
      }

      if (trimmed.startsWith('#')) {
        // Check for URI attributes in tags such as #EXT-X-KEY or #EXT-X-MAP
        if (trimmed.contains('URI="')) {
          final rewrittenLine = trimmed.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (match) {
              final originalUriStr = match.group(1)!;
              final resolvedUri = targetUri.resolve(originalUriStr);
              final isM3u8 = resolvedUri.path.endsWith('.m3u8') || resolvedUri.toString().contains('.m3u8');
              final ext = resolvedUri.pathSegments.isNotEmpty && resolvedUri.pathSegments.last.contains('.')
                  ? '.${resolvedUri.pathSegments.last.split('.').last.split('?').first}'
                  : '';
              final proxyUrl = isM3u8
                  ? '/stream.m3u8?sid=$sid&url=${Uri.encodeComponent(resolvedUri.toString())}'
                  : '/proxy_resource$ext?sid=$sid&url=${Uri.encodeComponent(resolvedUri.toString())}';
              return 'URI="$proxyUrl"';
            },
          );
          rewritten.writeln(rewrittenLine);
        } else {
          rewritten.writeln(line);
        }
      } else {
        // This is a media segment or sub-variant playlist URL
        final resolvedUri = targetUri.resolve(trimmed);
        final isSubPlaylist = resolvedUri.path.endsWith('.m3u8') || resolvedUri.toString().contains('.m3u8');
        if (isSubPlaylist) {
          rewritten.writeln('/stream.m3u8?sid=$sid&url=${Uri.encodeComponent(resolvedUri.toString())}');
        } else {
          final ext = resolvedUri.pathSegments.isNotEmpty && resolvedUri.pathSegments.last.contains('.')
              ? '.${resolvedUri.pathSegments.last.split('.').last.split('?').first}'
              : '.ts';
          rewritten.writeln('/segment$ext?sid=$sid&url=${Uri.encodeComponent(resolvedUri.toString())}');
        }
      }
    }

    final bytes = utf8.encode(rewritten.toString());
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> _handleSegmentRequest(HttpRequest request, _ProxySession session) async {
    final rawUrl = request.uri.queryParameters['url'];
    final targetUrl = (rawUrl != null && rawUrl.isNotEmpty) ? rawUrl : session.targetUrl;
    final targetUri = Uri.parse(targetUrl);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final upstreamResp = await _fetchWithHeaders(
      targetUri,
      session.headers,
      rangeHeader: rangeHeader,
    );

    request.response.statusCode = upstreamResp.statusCode;

    // Forward relevant headers
    if (upstreamResp.headers.contentType != null) {
      request.response.headers.contentType = upstreamResp.headers.contentType;
    } else {
      request.response.headers.set('Content-Type', 'video/MP2T');
    }

    final contentLength = upstreamResp.contentLength;
    if (contentLength > 0) {
      request.response.headers.contentLength = contentLength;
    }

    final contentRange = upstreamResp.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }

    final acceptRanges = upstreamResp.headers.value(HttpHeaders.acceptRangesHeader);
    if (acceptRanges != null) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, acceptRanges);
    } else {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }

    request.response.headers.set('Cache-Control', 'public, max-age=3600');

    try {
      await upstreamResp.pipe(request.response);
    } catch (_) {
      // Promptly destroy upstream socket on client seek/abort so bandwidth is never wasted on old chunks
      try {
        upstreamResp.detachSocket().then((s) => s.destroy()).catchError((_) {});
      } catch (_) {}
    }
  }
}
