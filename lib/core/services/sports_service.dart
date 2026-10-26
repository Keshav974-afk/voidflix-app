import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/sports_match.dart';

class SportsService {
  static final SportsService _instance = SportsService._internal();
  factory SportsService() => _instance;
  SportsService._internal();

  static const String _apiBase = 'https://voidflix.org/api/public/sports';
  static const String _hygraphEndpoint =
      'https://eu-west-2.cdn.hygraph.com/content/cmltehh69001707w2jnvzol56/master';

  final Map<String, List<SportsMatch>> _cache = {};
  final Map<String, DateTime> _cacheTime = {};

  /// Fetches live matches for a given sport category (cricket, football, basketball)
  Future<List<SportsMatch>> fetchMatches({String category = 'cricket', bool forceRefresh = false}) async {
    final catKey = category.toLowerCase();
    final cached = _cache[catKey];
    final time = _cacheTime[catKey];

    if (!forceRefresh && cached != null && time != null) {
      if (DateTime.now().difference(time) < const Duration(seconds: 50)) {
        return cached;
      }
    }

    // 1. Query Central Voidflix Edge API
    try {
      final res = await http.get(
        Uri.parse('$_apiBase?category=$catKey'),
        headers: {
          'User-Agent': 'Voidflix-App/0.3.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawMatches = data['matches'] as List<dynamic>? ?? [];
        final list = rawMatches
            .whereType<Map<String, dynamic>>()
            .map((m) => SportsMatch.fromJson(m))
            .toList();

        if (list.isNotEmpty) {
          _cache[catKey] = list;
          _cacheTime[catKey] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('SportsService: Central API fetch error: $e. Falling back to direct query...');
    }

    // 2. Direct Fallback if Central API is unreachable (e.g. offline dev or cold cache)
    if (catKey == 'cricket') {
      return await _fetchCricketDirectFallback();
    }

    return _cache[catKey] ?? [];
  }

  /// Direct client-side Hygraph query fallback
  Future<List<SportsMatch>> _fetchCricketDirectFallback() async {
    const query = '''
query GetLiveCricket {
  crickets(first: 30, orderBy: updatedAt_DESC) {
    id
    title
    homeTeam
    awayTeam
    slug
    startDateTime
    duration
    cricketCategory
    thumbnailUrl
    homeTeamLogoUrl
    awayTeamLogoUrl
    liveUrl1
    liveUrl2
    liveUrl3
    liveUrl4
    liveUrl5
    liveUrl6
    liveUrl7
  }
}
''';

    const blacklist = [
      'asiafilm.org',
      'tinyurl.com',
      'diskbecausesmell.com',
      'czernik.org',
      'capitalhospitals.org',
      'quge5.com',
      'maxdigitaltv.com',
      'sphub-cors-proxy',
      'safpar001.workers',
      'privateemail123466.workers',
      'playnp?id=',
      'playbd?id=',
      'playin?id=',
      'playlk?id=',
    ];

    try {
      final res = await http.post(
        Uri.parse(_hygraphEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawList = data['data']?['crickets'] as List<dynamic>? ?? [];

        final now = DateTime.now();
        final matches = <SportsMatch>[];

        for (final c in rawList) {
          if (c is! Map<String, dynamic>) continue;
          final start = DateTime.tryParse(c['startDateTime']?.toString() ?? '') ?? now;
          final duration = (c['duration'] as num?)?.toInt() ?? 240;
          final end = start.add(Duration(minutes: duration));

          // 1. Filter out old matches that have already completed
          if (now.isAfter(end.add(const Duration(minutes: 30)))) {
            continue;
          }

          // 2. Filter out matches scheduled too far into the future (keep next 4 days)
          if (start.difference(now).inDays > 4) {
            continue;
          }

          final isLive = now.isAfter(start) && now.isBefore(end);

          final streams = <SportsStream>[];
          for (int i = 1; i <= 7; i++) {
            final raw = c['liveUrl$i']?.toString().trim() ?? '';
            if (raw.isEmpty) continue;
            if (blacklist.any((b) => raw.toLowerCase().contains(b))) continue;

            // A. ClearKey DASH
            if (raw.contains('dash/mpd') || raw.contains('cenc.mpd')) {
              final mManifest = RegExp(r'manifest=([^&]+)').firstMatch(raw);
              final mKid = RegExp(r'keyid=([^&]+)').firstMatch(raw);
              final mKey = RegExp(r'key=([^&]+)').firstMatch(raw);
              if (mManifest != null && mKid != null && mKey != null) {
                final mpd = Uri.decodeComponent(mManifest.group(1)!);
                streams.add(SportsStream(
                  id: 'dash_$i',
                  type: 'dash',
                  label: 'ClearKey DASH (1080p)',
                  url: raw, // keep embed wrapper so WebView executes Shaka Player rather than downloading raw .mpd!
                  manifest: mpd,
                  keyId: mKid.group(1),
                  key: mKey.group(1),
                  isDirect: false, // In app, launch via in-app WebView
                ));
                continue;
              }
            }

            // B. Pro Tokenized HLS (c/love -> wideiptv -> bluetier)
            if (raw.contains('c/love') || raw.contains('ch=')) {
              final mCh = RegExp(r'ch=([a-zA-Z0-9_\-]+)').firstMatch(raw);
              if (mCh != null) {
                final channel = mCh.group(1)!;
                final token = await _fetchWideIptvToken(channel);
                if (token != null) {
                  streams.add(SportsStream(
                    id: 'clove_${channel}_$i',
                    type: 'hls',
                    label: '$channel (1080p HD Pro)',
                    url: 'https://ds169.bluetier.top/$channel/index.m3u8?token=$token',
                    isDirect: true,
                    headers: const {'Referer': 'https://tv.sphublive.com/'},
                  ));
                  continue;
                }
              }
            }

            // C. Direct HLS
            if (raw.contains('.m3u8')) {
              var clean = raw;
              if (raw.contains('url=')) {
                final enc = raw.split('url=')[1].split('&')[0];
                clean = Uri.decodeComponent(enc);
              }
              streams.add(SportsStream(
                id: 'hls_$i',
                type: 'hls',
                label: 'Server $i (Direct HLS)',
                url: clean,
                isDirect: true,
                headers: const {'Referer': 'https://tv.sphublive.com/'},
              ));
              continue;
            }

            // D. Fallback Mirror
            streams.add(SportsStream(
              id: 'embed_$i',
              type: 'embed',
              label: 'Mirror $i',
              url: raw,
              isDirect: false,
            ));
          }

          matches.add(SportsMatch(
            id: c['id']?.toString() ?? '',
            slug: c['slug']?.toString() ?? '',
            title: c['title']?.toString() ?? 'Cricket Match',
            sport: 'Cricket',
            category: c['cricketCategory']?.toString() ?? 'Tournament',
            homeTeam: c['homeTeam']?.toString() ?? '',
            awayTeam: c['awayTeam']?.toString() ?? '',
            homeTeamLogo: c['homeTeamLogoUrl']?.toString() ?? '',
            awayTeamLogo: c['awayTeamLogoUrl']?.toString() ?? '',
            thumbnail: c['thumbnailUrl']?.toString() ?? '',
            startDateTime: start,
            durationMinutes: duration,
            isLive: isLive,
            streams: streams,
          ));
        }

        _cache['cricket'] = matches;
        _cacheTime['cricket'] = now;
        return matches;
      }
    } catch (e) {
      debugPrint('SportsService direct fallback error: $e');
    }

    return [];
  }

  /// Fetches a dynamic 300s token from wideiptv.top
  Future<String?> _fetchWideIptvToken(String channel) async {
    try {
      final res = await http.post(
        Uri.parse('https://wideiptv.top/api/refresh_token.php'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://tv.sphublive.com/',
        },
        body: jsonEncode({'channel': channel, 'current_token': null}),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if (json['success'] == true && json['token'] != null) {
          return json['token'].toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
