import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service to handle YouTube trailer playback, stream extraction (via youtube-dl-api-server / invidious),
/// and rock-solid WebView embed generation matching the Voidflix web version.
class YoutubeService {
  static const String _defaultYtDlServer = 'https://yt-api.voidflix.org';

  /// List of public Invidious and Piped API endpoints for direct stream extraction
  static const List<String> _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://yewtu.be',
    'https://vid.puffyan.us',
    'https://invidious.nerdvpn.de',
    'https://yt.artemislena.eu',
  ];

  static const List<String> _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://pipedapi.tokhmi.xyz',
  ];

  /// Attempt to extract a direct MP4/HLS stream URL for a YouTube key using youtube-dl-api-server / invidious
  static Future<String?> extractDirectStream(String key) async {
    if (key.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final customServer = prefs.getString('voidflix_ytdl_server') ?? _defaultYtDlServer;

    // 1. Try youtube-dl-api-server endpoint (/api/info)
    try {
      final uri = Uri.parse('$customServer/api/info?url=https://www.youtube.com/watch?v=$key');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final info = data['info'] ?? data;
        if (info is Map<String, dynamic>) {
          if (info['url'] != null && info['url'].toString().startsWith('http')) {
            return info['url'].toString();
          }
          final formats = info['formats'] as List<dynamic>?;
          if (formats != null && formats.isNotEmpty) {
            // Pick highest quality mp4 stream with both video and audio
            for (final f in formats.reversed) {
              if (f is Map && f['url'] != null && (f['ext'] == 'mp4' || f['ext'] == 'webm')) {
                return f['url'].toString();
              }
            }
          }
        }
      }
    } catch (_) {}

    // 2. Try Invidious instances
    for (final host in _invidiousInstances) {
      try {
        final uri = Uri.parse('$host/api/v1/videos/$key');
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final streams = data['formatStreams'] as List<dynamic>?;
          if (streams != null && streams.isNotEmpty) {
            for (final s in streams.reversed) {
              if (s is Map && s['url'] != null && s['type'].toString().contains('mp4')) {
                return s['url'].toString();
              }
            }
            if (streams.first['url'] != null) {
              return streams.first['url'].toString();
            }
          }
        }
      } catch (_) {}
    }

    // 3. Try Piped instances
    for (final host in _pipedInstances) {
      try {
        final uri = Uri.parse('$host/streams/$key');
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final vStreams = data['videoStreams'] as List<dynamic>?;
          if (vStreams != null && vStreams.isNotEmpty) {
            for (final s in vStreams) {
              if (s is Map && s['url'] != null && s['mimeType'].toString().contains('mp4')) {
                return s['url'].toString();
              }
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Generates the HTML embed string matching the Voidflix web site (DetailModal.tsx)
  /// with no restrictive origin headers, ensuring clean playback without Error 150.
  static String buildTrailerEmbedHtml(String key, {bool isMuted = true}) {
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #000000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .video-container {
      position: relative;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      pointer-events: auto;
      transform: scale(1.02);
    }
  </style>
</head>
<body>
  <div class="video-container">
    <iframe
      id="trailer-frame"
      src="https://www.youtube.com/embed/$key?autoplay=1&mute=${isMuted ? 1 : 0}&controls=1&rel=0&modestbranding=1&playsinline=1&enablejsapi=1&loop=1&playlist=$key"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      allowfullscreen>
    </iframe>
  </div>
</body>
</html>''';
  }
}
