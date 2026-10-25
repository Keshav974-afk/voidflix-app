import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'subtitle_service.dart';
import '../constants/api_constants.dart';
import 'aoneroom_client.dart';
import 'aoneroom_matcher.dart';

class StreamQuality {
  final String label;
  final int height;
  final String url;

  const StreamQuality({
    required this.label,
    required this.height,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'height': height,
        'url': url,
      };

  factory StreamQuality.fromJson(Map<String, dynamic> json) => StreamQuality(
        label: (json['label'] as String?) ?? 'HD',
        height: (json['height'] as num?)?.toInt() ?? 0,
        url: (json['url'] as String?) ?? '',
      );

  @override
  String toString() => 'StreamQuality($label: $url)';
}

class ExtractedStream {
  final String url;
  final String type; // 'hls' or 'mp4'
  final String sourceName; // 'Nova', 'Atlas', 'Vidlink (VoidHD)', etc.
  final String language; // 'English', 'Hindi', etc.
  final Map<String, String> headers;
  final String? qualityLabel;
  final List<StreamQuality> qualities;
  final List<SubtitleTrack> subtitles;

  const ExtractedStream({
    required this.url,
    required this.type,
    required this.sourceName,
    this.language = 'English',
    required this.headers,
    this.qualityLabel,
    this.qualities = const [],
    this.subtitles = const [],
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'type': type,
        'sourceName': sourceName,
        'language': language,
        'headers': headers,
        'qualityLabel': qualityLabel,
        'qualities': qualities.map((q) => q.toJson()).toList(),
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
      };

  factory ExtractedStream.fromJson(Map<String, dynamic> json) => ExtractedStream(
        url: (json['url'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'hls',
        sourceName: (json['sourceName'] as String?) ?? 'Stream',
        language: (json['language'] as String?) ?? 'English',
        headers: (json['headers'] as Map<dynamic, dynamic>?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            {},
        qualityLabel: json['qualityLabel'] as String?,
        qualities: (json['qualities'] as List<dynamic>?)
                ?.map((q) => StreamQuality.fromJson(q as Map<String, dynamic>))
                .toList() ??
            [],
        subtitles: (json['subtitles'] as List<dynamic>?)
                ?.map((s) => SubtitleTrack.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );

  ExtractedStream copyWith({
    String? url,
    String? type,
    String? sourceName,
    String? language,
    Map<String, String>? headers,
    String? qualityLabel,
    List<StreamQuality>? qualities,
    List<SubtitleTrack>? subtitles,
  }) =>
      ExtractedStream(
        url: url ?? this.url,
        type: type ?? this.type,
        sourceName: sourceName ?? this.sourceName,
        language: language ?? this.language,
        headers: headers ?? this.headers,
        qualityLabel: qualityLabel ?? this.qualityLabel,
        qualities: qualities ?? this.qualities,
        subtitles: subtitles ?? this.subtitles,
      );

  @override
  String toString() => 'ExtractedStream($sourceName: $url, lang: $language)';
}

class CachedStreamEntry {
  final List<ExtractedStream> streams;
  final DateTime createdAt;

  CachedStreamEntry(this.streams, [DateTime? createdAt])
      : createdAt = createdAt ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > const Duration(hours: 3);

  Map<String, dynamic> toJson() => {
        'streams': streams.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory CachedStreamEntry.fromJson(Map<String, dynamic> json) => CachedStreamEntry(
        (json['streams'] as List<dynamic>?)
                ?.map((s) => ExtractedStream.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class _HlsVariantCandidate {
  final String url;
  final int height;
  final String rawLine;
  _HlsVariantCandidate({required this.url, required this.height, required this.rawLine});
}

class StreamExtractor {
  static final Map<String, CachedStreamEntry> _cache = {};

  static String getCacheKey(String type, int tmdbId, int season, int episode, {String prefix = ''}) =>
      '${prefix.isNotEmpty ? '$prefix:' : ''}$type:$tmdbId:$season:$episode';

  /// Retrieves cached streams from fast in-memory map or persistent SharedPreferences.
  static Future<CachedStreamEntry?> getCachedEntry(String key) async {
    // 1. In-memory check first (instant 0ms)
    if (_cache.containsKey(key)) {
      final entry = _cache[key]!;
      if (!entry.isExpired && entry.streams.isNotEmpty) {
        return entry;
      }
    }

    // 2. Persistent SharedPreferences check
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_stream_$key');
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final entry = CachedStreamEntry.fromJson(json);
        if (!entry.isExpired && entry.streams.isNotEmpty) {
          _cache[key] = entry; // Hydrate into memory
          return entry;
        } else {
          prefs.remove('cached_stream_$key');
        }
      }
    } catch (e) {
      debugPrint('Error reading stream cache from prefs: $e');
    }
    return null;
  }

  /// Returns cached subtitle tracks if available from previous extractions
  static Future<List<SubtitleTrack>> getSharedSubtitles(
    String type,
    int tmdbId,
    int season,
    int episode,
  ) async {
    // 1. Check vidlink cache
    final vidlinkKey = getCacheKey(type, tmdbId, season, episode, prefix: 'vidlink');
    final cachedVidlink = await getCachedEntry(vidlinkKey);
    if (cachedVidlink != null && cachedVidlink.streams.isNotEmpty) {
      final subs = cachedVidlink.streams.first.subtitles;
      if (subs.isNotEmpty) return subs;
    }

    // 2. Check aggregated all cache
    final allKey = getCacheKey(type, tmdbId, season, episode);
    final cachedAll = await getCachedEntry(allKey);
    if (cachedAll != null) {
      for (final s in cachedAll.streams) {
        if (s.subtitles.isNotEmpty) return s.subtitles;
      }
    }
    return [];
  }

  /// Fetches an already extracted and cached stream directly from our central Cloudflare database.
  static Future<ExtractedStream?> fetchFromRemoteDatabase(
    String type,
    int tmdbId,
    int season,
    int episode, {
    String server = '',
  }) async {
    try {
      final uri = Uri.parse(
        'https://voidflix.org/api/public/extract?type=$type&id=$tmdbId&s=$season&e=$episode&server=$server',
      );
      final res = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final hlsUrl = (data['hls'] ?? data['url']) as String?;
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          String resolveUrl(String u) {
            if (u.startsWith('http')) return u;
            if (u.startsWith('/')) return 'https://voidflix.org$u';
            return 'https://voidflix.org/$u';
          }

          final finalUrl = resolveUrl(hlsUrl);
          final qualities = <StreamQuality>[];
          final rawQualities = data['qualities'] as List<dynamic>?;
          if (rawQualities != null) {
            for (final q in rawQualities) {
              if (q is Map<String, dynamic> && q['url'] != null) {
                final qUrl = resolveUrl(q['url'] as String);
                final label = (q['label'] as String?) ?? 'HD';
                final height = (q['height'] as num?)?.toInt() ?? 0;
                qualities.add(StreamQuality(label: label, height: height, url: qUrl));
              }
            }
          }

          final subs = <SubtitleTrack>[];
          final rawSubs = (data['subs'] ?? data['subtitles']) as List<dynamic>?;
          if (rawSubs != null) {
            for (final s in rawSubs) {
              if (s is Map<String, dynamic> && s['url'] != null) {
                subs.add(SubtitleTrack(
                  label: s['label']?.toString() ?? 'English',
                  language: s['lang']?.toString() ?? s['language']?.toString() ?? 'en',
                  url: resolveUrl(s['url'].toString()),
                ));
              }
            }
          }

          final prov = data['provider'] ?? data['sourceName'] ?? (server.isNotEmpty ? server : 'Cine4K (Database)');

          return ExtractedStream(
            url: finalUrl,
            type: (data['kind'] ?? data['type'] ?? 'hls').toString(),
            sourceName: prov.toString(),
            headers: (data['headers'] as Map<dynamic, dynamic>?)?.map(
                  (k, v) => MapEntry(k.toString(), v.toString()),
                ) ??
                (data['referer'] != null ? {'Referer': data['referer'].toString()} : {}),
            qualities: qualities,
            subtitles: subs,
          );
        }
      }
    } catch (e) {
      debugPrint('StreamExtractor: Remote database fetch skipped: $e');
    }
    return null;
  }

  /// Saves a successfully extracted stream link to our central Cloudflare KV database for all app and web users.
  static void saveToRemoteDatabase(
    String type,
    int tmdbId,
    int season,
    int episode,
    ExtractedStream stream, {
    String server = '',
  }) {
    if (stream.url.isEmpty) return;
    // Asynchronous background fire-and-forget save
    Future(() async {
      try {
        final uri = Uri.parse('https://voidflix.org/api/public/extract');
        final payload = {
          'type': type,
          'id': tmdbId,
          's': season,
          'e': episode,
          'server': server.isNotEmpty ? server : stream.sourceName,
          'stream': {
            'url': stream.url,
            'hls': stream.url,
            'type': stream.type,
            'kind': stream.type,
            'sourceName': stream.sourceName,
            'headers': stream.headers,
            'qualities': stream.qualities.map((q) => q.toJson()).toList(),
            'subtitles': stream.subtitles.map((s) => s.toJson()).toList(),
          },
        };
        await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 5));
        debugPrint('StreamExtractor: Stream saved to central Cloudflare KV database for $type $tmdbId');
      } catch (e) {
        debugPrint('StreamExtractor: Error saving stream to database: $e');
      }
    });
  }

  /// Sets cached streams in both in-memory map and asynchronous SharedPreferences.
  static void setCachedEntry(String key, List<ExtractedStream> streams) {
    if (streams.isEmpty) return;
    final entry = CachedStreamEntry(streams);
    _cache[key] = entry;

    SharedPreferences.getInstance().then((prefs) => prefs.setString('cached_stream_$key', jsonEncode(entry.toJson()))).catchError((_) => false);

    // Save extracted streams to central Cloudflare database so all users get it directly
    try {
      final parts = key.split(':');
      if (parts.length >= 4) {
        final episode = int.tryParse(parts.last) ?? 1;
        final season = int.tryParse(parts[parts.length - 2]) ?? 1;
        final tmdbId = int.tryParse(parts[parts.length - 3]) ?? 0;
        final type = parts[parts.length - 4];
        final prefix = parts.length > 4 ? parts.first : '';

        if (tmdbId > 0) {
          for (final s in streams) {
            saveToRemoteDatabase(
              type,
              tmdbId,
              season,
              episode,
              s,
              server: prefix.isNotEmpty ? prefix : s.sourceName,
            );
          }
        }
      }
    } catch (_) {}
  }

  static void invalidateCache(String type, int tmdbId, int season, int episode) {
    final keys = [
      getCacheKey(type, tmdbId, season, episode),
      getCacheKey(type, tmdbId, season, episode, prefix: 'cinejoy'),
      getCacheKey(type, tmdbId, season, episode, prefix: 'vidrock'),
      getCacheKey(type, tmdbId, season, episode, prefix: 'vidlink'),
      getCacheKey(type, tmdbId, season, episode, prefix: 'voidflix'),
      getCacheKey(type, tmdbId, season, episode, prefix: 'nova'),
      getCacheKey(type, tmdbId, season, episode, prefix: 'atlas'),
    ];
    for (final k in keys) {
      _cache.remove(k);
      SharedPreferences.getInstance().then((prefs) => prefs.remove('cached_stream_$k')).catchError((_) => false);
    }
  }

  static void clearCache() {
    _cache.clear();
    SharedPreferences.getInstance().then((prefs) {
      final keys = prefs.getKeys().where((k) => k.startsWith('cached_stream_')).toList();
      for (final k in keys) {
        prefs.remove(k);
      }
    }).catchError((_) {});
  }

  static const _vidrockHexKey =
      '7f3e9c2a8b5d1f4e6a9c3b7d2e5f8a1c4b6d9e2f5a8c1b4d7e9f2a5c8b1d4e7f';
  static final _aesGcm = AesGcm.with256bits();
  static final _secretKey = SecretKey(_hexToBytes(_vidrockHexKey));

  static List<int> _hexToBytes(String hex) {
    final list = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      list.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return list;
  }

  static Future<String> _decryptVidrockUrl(String enc) async {
    final cleanEnc = enc.trim();
    if (cleanEnc.length < 28) return '';
    var b64 = cleanEnc.replaceAll('-', '+').replaceAll('_', '/');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    try {
      final data = base64Decode(b64);
      if (data.length < 28) return '';
      final iv = data.sublist(0, 12);
      final ciphertextWithTag = data.sublist(12);
      final ciphertext =
          ciphertextWithTag.sublist(0, ciphertextWithTag.length - 16);
      final mac = Mac(ciphertextWithTag.sublist(ciphertextWithTag.length - 16));

      final secretBox = SecretBox(ciphertext, nonce: iv, mac: mac);
      final clearBytes =
          await _aesGcm.decrypt(secretBox, secretKey: _secretKey);
      return utf8.decode(clearBytes);
    } catch (_) {
      return '';
    }
  }

  /// Extracts direct HLS stream URLs from Vidrock (Nova, Atlas, Orion, Astra, Luna, Lyra)
  static Future<List<ExtractedStream>> extractVidrock({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'vidrock');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Vidrock streams for $cacheKey (instant!)');
      return cached.streams;
    }

    try {
      final path =
          type == 'tv' ? 'tv/$tmdbId/$season/$episode' : 'movie/$tmdbId';
      final res = await http.get(
        Uri.parse('https://vidrock.ru/api/$path'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://vvid.moe/',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = <ExtractedStream>[];

      // Preferred priority order of sources (Orion is primary active 1080p cluster, Luna/Lyra fallbacks)
      final order = ['Orion', 'Nova', 'Atlas', 'Astra', 'Luna', 'Lyra'];
      final candidateServers = <String>[
        ...order,
        ...json.keys.where((k) => !order.contains(k) && !['Hindi', 'Tamil', 'Telugu'].contains(k)),
      ];

      for (final name in candidateServers) {
        final src = json[name] as Map<String, dynamic>?;
        if (src != null && src['url'] != null) {
          final enc = src['url'] as String;
          if (enc.trim().length < 28) continue;
          try {
            final streamUrl = await _decryptVidrockUrl(enc);
            if (streamUrl.isNotEmpty && streamUrl.startsWith('http')) {
              final lang = (src['language'] as String?) ?? 'English';
              final qList = await _resolveHlsVariants(streamUrl, {
                'Referer': 'https://vidrock.ru/',
                'Origin': 'https://vidrock.ru',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              });
              results.add(ExtractedStream(
                url: streamUrl,
                type: (src['type'] as String?) ?? 'hls',
                sourceName: name,
                language: lang,
                headers: {
                  'Referer': 'https://vidrock.ru/',
                  'Origin': 'https://vidrock.ru',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
                qualityLabel: 'Auto (Adaptive)',
                qualities: qList,
              ));
            }
          } catch (e) {
            debugPrint('Vidrock decryption failed for $name: $e');
          }
        }
      }
      if (results.isNotEmpty) {
        setCachedEntry(cacheKey, results);
      }
      return results;
    } catch (e) {
      debugPrint('Vidrock extraction error: $e');
      return [];
    }
  }

  /// Multi-mirror fallback for Vidlink ID encryption helper to prevent timeouts
  static Future<String?> _encryptVidlinkId(int tmdbId) async {
    final mirrors = [
      'https://enc-dec.app/api',
      'https://enc-dec.vercel.app/api',
      'https://encdec.vercel.app/api',
    ];
    for (final host in mirrors) {
      try {
        final res = await http.get(
          Uri.parse('$host/enc-vidlink?text=$tmdbId'),
        ).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final encId = json['result'] as String?;
          if (encId != null && encId.isNotEmpty) {
            return encId;
          }
        }
      } catch (e) {
        debugPrint('Mirror $host for enc-vidlink failed: $e');
      }
    }
    return null;
  }

  /// Extracts direct stream and all multilingual subtitles & MP4 qualities via Vidlink
  static Future<ExtractedStream?> extractVidlink({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'vidlink');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Vidlink stream for $cacheKey (instant!)');
      return cached.streams.first;
    }

    try {
      // 1. Get encrypted TMDB ID from resilient helper mirrors
      final encId = await _encryptVidlinkId(tmdbId);
      if (encId == null || encId.isEmpty) return null;

      // 2. Fetch Vidlink stream definition
      final endpoint = type == 'tv'
          ? 'https://vidlink.pro/api/b/tv/$encId/$season/$episode'
          : 'https://vidlink.pro/api/b/movie/$encId';

      final res = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Referer': 'https://vidlink.pro/',
          'Origin': 'https://vidlink.pro',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded;
      final streamObj = data['stream'] as Map<String, dynamic>?;
      if (streamObj == null) return null;

      // Extract Subtitles
      final subs = <SubtitleTrack>[];
      final captionsRaw = streamObj['captions'] as List<dynamic>?;
      if (captionsRaw != null) {
        for (final c in captionsRaw) {
          if (c is Map<String, dynamic>) {
            final url = c['url'] as String?;
            final label = (c['language'] ?? c['label'] ?? 'Sub') as String;
            if (url != null && url.isNotEmpty) {
              subs.add(SubtitleTrack(
                label: label,
                language: label.toLowerCase().substring(0, label.length > 3 ? 3 : label.length),
                url: url,
              ));
            }
          }
        }
      }

      // Extract Qualities
      final qualities = <StreamQuality>[];
      final rawQualitiesMap = streamObj['qualities'];
      final Map<String, dynamic>? qualitiesMap =
          rawQualitiesMap is Map ? Map<String, dynamic>.from(rawQualitiesMap) : null;
      String? primaryUrl;

      if (qualitiesMap != null && qualitiesMap.isNotEmpty) {
        final sortedKeys = qualitiesMap.keys.toList()
          ..sort((a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0));

        for (final qKey in sortedKeys) {
          final qObj = qualitiesMap[qKey];
          if (qObj is Map && qObj['url'] != null) {
            final qUrl = qObj['url'] as String;
            final height = int.tryParse(qKey) ?? 0;
            qualities.add(StreamQuality(
              label: '${qKey}p',
              height: height,
              url: qUrl,
            ));
            primaryUrl ??= qUrl;
          }
        }
      } else if (streamObj['playlist'] != null) {
        primaryUrl = streamObj['playlist'] as String;
      }

      if (primaryUrl != null && primaryUrl.isNotEmpty) {
        final stream = ExtractedStream(
          url: primaryUrl,
          type: (streamObj['type'] as String?) ?? 'mp4',
          sourceName: 'VoidHD',
          headers: {
            'Referer': 'https://vidlink.pro/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          qualityLabel: qualities.isNotEmpty ? qualities.first.label : 'HD',
          qualities: qualities,
          subtitles: subs,
        );
        setCachedEntry(cacheKey, [stream]);
        return stream;
      }

      return null;
    } catch (e) {
      debugPrint('Vidlink extraction error: $e');
      return null;
    }
  }

  /// Extracts high-speed proxied streams directly from Voidflix API backend (same as flowflix-web)
  static Future<ExtractedStream?> extractVoidflixBackend({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'voidflix');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Voidflix stream for $cacheKey (instant!)');
      return cached.streams.first;
    }

    try {
      final uri = Uri.parse(
        'https://voidflix.org/api/public/extract?type=$type&id=$tmdbId&s=$season&e=$episode',
      );
      final res = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final rawHls = json['hls'] as String?;
      if (rawHls == null || rawHls.isEmpty) return null;

      String resolveUrl(String u) {
        if (u.startsWith('http')) return u;
        if (u.startsWith('/')) return 'https://voidflix.org$u';
        return 'https://voidflix.org/$u';
      }

      final hlsUrl = resolveUrl(rawHls);
      final kind = (json['kind'] as String?) ?? 'mp4';
      final rawProvider = (json['provider'] as String?) ?? 'Direct';
      final cleanProvider = rawProvider.toLowerCase().contains('vidlink')
          ? 'VoidHD'
          : rawProvider.toLowerCase().contains('vidrock')
              ? 'PulsarHD'
              : rawProvider.toLowerCase().contains('videasy')
                  ? 'TurboStream'
                  : 'Ultra';

      // Parse Qualities
      final qualities = <StreamQuality>[];
      final rawQualities = json['qualities'] as List<dynamic>?;
      if (rawQualities != null) {
        for (final q in rawQualities) {
          if (q is Map<String, dynamic> && q['url'] != null) {
            final qUrl = resolveUrl(q['url'] as String);
            final label = (q['label'] as String?) ?? 'HD';
            final height = (q['height'] as num?)?.toInt() ?? 0;
            qualities.add(StreamQuality(label: label, height: height, url: qUrl));
          }
        }
      }

      // Parse Subtitles
      final subs = <SubtitleTrack>[];
      final rawSubs = json['subs'] as List<dynamic>?;
      if (rawSubs != null) {
        for (final s in rawSubs) {
          if (s is Map<String, dynamic> && s['url'] != null) {
            final sUrl = resolveUrl(s['url'] as String);
            final label = (s['label'] as String?) ?? 'Sub';
            final lang = (s['lang'] as String?) ?? label;
            subs.add(SubtitleTrack(label: label, language: lang, url: sUrl));
          }
        }
      }

      final stream = ExtractedStream(
        url: hlsUrl,
        type: kind,
        sourceName: 'VoidDirect ($cleanProvider)',
        headers: {
          'Referer': 'https://voidflix.org/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        qualityLabel: qualities.isNotEmpty ? qualities.first.label : 'HD',
        qualities: qualities,
        subtitles: subs,
      );
      setCachedEntry(cacheKey, [stream]);
      return stream;
    } catch (e) {
      debugPrint('Voidflix backend extraction error: $e');
      return null;
    }
  }

  /// Extracts Telegram streams from Voidflix VPS indexer (25k channel database)
  /// Features multi-audio (Hindi, English, Telugu, Tamil), multi-quality (4K, 1080p, 720p)
  /// and direct HTTP 206 byte-range streaming for Native Player.
  static Future<List<ExtractedStream>> extractTelegram({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'telegram');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Telegram streams for $cacheKey (instant!)');
      return cached.streams;
    }

    try {
      final endpoint = type == 'tv'
          ? 'https://api.voidflix.org/api/source/tv/$tmdbId/$season/$episode'
          : 'https://api.voidflix.org/api/source/movie/$tmdbId';

      final res = await http.get(
        Uri.parse(endpoint),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Connection': 'keep-alive',
        },
      ).timeout(const Duration(milliseconds: 2500));

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] != true || data['streams'] == null) return [];

      final rawStreams = data['streams'] as List<dynamic>;
      if (rawStreams.isEmpty) return [];

      // Build quality variants
      final qualities = <StreamQuality>[];
      for (final s in rawStreams) {
        if (s is Map<String, dynamic>) {
          final q = (s['quality'] as String?) ?? '1080p';
          final a = (s['audio'] as String?) ?? 'Audio';
          final rawUrl = (s['raw_url'] as String?) ?? (s['stream_url'] as String?) ?? '';
          if (rawUrl.isNotEmpty) {
            int height = 1080;
            if (q.contains('4K') || q.contains('2160p')) {
              height = 2160;
            } else if (q.contains('1080p')) {
              height = 1080;
            } else if (q.contains('720p')) {
              height = 720;
            } else if (q.contains('480p')) {
              height = 480;
            } else if (q.contains('360p')) {
              height = 360;
            }

            qualities.add(StreamQuality(
              label: '$q • $a',
              height: height,
              url: rawUrl,
            ));
          }
        }
      }

      final results = <ExtractedStream>[];
      for (final s in rawStreams) {
        if (s is Map<String, dynamic>) {
          final rawUrl = (s['raw_url'] as String?) ?? (s['stream_url'] as String?) ?? '';
          if (rawUrl.isEmpty) continue;

          final quality = (s['quality'] as String?) ?? '1080p';
          final audio = (s['audio'] as String?) ?? 'Original Audio';

          // Determine language for player audio matching
          String lang = 'English';
          if (audio.contains('Hindi')) {
            lang = 'Hindi';
          } else if (audio.contains('Telugu')) {
            lang = 'Telugu';
          } else if (audio.contains('Tamil')) {
            lang = 'Tamil';
          } else if (audio.contains('Malayalam')) {
            lang = 'Malayalam';
          } else if (audio.contains('Kannada')) {
            lang = 'Kannada';
          } else if (audio.contains('Korean')) {
            lang = 'Korean';
          } else if (audio.contains('Japanese')) {
            lang = 'Japanese';
          }

          results.add(ExtractedStream(
            url: rawUrl,
            type: 'mp4',
            sourceName: 'Meow [$quality • $audio]',
            language: lang,
            headers: {
              'User-Agent': 'Voidflix-NativePlayer/1.0',
            },
            qualityLabel: quality,
            qualities: qualities,
            subtitles: const [],
          ));
        }
      }

      if (results.isNotEmpty) {
        setCachedEntry(cacheKey, results);
      }
      return results;
    } catch (e) {
      debugPrint('Telegram extraction error: $e');
      return [];
    }
  }

