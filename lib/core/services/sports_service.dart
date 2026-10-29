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
          'User-Agent': 'Voidflix-App/0.4.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

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
      // Fetch disabled stream rules from Voidflix Central Admin Config to ensure offline fallback respects admin stream disabling
      final disabledRules = <String>{};
      try {
        final cfgRes = await http.get(
          Uri.parse('https://voidflix.org/api/public/config'),
          headers: {'User-Agent': 'Voidflix-App/0.4.0'},
        ).timeout(const Duration(seconds: 5));
        if (cfgRes.statusCode == 200) {
          final cfg = jsonDecode(cfgRes.body) as Map<String, dynamic>;
          final sportsControls = cfg['sportsControls'] as Map<String, dynamic>?;
          final disabledMap = sportsControls?['disabledMatchStreams'] as Map<String, dynamic>?;
          if (disabledMap != null) {
            for (final list in disabledMap.values) {
              if (list is List) {
                for (final item in list) {
                  disabledRules.add(item.toString().toLowerCase().trim());
                }
              }
            }
          }
        }
      } catch (_) {}

      // 1. Fetch dynamic live streams map from Cloudflare Pages (YashinTV / YonoTV feed)
      Map<String, dynamic> feedLinksMap = {};
      try {
        final feedRes = await http.get(
          Uri.parse('https://football-feed.pages.dev/links.json?t=${DateTime.now().millisecondsSinceEpoch}'),
          headers: {'User-Agent': 'Voidflix-App/0.4.0'},
        ).timeout(const Duration(seconds: 4));
        if (feedRes.statusCode == 200) {
          feedLinksMap = jsonDecode(feedRes.body) as Map<String, dynamic>;
        }
      } catch (_) {}

      // 2. Fetch Hygraph Cricket fixtures
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

        // Collect all active tournament DASH streams for Nepal Premier League (cross-pollination)
        final nplDashStreams = <SportsStream>[];
        final seenMpd = <String>{};

        for (final c in rawList) {
          if (c is! Map<String, dynamic>) continue;
          final isNpl = (c['title']?.toString() ?? '').toLowerCase().contains('nepal') ||
                        (c['cricketCategory']?.toString() ?? '').toLowerCase().contains('nepal');
          if (!isNpl) continue;
          for (int i = 1; i <= 7; i++) {
            final u = c['liveUrl$i']?.toString().trim() ?? '';
            if (u.contains('dash/mpd') || u.contains('cenc.mpd')) {
              final mManifest = RegExp(r'manifest=([^&]+)').firstMatch(u);
              final mKid = RegExp(r'keyid=([^&]+)').firstMatch(u);
              final mKey = RegExp(r'key=([^&]+)').firstMatch(u);
              if (mManifest != null && mKid != null && mKey != null) {
                final mpd = Uri.decodeComponent(mManifest.group(1)!);
                if (!seenMpd.contains(mpd)) {
                  seenMpd.add(mpd);
                  nplDashStreams.add(SportsStream(
                    id: 'dash_npl_${nplDashStreams.length + 1}',
                    type: 'dash',
                    label: 'Direct ClearKey DASH (${nplDashStreams.isEmpty ? "1080p Main" : "1080p Alt"})',
                    url: 'https://voidflix.org/dash-player.html?manifest=${Uri.encodeComponent(mpd)}&keyid=${mKid.group(1)}&key=${mKey.group(1)}&title=Nepal%20Premier%20League%20Live',
                    manifest: mpd,
                    keyId: mKid.group(1),
                    key: mKey.group(1),
                    isDirect: true,
                  ));
                }
              }
            }
          }
        }

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

          // A. Ingest verified live feeds from football-feed.pages.dev/links.json
          final matchSearchStr = '${c['title'] ?? ""} ${c['homeTeam'] ?? ""} ${c['awayTeam'] ?? ""} ${c['slug'] ?? ""}'.toLowerCase();
          Map<String, dynamic>? feedData;
          for (final entry in feedLinksMap.entries) {
            if (entry.key.length >= 3 && matchSearchStr.contains(entry.key.toLowerCase()) && entry.value is Map) {
              feedData = entry.value as Map<String, dynamic>;
              break;
            }
          }

          if (feedData != null) {
            for (int l = 1; l <= 7; l++) {
              final item = feedData['link$l'];
              if (item is! Map) continue;
              final u = item['url']?.toString().trim() ?? '';
              if (u.isEmpty || blacklist.any((b) => u.toLowerCase().contains(b))) continue;

              if (u.contains('.m3u8') || item['type'] == 'hls') {
                if (!streams.any((s) => s.url == u)) {
                  streams.add(SportsStream(
                    id: 'feed_hls_$l',
                    type: 'hls',
                    label: 'Direct HD Live HLS (${l == 1 ? "1080p Main" : "Server $l"})',
                    url: u,
                    isDirect: true,
                  ));
                }
              } else if (u.contains('yakotv.pages.dev') || u.contains('fcw') || u.contains('fxc')) {
                final cleanUrl = 'https://voidflix.org/dash-player.html?embed=${Uri.encodeComponent(u)}&title=${Uri.encodeComponent(c['title']?.toString() ?? "Live Cricket HD")}';
                if (!streams.any((s) => s.url == cleanUrl || s.url == u)) {
                  streams.add(SportsStream(
                    id: 'feed_fc_$l',
                    type: 'embed',
                    label: 'FanCode 1080p (Official Live Feed)',
                    url: cleanUrl,
                    isDirect: false,
                  ));
                }
              } else if (item['type'] == 'iframe' || item['type'] == 'redirect') {
                final cleanUrl = 'https://voidflix.org/dash-player.html?embed=${Uri.encodeComponent(u)}&title=${Uri.encodeComponent(c['title']?.toString() ?? "Live Cricket HD")}';
                if (!streams.any((s) => s.url == cleanUrl || s.url == u)) {
                  streams.add(SportsStream(
                    id: 'feed_embed_$l',
                    type: 'embed',
                    label: 'Live Server $l',
                    url: cleanUrl,
                    isDirect: false,
                  ));
                }
              }
            }
          }

          // B. Ingest Hygraph streams
          for (int i = 1; i <= 7; i++) {
            final raw = c['liveUrl$i']?.toString().trim() ?? '';
            if (raw.isEmpty) continue;
            if (blacklist.any((b) => raw.toLowerCase().contains(b))) continue;

            // ClearKey DASH
            if (raw.contains('dash/mpd') || raw.contains('cenc.mpd')) {
              final mManifest = RegExp(r'manifest=([^&]+)').firstMatch(raw);
              final mKid = RegExp(r'keyid=([^&]+)').firstMatch(raw);
              final mKey = RegExp(r'key=([^&]+)').firstMatch(raw);
              if (mManifest != null && mKid != null && mKey != null) {
                final mpd = Uri.decodeComponent(mManifest.group(1)!);
                final cleanUrl = 'https://voidflix.org/dash-player.html?manifest=${Uri.encodeComponent(mpd)}&keyid=${mKid.group(1)}&key=${mKey.group(1)}&title=${Uri.encodeComponent(c['title']?.toString() ?? "Voidflix Live HD")}';
                streams.add(SportsStream(
                  id: 'dash_$i',
                  type: 'dash',
                  label: 'Direct ClearKey DASH (1080p)',
                  url: cleanUrl,
                  manifest: mpd,
                  keyId: mKid.group(1),
                  key: mKey.group(1),
                  isDirect: true,
                ));
                continue;
              }
            }

            // Pro Tokenized HLS
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

            // Direct HLS (Clean extraction without parameter truncation)
            if (raw.contains('.m3u8')) {
              var clean = raw;
              if (raw.contains('url=')) {
                final parts = raw.split('url=');
                clean = Uri.decodeComponent(parts.last.split('&')[0]);
              }
              if (clean.endsWith('?hls')) {
                clean = clean.substring(0, clean.length - 4);
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

            // Fallback Mirror (routed through dash-player.html?embed=... for 0 popups)
            final embedClean = 'https://voidflix.org/dash-player.html?embed=${Uri.encodeComponent(raw)}&title=${Uri.encodeComponent(c['title']?.toString() ?? "Live Cricket HD")}';
            streams.add(SportsStream(
              id: 'embed_$i',
              type: 'embed',
              label: 'Mirror $i',
              url: embedClean,
              isDirect: false,
            ));
          }

          // C. Cross-pollinate tournament-level DASH for Nepal Premier League
          final isNplMatch = (c['title']?.toString() ?? '').toLowerCase().contains('nepal') ||
                             (c['cricketCategory']?.toString() ?? '').toLowerCase().contains('nepal');
          if (isNplMatch && nplDashStreams.isNotEmpty) {
            for (final ds in nplDashStreams.reversed) {
              if (!streams.any((s) => s.manifest == ds.manifest)) {
                streams.insert(0, ds);
              }
            }
          }

          // Filter out any disabled streams if admin marked them disabled in Admin Panel
          final filteredStreams = streams.where((s) {
            final sId = s.id.toLowerCase().trim();
            final sLabel = s.label.toLowerCase().trim();
            final sUrl = s.url.toLowerCase();
            final isDisabled = disabledRules.contains(sId) ||
                disabledRules.contains(sLabel) ||
                disabledRules.any((d) => d.length > 4 && (sUrl.contains(d) || sLabel.contains(d)));
            return !isDisabled;
          }).toList();

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
            streams: filteredStreams,
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
