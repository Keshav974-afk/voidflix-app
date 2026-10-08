import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ExtractedStream {
  final String url;
  final String type; // 'hls' or 'mp4'
  final String sourceName; // 'Nova', 'Atlas', 'Orion', etc.
  final Map<String, String> headers;
  final String? qualityLabel;

  const ExtractedStream({
    required this.url,
    required this.type,
    required this.sourceName,
    required this.headers,
    this.qualityLabel,
  });

  @override
  String toString() => 'ExtractedStream($sourceName: $url)';
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

  /// Extracts direct stream URLs from Vidrock (Nova, Atlas, Orion, Astra, Luna)
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
              results.add(ExtractedStream(
                url: streamUrl,
                type: (src['type'] as String?) ?? 'hls',
                sourceName: name,
                headers: {
                  'Referer': 'https://vidrock.ru/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
                qualityLabel: 'Auto (HLS)',
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

  /// Master extraction method that queries all direct stream extractors
  static Future<List<ExtractedStream>> extractAll({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    int season = 1,
    int episode = 1,
  }) async {
    final results = <ExtractedStream>[];

    // 1. Vidrock (VVID extractor engine - Ultra fast multi-CDN HLS)
    try {
      final vidrockStreams = await extractVidrock(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );
      results.addAll(vidrockStreams);
    } catch (e) {
      debugPrint('Extractor error: $e');
    }

    return results;
  }
}