  /// Direct file resolver from Voidflix download API (Stremio/direct MP4 addon)
  static Future<String?> extractDirectFileUrl({
    required String type,
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      final uri = Uri.parse(
        'https://voidflix.org/api/public/download?type=$type&id=$tmdbId&s=$season&e=$episode',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final url = json['url'] as String?;
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    } catch (_) {}
    return null;
  }

  static int? _extractResolutionHeight(String infoLine) {
    final match = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(infoLine);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static Future<List<StreamQuality>> _resolveHlsVariants(
    String masterPlaylistUrl,
    Map<String, String> headers,
  ) async {
    try {
      final res = await http.get(Uri.parse(masterPlaylistUrl), headers: headers)
          .timeout(const Duration(milliseconds: 1800));
      if (res.statusCode == 200 && res.body.contains('#EXTM3U')) {
        final lines = res.body.split('\n');
        final variants = <_HlsVariantCandidate>[];
        String? currentInfo;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            currentInfo = line;
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            final variantUrl = Uri.parse(masterPlaylistUrl).resolve(line).toString();
            final height = _extractResolutionHeight(currentInfo ?? '') ??
                (line.toLowerCase().contains('4k')
                    ? 2160
                    : line.toLowerCase().contains('1080')
                        ? 1080
                        : line.toLowerCase().contains('720')
                            ? 720
                            : line.toLowerCase().contains('480')
                                ? 480
                                : line.toLowerCase().contains('360')
                                    ? 360
                                    : 0);
            variants.add(_HlsVariantCandidate(url: variantUrl, height: height, rawLine: line));
            currentInfo = null;
          }
        }

        if (variants.isNotEmpty) {
          variants.sort((a, b) => b.height.compareTo(a.height));
          return [
            StreamQuality(label: 'Auto (Adaptive)', height: 0, url: masterPlaylistUrl),
            ...variants.map((v) {
              final label = v.height >= 2160
                  ? '4K Ultra HD'
                  : v.height >= 1080
                      ? '1080p Full HD'
                      : v.height >= 720
                          ? '720p HD'
                          : v.height >= 480
                              ? '480p (Fast / Low Data)'
                              : '${v.height}p (Data Saver)';
              return StreamQuality(label: label, height: v.height, url: v.url);
            }),
          ];
        }
      }
    } catch (_) {}

    return [
      StreamQuality(label: 'Auto (Adaptive)', height: 0, url: masterPlaylistUrl),
      StreamQuality(label: '1080p Full HD', height: 1080, url: masterPlaylistUrl),
      StreamQuality(label: '720p HD', height: 720, url: masterPlaylistUrl),
      StreamQuality(label: '480p (Fast / Low Data)', height: 480, url: masterPlaylistUrl),
    ];
  }

