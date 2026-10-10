import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'subtitle_service.dart';

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

  /// Sets cached streams in both in-memory map and asynchronous SharedPreferences.
  static void setCachedEntry(String key, List<ExtractedStream> streams) {
    if (streams.isEmpty) return;
    final entry = CachedStreamEntry(streams);
    _cache[key] = entry;

    SharedPreferences.getInstance().then((prefs) => prefs.setString('cached_stream_$key', jsonEncode(entry.toJson()))).catchError((_) => false);
  }

  static void invalidateCache(String type, int tmdbId, int season, int episode) {
    final keys = [
      getCacheKey(type, tmdbId, season, episode),
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
    var b64 = enc.replaceAll('-', '+').replaceAll('_', '/');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    final data = base64Decode(b64);
    final iv = data.sublist(0, 12);
    final ciphertextWithTag = data.sublist(12);
    final ciphertext =
        ciphertextWithTag.sublist(0, ciphertextWithTag.length - 16);
    final mac = Mac(ciphertextWithTag.sublist(ciphertextWithTag.length - 16));

    final secretBox = SecretBox(ciphertext, nonce: iv, mac: mac);
    final clearBytes =
        await _aesGcm.decrypt(secretBox, secretKey: _secretKey);
    return utf8.decode(clearBytes);
  }

  /// Extracts direct HLS stream URLs from Vidrock (Nova, Atlas, Orion, Astra, Luna)
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

      // Preferred priority order of sources
      final order = ['Nova', 'Atlas', 'Orion', 'Astra', 'Luna'];
      for (final name in order) {
        final src = json[name] as Map<String, dynamic>?;
        if (src != null && src['url'] != null) {
          final enc = src['url'] as String;
          try {
            final streamUrl = await _decryptVidrockUrl(enc);
            if (streamUrl.isNotEmpty && streamUrl.startsWith('http')) {
              final lang = (src['language'] as String?) ?? 'English';
              results.add(ExtractedStream(
                url: streamUrl,
                type: (src['type'] as String?) ?? 'hls',
                sourceName: name,
                language: lang,
                headers: {
                  'Referer': 'https://vidrock.ru/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
                qualityLabel: 'Auto (HLS)',
                qualities: [
                  StreamQuality(label: 'Auto (HLS)', height: 0, url: streamUrl),
                  StreamQuality(label: '1080p', height: 1080, url: streamUrl),
                  StreamQuality(label: '720p', height: 720, url: streamUrl),
                  StreamQuality(label: '480p', height: 480, url: streamUrl),
                ],
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
      final data = jsonDecode(res.body) as Map<String, dynamic>;
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

  /// Master extraction method that queries all direct stream extractors
  /// and aggregates audio sources, qualities, and all subtitle tracks.
  /// Automatically uses cached results within 3 hours for instant resumption.
  static Future<List<ExtractedStream>> extractAll({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
    bool forceRefresh = false,
  }) async {
    final key = getCacheKey(type, tmdbId, season, episode);

    if (!forceRefresh) {
      final cached = await getCachedEntry(key);
      if (cached != null && cached.streams.isNotEmpty) {
        debugPrint('StreamExtractor: Reusing cached aggregated streams for $key (instant!)');
        return cached.streams;
      }
    }

    final results = <ExtractedStream>[];
    List<SubtitleTrack> sharedSubs = [];

    // Parallel concurrent extraction across all direct sources
    try {
      final futures = await Future.wait([
        extractVoidflixBackend(
          type: type,
          tmdbId: tmdbId,
          season: season,
          episode: episode,
        ).catchError((e) {
          debugPrint('Voidflix extractor error: $e');
          return null;
        }),
        extractVidlink(
          type: type,
          tmdbId: tmdbId,
          season: season,
          episode: episode,
        ).catchError((e) {
          debugPrint('Vidlink extractor error: $e');
          return null;
        }),
        extractVidrock(
          type: type,
          tmdbId: tmdbId,
          season: season,
          episode: episode,
        ).catchError((e) {
          debugPrint('Vidrock extractor error: $e');
          return <ExtractedStream>[];
        }),
      ]);

      final voidflixStream = futures[0] as ExtractedStream?;
      final vidlinkStream = futures[1] as ExtractedStream?;
      final vidrockStreams = futures[2] as List<ExtractedStream>;

      if (voidflixStream != null) {
        results.add(voidflixStream);
        if (voidflixStream.subtitles.isNotEmpty) {
          sharedSubs = voidflixStream.subtitles;
        }
      }

      if (vidlinkStream != null) {
        results.add(vidlinkStream);
        if (vidlinkStream.subtitles.isNotEmpty && sharedSubs.isEmpty) {
          sharedSubs = vidlinkStream.subtitles;
        }
      }

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
    } catch (e) {
      debugPrint('Parallel extraction error: $e');
    }

    if (results.isNotEmpty) {
      setCachedEntry(key, results);
    }

    return results;
  }
}
