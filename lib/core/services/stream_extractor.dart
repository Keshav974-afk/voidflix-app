import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  @override
  String toString() => 'ExtractedStream($sourceName: $url, lang: $language)';
}

class StreamExtractor {
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
      return results;
    } catch (e) {
      debugPrint('Vidrock extraction error: $e');
      return [];
    }
  }

  /// Extracts direct stream and all multilingual subtitles & MP4 qualities via Vidlink
  static Future<ExtractedStream?> extractVidlink({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      // 1. Get encrypted TMDB ID from helper endpoint
      final encRes = await http.get(
        Uri.parse('https://enc-dec.app/api/enc-vidlink?text=$tmdbId'),
      ).timeout(const Duration(seconds: 6));

      if (encRes.statusCode != 200) return null;
      final encJson = jsonDecode(encRes.body) as Map<String, dynamic>;
      final encId = encJson['result'] as String?;
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
      final qualitiesMap = streamObj['qualities'] as Map<String, dynamic>?;
      String? primaryUrl;

      if (qualitiesMap != null && qualitiesMap.isNotEmpty) {
        final sortedKeys = qualitiesMap.keys.toList()
          ..sort((a, b) => (int.tryParse(b) ?? 0).compareTo(int.tryParse(a) ?? 0));

        for (final qKey in sortedKeys) {
          final qObj = qualitiesMap[qKey];
          if (qObj is Map<String, dynamic> && qObj['url'] != null) {
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
        return ExtractedStream(
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
      }

      return null;
    } catch (e) {
      debugPrint('Vidlink extraction error: $e');
      return null;
    }
  }

  /// Master extraction method that queries all direct stream extractors
  /// and aggregates audio sources, qualities, and all subtitle tracks.
  static Future<List<ExtractedStream>> extractAll({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final results = <ExtractedStream>[];
    List<SubtitleTrack> sharedSubs = [];

    // 1. Vidlink (High quality with complete multilingual subtitles)
    try {
      final vidlinkStream = await extractVidlink(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );
      if (vidlinkStream != null) {
        results.add(vidlinkStream);
        if (vidlinkStream.subtitles.isNotEmpty) {
          sharedSubs = vidlinkStream.subtitles;
        }
      }
    } catch (e) {
      debugPrint('Vidlink extractor error: $e');
    }

    // 2. Vidrock (VVID engine: Nova, Atlas, Orion - Ultra-fast CDN HLS)
    try {
      final vidrockStreams = await extractVidrock(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );

      // Attach the subtitle tracks to the Vidrock streams as well
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
      debugPrint('Vidrock extractor error: $e');
    }

    return results;
  }
}