  static Future<ExtractedStream?> _processCinejoyPlaylist({
    required String playlistUrl,
    required String serverName,
    required bool is4k,
  }) async {
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };

    try {
      final res = await http.get(Uri.parse(playlistUrl), headers: headers).timeout(const Duration(milliseconds: 2500));
      if (res.statusCode == 200 && res.body.contains('#EXTM3U')) {
        // Audio health check: Detect and reject servers with broken/502 audio CDNs (e.g. lit.cheaptruckrepairs.cc)
        final audioMatches = RegExp(r'#EXT-X-MEDIA:TYPE=AUDIO.*?URI="([^"]+)"').allMatches(res.body);
        if (audioMatches.isNotEmpty) {
          final firstAudioUri = audioMatches.first.group(1);
          if (firstAudioUri != null) {
            final resolvedAudio = Uri.parse(playlistUrl).resolve(firstAudioUri).toString();
            try {
              final aCheck = await http.get(Uri.parse(resolvedAudio), headers: headers)
                  .timeout(const Duration(milliseconds: 1500));
              if (aCheck.statusCode >= 400) {
                debugPrint('Cinejoy $serverName audio CDN failed with ${aCheck.statusCode} - skipping to working audio server!');
                return null;
              }
            } catch (_) {
              debugPrint('Cinejoy $serverName audio CDN timed out - skipping to working audio server!');
              return null;
            }
          }
        }
        final lines = res.body.split('\n');
        final variants = <_HlsVariantCandidate>[];
        String? currentInfo;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            currentInfo = line;
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            final variantUrl = Uri.parse(playlistUrl).resolve(line).toString();
            final height = _extractResolutionHeight(currentInfo ?? '') ??
                (line.toLowerCase().contains('4k')
                    ? 2160
                    : line.toLowerCase().contains('1080')
                        ? 1080
                        : line.toLowerCase().contains('720')
                            ? 720
                            : line.toLowerCase().contains('360')
                                ? 360
                                : 0);
            variants.add(_HlsVariantCandidate(url: variantUrl, height: height, rawLine: line));
            currentInfo = null;
          }
        }

        if (variants.isNotEmpty) {
          // Probe all variants concurrently with 1.5s timeout to drop dead (e.g. 502/404) streams
          final workingVariants = <_HlsVariantCandidate>[];
          final checks = await Future.wait(variants.map((v) async {
            try {
              final testRes = await http.get(Uri.parse(v.url), headers: headers).timeout(const Duration(milliseconds: 1500));
              if (testRes.statusCode != 200) return false;

              // For 4K streams, verify child segments are healthy and not returning 502/404 from CDN
              if (v.height >= 2160 && testRes.body.contains('.html')) {
                final segLines = testRes.body.split('\n');
                final segmentUrls = <String>[];
                for (final sl in segLines) {
                  final t = sl.trim();
                  if (t.isNotEmpty && !t.startsWith('#')) {
                    segmentUrls.add(Uri.parse(v.url).resolve(t).toString());
                    if (segmentUrls.length >= 2) break;
                  }
                }
                final testSeg = segmentUrls.length > 1 ? segmentUrls[1] : (segmentUrls.isNotEmpty ? segmentUrls[0] : null);
                if (testSeg != null) {
                  final segRes = await http.head(Uri.parse(testSeg), headers: headers).timeout(const Duration(milliseconds: 1200));
                  if (segRes.statusCode != 200) return false;
                }
              }
              return true;
            } catch (_) {
              return false;
            }
          }));

          for (int i = 0; i < variants.length; i++) {
            if (checks[i]) {
              workingVariants.add(variants[i]);
            }
          }

          if (workingVariants.isNotEmpty) {
            // Sort by height descending (highest working quality first)
            workingVariants.sort((a, b) => b.height.compareTo(a.height));
            final has4k = workingVariants.any((v) => v.height >= 2160);

            // Master playlist provides full adaptive bitrate ladder to ExoPlayer/fvp.
            // When seeking or on low internet, ExoPlayer immediately starts with 360p/480p,
            // delivering <1-2s time-to-first-frame without freezing or stalling!
            final qList = <StreamQuality>[
              StreamQuality(
                label: 'Auto (Adaptive)',
                height: 0,
                url: playlistUrl,
              ),
              ...workingVariants.map((v) {
                final label = v.height >= 2160
                    ? '4K Ultra HD'
                    : v.height >= 1080
                        ? '1080p Full HD'
                        : v.height >= 720
                            ? '720p HD'
                            : v.height >= 480
                                ? '480p (Fast / Low Data)'
                                : '${v.height}p (Data Saver)';
                return StreamQuality(label: label, height: v.height, url: v.url);
              }),
            ];

            return ExtractedStream(
              url: playlistUrl,
              type: 'hls',
              sourceName: 'Cinejoy ($serverName${has4k ? " 4K" : ""})',
              headers: headers,
              qualityLabel: 'Auto (Adaptive)',
              qualities: qList,
                          );
          }
        }
      }
    } catch (e) {
      debugPrint('Cinejoy playlist probe fallback: $e');
    }

    return ExtractedStream(
      url: playlistUrl,
      type: 'hls',
      sourceName: 'Cinejoy ($serverName${is4k ? " 4K" : ""})',
      headers: headers,
      qualityLabel: 'Auto (Adaptive)',
      qualities: [
        StreamQuality(label: 'Auto (Adaptive)', height: 0, url: playlistUrl),
        if (is4k) StreamQuality(label: '4K Ultra HD', height: 2160, url: playlistUrl),
        StreamQuality(label: '1080p Full HD', height: 1080, url: playlistUrl),
        StreamQuality(label: '720p HD', height: 720, url: playlistUrl),
        StreamQuality(label: '480p (Fast / Low Data)', height: 480, url: playlistUrl),
      ],
          );
  }

  /// Extracts high-bitrate direct HLS streams (up to 4K Ultra HD & 1080p) via Cinejoy / wing.st using enc-dec.app
  static Future<List<ExtractedStream>> extractCinejoy({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    String? title,
    String? year,
    int season = 1,
    int episode = 1,
    String? preferredServer, // 'Lisbon' (4K) or 'Nebula' (1080p)
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'cinejoy');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Cinejoy streams for $cacheKey (instant!)');
      return cached.streams;
    }

    try {
      String resolvedTitle = (title != null && title.isNotEmpty) ? title : '';
      String resolvedYear = (year != null && year.isNotEmpty) ? year : '';
      String imdbId = '';

      if (resolvedTitle.isEmpty) {
        Map<String, dynamic>? tmdbJson;
        try {
          final tmdbUri = Uri.parse(
            'https://api.themoviedb.org/3/$type/$tmdbId?api_key=${ApiConstants.tmdbApiKey}&append_to_response=external_ids',
          );
          final tmdbRes = await http.get(tmdbUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          }).timeout(const Duration(seconds: 3));
          if (tmdbRes.statusCode == 200) {
            tmdbJson = jsonDecode(tmdbRes.body) as Map<String, dynamic>;
          }
        } catch (_) {}

        if (tmdbJson == null) {
          try {
            final proxyUri = Uri.parse(
              'https://voidflix.org/api/public/tmdb?path=/$type/$tmdbId&append_to_response=external_ids',
            );
            final proxyRes = await http.get(proxyUri, headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            }).timeout(const Duration(seconds: 3));
            if (proxyRes.statusCode == 200) {
              tmdbJson = jsonDecode(proxyRes.body) as Map<String, dynamic>;
            }
          } catch (_) {}
        }

        if (tmdbJson != null) {
          resolvedTitle = (tmdbJson['title'] ?? tmdbJson['name'] ?? '') as String;
          final rawDate = (tmdbJson['release_date'] ?? tmdbJson['first_air_date'] ?? '') as String;
          resolvedYear = rawDate.length >= 4 ? rawDate.substring(0, 4) : '';
          final extIds = tmdbJson['external_ids'] as Map<String, dynamic>?;
          imdbId = (tmdbJson['imdb_id'] ?? extIds?['imdb_id'] ?? '') as String;
        }
      }

      if (resolvedTitle.isEmpty) return [];
      final finalTitle = resolvedTitle;
      final finalYear = resolvedYear;

      final serversToTry = preferredServer != null
          ? [preferredServer, if (preferredServer != 'Lisbon') 'Lisbon', if (preferredServer != 'Nebula') 'Nebula']
          : ['Lisbon', 'Nebula'];

      final results = <ExtractedStream>[];
      final mirrors = [
        'https://enc-dec.app/api',
        'https://enc-dec.vercel.app/api',
        'https://encdec.vercel.app/api',
      ];

      for (final srv in serversToTry) {
        try {
          final tParam = type == 'movie' ? 'movie' : 'series';
          final wingUrl = type == 'movie'
              ? 'https://api.wing.st/?title=${Uri.encodeComponent(finalTitle)}&type=$tParam&year=$finalYear&imdb=$imdbId&tmdb=$tmdbId&server=$srv'
              : 'https://api.wing.st/?title=${Uri.encodeComponent(finalTitle)}&type=$tParam&year=$finalYear&imdb=$imdbId&tmdb=$tmdbId&server=$srv&season=$season&episode=$episode';

          // Step 1: Encrypt request via enc-dec
          Map<String, dynamic>? encResult;
          for (final host in mirrors) {
            try {
              final encUri = Uri.parse('$host/enc-cinejoy?url=${Uri.encodeComponent(wingUrl)}');
              final encRes = await http.get(encUri, headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              }).timeout(const Duration(seconds: 4));
              if (encRes.statusCode == 200) {
                final json = jsonDecode(encRes.body) as Map<String, dynamic>;
                if (json['status'] == 200 && json['result'] is Map<String, dynamic>) {
                  encResult = json['result'] as Map<String, dynamic>;
                  break;
                }
              }
            } catch (_) {}
          }

          if (encResult == null) continue;
          final encData = encResult['data'] as String?;
          final encState = encResult['state'];
          if (encData == null || encState == null) continue;

          // Step 2: Query wing.st/g with base64url-decoded bytes
          var b64Data = encData.replaceAll('-', '+').replaceAll('_', '/');
          while (b64Data.length % 4 != 0) {
            b64Data += '=';
          }
          final decodedPayloadBytes = base64Decode(b64Data);

          final wingRes = await http.post(
            Uri.parse('https://api.wing.st/g'),
            body: decodedPayloadBytes,
            headers: {
              'Accept': '*/*',
              'Origin': 'https://cinejoy.pk',
              'Referer': 'https://cinejoy.pk/',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          ).timeout(const Duration(seconds: 5));

          if (wingRes.statusCode != 200) continue;
          final encryptedBytes = wingRes.bodyBytes;

          // Step 3: Decrypt via enc-dec dec-cinejoy
          final b64Encrypted = base64UrlEncode(encryptedBytes).replaceAll('=', '');
          Map<String, dynamic>? decResult;
          for (final host in mirrors) {
            try {
              final decUri = Uri.parse('$host/dec-cinejoy');
              final decRes = await http.post(
                decUri,
                body: jsonEncode({'text': b64Encrypted, 'state': encState}),
                headers: {
                  'Content-Type': 'application/json',
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
              ).timeout(const Duration(seconds: 5));
              if (decRes.statusCode == 200) {
                final json = jsonDecode(decRes.body) as Map<String, dynamic>;
                if (json['status'] == 200 && json['result'] is Map<String, dynamic>) {
                  decResult = json['result'] as Map<String, dynamic>;
                  break;
                }
              }
            } catch (_) {}
          }

          if (decResult == null) continue;
          final dataMap = decResult['data'] as Map<String, dynamic>?;
          final streamList = dataMap?['stream'] as List<dynamic>?;
          if (streamList == null || streamList.isEmpty) continue;

          for (final s in streamList) {
            if (s is Map<String, dynamic> && s['playlist'] != null) {
              final playlistUrl = s['playlist'] as String;
              if (playlistUrl.isNotEmpty && playlistUrl.startsWith('http')) {
                final is4k = srv == 'Lisbon';
                final stream = await _processCinejoyPlaylist(
                  playlistUrl: playlistUrl,
                  serverName: srv,
                  is4k: is4k,
                );
                if (stream != null) {
                  results.add(stream);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Cinejoy $srv extraction error: $e');
        }
      }

      if (results.isNotEmpty) {
        setCachedEntry(cacheKey, results);
      }
      return results;
    } catch (e) {
      debugPrint('Cinejoy extraction overall error: $e');
      return [];
    }
  }

  /// Master extraction method that queries all direct stream extractors
  /// and aggregates audio sources, qualities, and all subtitle tracks.
  /// Automatically uses cached results within 3 hours for instant resumption.
  /// Netflix-style background pre-warming: pre-resolves streams before the user taps Play!
  static void prewarm(String type, int tmdbId, {int season = 1, int episode = 1}) {
    final key = getCacheKey(type, tmdbId, season, episode);
    if (_cache.containsKey(key)) return;
    extractAll(type: type, tmdbId: tmdbId, season: season, episode: episode).ignore();
  }

  static Future<List<ExtractedStream>> extractAll({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
    bool forceRefresh = false,
  }) async {
    final key = getCacheKey(type, tmdbId, season, episode);

    if (!forceRefresh) {
      // 1. In-memory & local SharedPreferences cache check
      final cached = await getCachedEntry(key);
      if (cached != null && cached.streams.isNotEmpty) {
        debugPrint('StreamExtractor: Reusing cached aggregated streams for $key (instant!)');
        return cached.streams;
      }

      // 2. Cloudflare KV Database check (instant direct playback without re-scraping!)
      final remoteStream = await fetchFromRemoteDatabase(type, tmdbId, season, episode);
      if (remoteStream != null) {
        debugPrint('StreamExtractor: Retrieved direct stream from Cloudflare KV database for $key (instant 0ms!)');
        final remoteEntry = [remoteStream];
        setCachedEntry(key, remoteEntry);
        return remoteEntry;
      }
    }

    final results = <ExtractedStream>[];
    List<SubtitleTrack> sharedSubs = [];

    // Parallel concurrent extraction across all direct sources
    try {
      final telegramFuture = extractTelegram(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ).catchError((e) {
        debugPrint('Telegram extractor error: $e');
        return <ExtractedStream>[];
      });

      final cinejoyFuture = extractCinejoy(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ).catchError((e) {
        debugPrint('Cinejoy extractor error: $e');
        return <ExtractedStream>[];
      });

      final vidrockFuture = extractVidrock(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ).catchError((e) {
        debugPrint('Vidrock extractor error: $e');
        return <ExtractedStream>[];
      });

      final vidlinkFuture = extractVidlink(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ).catchError((e) {
        debugPrint('Vidlink extractor error: $e');
        return null;
      });

      final voidflixFuture = extractVoidflixBackend(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      ).catchError((e) {
        debugPrint('Voidflix extractor error: $e');
        return null;
      });

      // Netflix-Style Fast Path: if ultra-fast Telegram or Cinejoy returns in <650ms,
      // return immediately so the player starts playing in <1 second!
      // The remaining extractors will complete in background and enrich the cache.
      final fastDirect = await Future.any([
        telegramFuture.then((list) => list.isNotEmpty ? list : null),
        cinejoyFuture.then((list) => list.isNotEmpty ? list : null),
        Future.delayed(const Duration(milliseconds: 650), () => null),
      ]);

      if (fastDirect != null && fastDirect.isNotEmpty) {
        debugPrint('StreamExtractor: Fast-path ready in <650ms (${fastDirect.first.sourceName}) - instant play!');
        setCachedEntry(key, fastDirect);

        // Background worker to enrich cache with all alternate audio & subtitles
        Future.wait([telegramFuture, cinejoyFuture, vidrockFuture, vidlinkFuture, voidflixFuture]).then((all) {
          try {
            final tList = all[0] as List<ExtractedStream>;
            final cList = all[1] as List<ExtractedStream>;
            final vList = all[2] as List<ExtractedStream>;
            final vl = all[3] as ExtractedStream?;
            final vf = all[4] as ExtractedStream?;

            List<SubtitleTrack> bgSubs = [];
            if (vf != null && vf.subtitles.isNotEmpty) bgSubs = vf.subtitles;
            if (vl != null && vl.subtitles.isNotEmpty && bgSubs.isEmpty) bgSubs = vl.subtitles;

            final combined = <ExtractedStream>[];
            for (final t in tList) {
              combined.add(t.copyWith(subtitles: bgSubs.isNotEmpty ? bgSubs : t.subtitles));
            }
            for (final c in cList) {
              combined.add(c.copyWith(subtitles: bgSubs.isNotEmpty ? bgSubs : c.subtitles));
            }
            for (final v in vList) {
              combined.add(v.copyWith(subtitles: bgSubs.isNotEmpty ? bgSubs : v.subtitles));
            }
            if (combined.isNotEmpty) {
              setCachedEntry(key, combined);
            }
          } catch (_) {}
        }).ignore();

        return fastDirect;
      }

      final futures = await Future.wait([
        telegramFuture,
        cinejoyFuture,
        vidrockFuture,
        vidlinkFuture,
        voidflixFuture,
      ]);

      final telegramStreams = futures[0] as List<ExtractedStream>;
      final cinejoyStreams = futures[1] as List<ExtractedStream>;
      final vidrockStreams = futures[2] as List<ExtractedStream>;
      final vidlinkStream = futures[3] as ExtractedStream?;
      final voidflixStream = futures[4] as ExtractedStream?;

      if (voidflixStream != null && voidflixStream.subtitles.isNotEmpty) {
        sharedSubs = voidflixStream.subtitles;
      }
      if (vidlinkStream != null && vidlinkStream.subtitles.isNotEmpty && sharedSubs.isEmpty) {
        sharedSubs = vidlinkStream.subtitles;
      }

      // 1. Add Telegram streams first (Direct VPS MTProto, highest speed, uncompressed multi-audio)
      for (final t in telegramStreams) {
        results.add(ExtractedStream(
          url: t.url,
          type: t.type,
          sourceName: t.sourceName,
          language: t.language,
          headers: t.headers,
          qualityLabel: t.qualityLabel,
          qualities: t.qualities,
          subtitles: sharedSubs.isNotEmpty ? sharedSubs : t.subtitles,
        ));
      }

      // 2. Add Cinejoy 4K & 1080p streams (fastest, cleanest, high-res)
      for (final c in cinejoyStreams) {
        results.add(ExtractedStream(
          url: c.url,
          type: c.type,
          sourceName: c.sourceName,
          language: c.language,
          headers: c.headers,
          qualityLabel: c.qualityLabel,
          qualities: c.qualities,
          subtitles: sharedSubs.isNotEmpty ? sharedSubs : c.subtitles,
        ));
      }

      // 2. Add Vidrock streams (Orion, Nova, Atlas)
      for (final v in vidrockStreams) {
        results.add(ExtractedStream(
          url: v.url,
          type: v.type,
          sourceName: v.sourceName,
          language: v.language,
          headers: v.headers,
          qualityLabel: v.qualityLabel,
          qualities: v.qualities,
          subtitles: sharedSubs.isNotEmpty ? sharedSubs : v.subtitles,
        ));
      }

      // 3. Add Vidlink stream if present
      if (vidlinkStream != null) {
        results.add(vidlinkStream);
      }

      // 4. Add Voidflix backend stream if present
      if (voidflixStream != null) {
        results.add(voidflixStream);
      }
    } catch (e) {
      debugPrint('Parallel extraction error: $e');
    }

    if (results.isNotEmpty) {
      setCachedEntry(key, results);
    }

    return results;
  }

  /// Extracts high-speed direct streams and multi-language dubs from Aoneroom (MovieBox).
  static Future<List<ExtractedStream>> extractAoneroom({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    required String title,
    String? releaseDate,
    int season = 1,
    int episode = 1,
    String? preferredAudioLang,
    String? subjectIdOverride,
  }) async {
    final cacheKey = getCacheKey(type, tmdbId, season, episode, prefix: 'aoneroom');
    final cached = await getCachedEntry(cacheKey);
    if (cached != null && cached.streams.isNotEmpty) {
      debugPrint('StreamExtractor: Reusing cached Aoneroom streams for $cacheKey');
      return cached.streams;
    }

    try {
      // 1. Resolve Aoneroom subjectId
      final subjectId = subjectIdOverride ??
          await AoneroomMatcher.instance.resolveSubjectId(
            type: type,
            tmdbId: tmdbId,
            title: title,
            releaseDate: releaseDate,
          );

      if (subjectId == null || subjectId.isEmpty) {
        debugPrint('StreamExtractor: Aoneroom title match failed for "$title" (tmdb: $tmdbId)');
        return <ExtractedStream>[];
      }

      // 2. Fetch title detail (dubs & seasons metadata)
      final detail = await AoneroomClient.instance.getDetail(subjectId);
      if (detail == null) {
        debugPrint('StreamExtractor: Aoneroom getDetail returned null for $subjectId');
        return <ExtractedStream>[];
      }

      // If TV series, verify season availability if seasons list is provided
      if (type == 'tv' && detail.seasons.isNotEmpty) {
        final hasSeason = detail.seasons.any((s) => s.se == season);
        if (!hasSeason) {
          debugPrint('StreamExtractor: Aoneroom season $season not found in available seasons');
        }
      }

      // 3. Examine dubs and select user's preferred dub
      final dubs = detail.dubs.isNotEmpty
          ? detail.dubs
          : [
              AoneroomDub(
                subjectId: subjectId,
                lanName: 'Original',
                lanCode: 'en',
                original: true,
              )
            ];

      AoneroomDub chosenDub = dubs.firstWhere(
        (d) => d.original,
        orElse: () => dubs.first,
      );

      if (preferredAudioLang != null && preferredAudioLang.isNotEmpty) {
        final prefLower = preferredAudioLang.toLowerCase();
        final match = dubs.firstWhere(
          (d) =>
              d.lanCode.toLowerCase() == prefLower ||
              d.lanName.toLowerCase().contains(prefLower) ||
              prefLower.contains(d.lanCode.toLowerCase()),
          orElse: () => chosenDub,
        );
        chosenDub = match;
      }

      // 4. Fetch play stream for chosen dub
      final playResult = await AoneroomClient.instance.getPlay(
        chosenDub.subjectId,
        season: type == 'tv' ? season : null,
        episode: type == 'tv' ? episode : null,
      );

      if (playResult == null || !playResult.hasPlayableStreams || playResult.vipLocked) {
        debugPrint(
          'StreamExtractor: Aoneroom play returned no streams (vipLocked: ${playResult?.vipLocked}) for subjectId ${chosenDub.subjectId}',
        );
        return <ExtractedStream>[];
      }

      final primaryUrl = playResult.hlsUrls.isNotEmpty
          ? playResult.hlsUrls.first
          : (playResult.dashUrls.isNotEmpty
              ? playResult.dashUrls.first
              : (playResult.streams.isNotEmpty ? playResult.streams.first['url']?.toString() ?? '' : ''));

      if (primaryUrl.isEmpty) {
        return <ExtractedStream>[];
      }

      // Resolve HLS variants if master playlist
      List<StreamQuality> qualities = [];
      if (primaryUrl.contains('.m3u8')) {
        qualities = await _resolveHlsVariants(
          primaryUrl,
          AoneroomClient.instance.headers,
        );
      }

      if (qualities.isEmpty) {
        qualities = [
          StreamQuality(label: 'Auto (Adaptive)', height: 0, url: primaryUrl),
          StreamQuality(label: '720p HD', height: 720, url: primaryUrl),
          StreamQuality(label: '480p (Fast)', height: 480, url: primaryUrl),
        ];
      }

      final streamType = primaryUrl.contains('.m3u8')
          ? 'hls'
          : (primaryUrl.contains('.mpd') ? 'dash' : 'mp4');

      final results = <ExtractedStream>[];

      // Add primary active stream
      results.add(ExtractedStream(
        url: primaryUrl,
        type: streamType,
        sourceName: 'Aoneroom [${chosenDub.lanName}]',
        language: chosenDub.lanName,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'X-Client-Info': jsonEncode({'timezone': DateTime.now().timeZoneName}),
          'X-No-High-Risk-Restrict': '1',
          'x-aoneroom-subject-id': chosenDub.subjectId,
        },
        qualityLabel: 'Auto (Adaptive)',
        qualities: qualities,
        subtitles: const [],
      ));

      // Surface remaining dub variants for multi-audio selector
      for (final dub in dubs) {
        if (dub.subjectId == chosenDub.subjectId) continue;
        results.add(ExtractedStream(
          url: '', // Lazily resolved on tap via extractAoneroomPlayUrl
          type: 'hls',
          sourceName: 'Aoneroom [${dub.lanName}]',
          language: dub.lanName,
          headers: {
            'x-aoneroom-subject-id': dub.subjectId,
            'x-aoneroom-lang': dub.lanName,
          },
          qualityLabel: 'HD',
          qualities: const [],
          subtitles: const [],
        ));
      }

      if (results.isNotEmpty) {
        setCachedEntry(cacheKey, results);
      }
      return results;
    } catch (e, st) {
      debugPrint('StreamExtractor: Aoneroom extraction error: $e\n$st');
      return <ExtractedStream>[];
    }
  }

  /// Lazily fetches a playable stream for a specific Aoneroom dub when selected by the user.
  static Future<List<ExtractedStream>?> extractAoneroomPlayUrl({
    required String subjectId,
    required String language,
    int? season,
    int? episode,
  }) async {
    try {
      final playResult = await AoneroomClient.instance.getPlay(
        subjectId,
        season: season,
        episode: episode,
      );

      if (playResult == null || !playResult.hasPlayableStreams || playResult.vipLocked) {
        return null;
      }

      final primaryUrl = playResult.hlsUrls.isNotEmpty
          ? playResult.hlsUrls.first
          : (playResult.dashUrls.isNotEmpty
              ? playResult.dashUrls.first
              : (playResult.streams.isNotEmpty ? playResult.streams.first['url']?.toString() ?? '' : ''));

      if (primaryUrl.isEmpty) return null;

      List<StreamQuality> qualities = [];
      if (primaryUrl.contains('.m3u8')) {
        qualities = await _resolveHlsVariants(
          primaryUrl,
          AoneroomClient.instance.headers,
        );
      }

      if (qualities.isEmpty) {
        qualities = [
          StreamQuality(label: 'Auto (Adaptive)', height: 0, url: primaryUrl),
          StreamQuality(label: '720p HD', height: 720, url: primaryUrl),
          StreamQuality(label: '480p (Fast)', height: 480, url: primaryUrl),
        ];
      }

      return [
        ExtractedStream(
          url: primaryUrl,
          type: primaryUrl.contains('.m3u8')
              ? 'hls'
              : (primaryUrl.contains('.mpd') ? 'dash' : 'mp4'),
          sourceName: 'Aoneroom [$language]',
          language: language,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'X-Client-Info': jsonEncode({'timezone': DateTime.now().timeZoneName}),
            'X-No-High-Risk-Restrict': '1',
            'x-aoneroom-subject-id': subjectId,
          },
          qualityLabel: 'Auto (Adaptive)',
          qualities: qualities,
          subtitles: const [],
        ),
      ];
    } catch (e) {
      debugPrint('StreamExtractor: extractAoneroomPlayUrl error: $e');
      return null;
    }
  }
}
