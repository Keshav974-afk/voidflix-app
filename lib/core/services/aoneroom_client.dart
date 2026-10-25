import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for the Aoneroom / MovieBox streaming provider.
class AoneroomConfig {
  static const String defaultBaseUrl = 'https://h5-api.aoneroom.com/wefeed-h5api-bff';
  static const Duration defaultTimeout = Duration(seconds: 7);
  static const String defaultServerName = 'Aoneroom (MovieBox)';

  final String baseUrl;
  final bool enabled;
  final String serverName;
  final Duration timeout;
  final List<String> preferredDubLanguages;
  final String? token;
  final bool showWhenConfidenceLow;

  const AoneroomConfig({
    this.baseUrl = defaultBaseUrl,
    this.enabled = true,
    this.serverName = defaultServerName,
    this.timeout = defaultTimeout,
    this.preferredDubLanguages = const ['en', 'hi', 'es', 'fr', 'de'],
    this.token,
    this.showWhenConfidenceLow = false,
  });

  AoneroomConfig copyWith({
    String? baseUrl,
    bool? enabled,
    String? serverName,
    Duration? timeout,
    List<String>? preferredDubLanguages,
    String? token,
    bool? showWhenConfidenceLow,
  }) {
    return AoneroomConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      serverName: serverName ?? this.serverName,
      timeout: timeout ?? this.timeout,
      preferredDubLanguages: preferredDubLanguages ?? this.preferredDubLanguages,
      token: token ?? this.token,
      showWhenConfidenceLow: showWhenConfidenceLow ?? this.showWhenConfidenceLow,
    );
  }

  static Future<AoneroomConfig> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('aoneroom_base_url') ?? defaultBaseUrl;
      final enabled = prefs.getBool('aoneroom_enabled') ?? true;
      final serverName = prefs.getString('aoneroom_server_name') ?? defaultServerName;
      final token = prefs.getString('aoneroom_auth_token');
      final timeoutMs = prefs.getInt('aoneroom_timeout_ms') ?? 7000;
      final showLow = prefs.getBool('aoneroom_show_low_confidence') ?? false;

      return AoneroomConfig(
        baseUrl: baseUrl,
        enabled: enabled,
        serverName: serverName,
        timeout: Duration(milliseconds: timeoutMs),
        token: (token != null && token.isNotEmpty) ? token : null,
        showWhenConfidenceLow: showLow,
      );
    } catch (e) {
      debugPrint('AoneroomConfig: error loading preferences: $e');
      return const AoneroomConfig();
    }
  }

  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('aoneroom_base_url', baseUrl);
      await prefs.setBool('aoneroom_enabled', enabled);
      await prefs.setString('aoneroom_server_name', serverName);
      await prefs.setInt('aoneroom_timeout_ms', timeout.inMilliseconds);
      if (token != null && token!.isNotEmpty) {
        await prefs.setString('aoneroom_auth_token', token!);
      } else {
        await prefs.remove('aoneroom_auth_token');
      }
      await prefs.setBool('aoneroom_show_low_confidence', showWhenConfidenceLow);
    } catch (e) {
      debugPrint('AoneroomConfig: error saving preferences: $e');
    }
  }
}

/// Represents a language variant / dub in Aoneroom.
/// type 0 = dub / audio variant; type 1 = subtitle-oriented variant.
class AoneroomDub {
  final String subjectId;
  final String lanName;
  final String lanCode;
  final bool original;
  final int type;

  const AoneroomDub({
    required this.subjectId,
    required this.lanName,
    required this.lanCode,
    this.original = false,
    this.type = 0,
  });

  factory AoneroomDub.fromJson(Map<String, dynamic> json) {
    return AoneroomDub(
      subjectId: json['subjectId']?.toString() ?? '',
      lanName: json['lanName']?.toString() ?? 'English',
      lanCode: json['lanCode']?.toString() ?? 'en',
      original: json['original'] == true || json['original'] == 1,
      type: (json['type'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'lanName': lanName,
        'lanCode': lanCode,
        'original': original,
        'type': type,
      };

  @override
  String toString() => 'AoneroomDub($lanName [$lanCode]: $subjectId, original=$original, type=$type)';
}

/// Season and episode availability in Aoneroom.
class AoneroomSeason {
  final int se;
  final int maxEp;
  final List<String> resolutions;

  const AoneroomSeason({
    required this.se,
    required this.maxEp,
    this.resolutions = const [],
  });

  factory AoneroomSeason.fromJson(Map<String, dynamic> json) {
    final resList = <String>[];
    if (json['resolutions'] is List) {
      for (final r in json['resolutions']) {
        if (r is Map && r['resolution'] != null) {
          resList.add(r['resolution'].toString());
        }
      }
    }
    return AoneroomSeason(
      se: (json['se'] as num?)?.toInt() ?? 1,
      maxEp: (json['maxEp'] as num?)?.toInt() ?? 1,
      resolutions: resList,
    );
  }
}

/// Detail response from /detail?subjectId={id}
class AoneroomDetail {
  final String subjectId;
  final String title;
  final String description;
  final String cover;
  final String releaseDate;
  final double imdbRating;
  final List<AoneroomDub> dubs;
  final List<AoneroomSeason> seasons;

  const AoneroomDetail({
    required this.subjectId,
    required this.title,
    this.description = '',
    this.cover = '',
    this.releaseDate = '',
    this.imdbRating = 0.0,
    this.dubs = const [],
    this.seasons = const [],
  });

  factory AoneroomDetail.fromJson(Map<String, dynamic> json) {
    final subject = json['subject'] as Map<String, dynamic>? ?? json;
    final resource = json['resource'] as Map<String, dynamic>? ?? {};

    final dubsList = <AoneroomDub>[];
    if (subject['dubs'] is List) {
      for (final d in subject['dubs']) {
        if (d is Map<String, dynamic>) {
          dubsList.add(AoneroomDub.fromJson(d));
        }
      }
    }

    final seasonsList = <AoneroomSeason>[];
    if (resource['seasons'] is List) {
      for (final s in resource['seasons']) {
        if (s is Map<String, dynamic>) {
          seasonsList.add(AoneroomSeason.fromJson(s));
        }
      }
    }

    return AoneroomDetail(
      subjectId: subject['subjectId']?.toString() ?? '',
      title: subject['title']?.toString() ?? '',
      description: subject['description']?.toString() ?? '',
      cover: subject['cover']?.toString() ?? '',
      releaseDate: subject['releaseDate']?.toString() ?? '',
      imdbRating: (subject['imdbRatingValue'] as num?)?.toDouble() ?? 0.0,
      dubs: dubsList,
      seasons: seasonsList,
    );
  }
}

/// Playback stream object from /subject/play?subjectId={id}
class AoneroomPlayResult {
  final List<String> hlsUrls;
  final List<String> dashUrls;
  final List<Map<String, dynamic>> streams;
  final bool hasResource;
  final bool vipLocked;
  final int maxResolution;
  final List<String> codecPriority;

  const AoneroomPlayResult({
    this.hlsUrls = const [],
    this.dashUrls = const [],
    this.streams = const [],
    this.hasResource = false,
    this.vipLocked = false,
    this.maxResolution = 480,
    this.codecPriority = const ['hevc', 'h264'],
  });

  bool get hasPlayableStreams => hlsUrls.isNotEmpty || dashUrls.isNotEmpty || streams.isNotEmpty;

  factory AoneroomPlayResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;

    final hlsList = <String>[];
    if (data['hls'] is List) {
      for (final item in data['hls']) {
        if (item is String && item.isNotEmpty) {
          hlsList.add(item);
        } else if (item is Map && item['url'] != null) {
          hlsList.add(item['url'].toString());
        }
      }
    }

    final dashList = <String>[];
    if (data['dash'] is List) {
      for (final item in data['dash']) {
        if (item is String && item.isNotEmpty) {
          dashList.add(item);
        } else if (item is Map && item['url'] != null) {
          dashList.add(item['url'].toString());
        }
      }
    }

    final streamList = <Map<String, dynamic>>[];
    if (data['streams'] is List) {
      for (final s in data['streams']) {
        if (s is Map<String, dynamic>) {
          streamList.add(s);
        }
      }
    }

    final playConfig = data['playConfig'] as Map<String, dynamic>? ?? {};

    return AoneroomPlayResult(
      hlsUrls: hlsList,
      dashUrls: dashList,
      streams: streamList,
      hasResource: data['hasResource'] == true,
      vipLocked: data['vipLocked'] == true,
      maxResolution: (playConfig['maxResolution'] as num?)?.toInt() ?? 480,
      codecPriority: (data['codecPriority'] as List<dynamic>?)
              ?.map((c) => c.toString())
              .toList() ??
          const ['hevc', 'h264'],
    );
  }
}

/// HTTP Client for interacting with Aoneroom (MovieBox) API.
class AoneroomClient {
  static final AoneroomClient instance = AoneroomClient._internal();
  AoneroomClient._internal();

  AoneroomConfig config = const AoneroomConfig();
  final http.Client _httpClient = http.Client();

  // In-memory 24-hour cache for /detail responses to eliminate duplicate network calls
  final Map<String, AoneroomDetail> _detailCache = {};

  /// Build standard headers expected by the Aoneroom BFF API.
  Map<String, String> get headers {
    final headerMap = {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'X-Client-Info': jsonEncode({'timezone': DateTime.now().timeZoneName}),
      'X-No-High-Risk-Restrict': '1',
    };

    if (config.token != null && config.token!.isNotEmpty) {
      headerMap['token'] = config.token!;
      headerMap['Authorization'] = 'Bearer ${config.token}';
    }

    return headerMap;
  }

  /// Initialize config from preferences
  Future<void> init() async {
    config = await AoneroomConfig.loadFromPreferences();
  }

  /// GET /country-code
  Future<String?> getCountryCode() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/country-code');
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['data']?['countryCode']?.toString();
      }
    } catch (e) {
      debugPrint('AoneroomClient: getCountryCode error: $e');
    }
    return null;
  }

  /// GET /subject/trending
  Future<List<Map<String, dynamic>>> getTrendingSubjects() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/subject/trending');
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['data']?['subjectList'] as List<dynamic>?;
        if (list != null) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('AoneroomClient: getTrendingSubjects error: $e');
    }
    return const [];
  }

  /// GET /subject/recommend
  Future<List<Map<String, dynamic>>> getRecommendSubjects() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/subject/recommend');
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['data']?['movieItems'] as List<dynamic>?;
        if (list != null) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('AoneroomClient: getRecommendSubjects error: $e');
    }
    return const [];
  }

  /// GET /home (Extracts subjects across all categories)
  Future<List<Map<String, dynamic>>> getHomeSubjects() async {
    try {
      final uri = Uri.parse('${config.baseUrl}/home');
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final ops = body['data']?['operatingList'] as List<dynamic>?;
        if (ops != null) {
          final allSubjects = <Map<String, dynamic>>[];
          final seenIds = <String>{};
          for (final op in ops) {
            if (op is Map<String, dynamic> && op['subjects'] is List) {
              for (final s in op['subjects']) {
                if (s is Map<String, dynamic>) {
                  final id = s['subjectId']?.toString() ?? '';
                  if (id.isNotEmpty && !seenIds.contains(id)) {
                    seenIds.add(id);
                    allSubjects.add(s);
                  }
                }
              }
            }
          }
          return allSubjects;
        }
      }
    } catch (e) {
      debugPrint('AoneroomClient: getHomeSubjects error: $e');
    }
    return const [];
  }

  /// GET /detail?subjectId={id}
  Future<AoneroomDetail?> getDetail(String subjectId) async {
    if (subjectId.isEmpty) return null;

    if (_detailCache.containsKey(subjectId)) {
      return _detailCache[subjectId];
    }

    try {
      final uri = Uri.parse('${config.baseUrl}/detail?subjectId=$subjectId');
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          final detail = AoneroomDetail.fromJson(data);
          _detailCache[subjectId] = detail;
          return detail;
        }
      }
    } catch (e) {
      debugPrint('AoneroomClient: getDetail error for $subjectId: $e');
    }
    return null;
  }

  /// GET /subject/play?subjectId={id}&se={n}&ep={n}
  Future<AoneroomPlayResult?> getPlay(
    String subjectId, {
    int? season,
    int? episode,
  }) async {
    if (subjectId.isEmpty) return null;

    try {
      final queryParams = <String, String>{
        'subjectId': subjectId,
      };
      if (season != null && episode != null) {
        queryParams['se'] = season.toString();
        queryParams['ep'] = episode.toString();
      }

      final uri = Uri.parse('${config.baseUrl}/subject/play').replace(queryParameters: queryParams);
      final res = await _httpClient.get(uri, headers: headers).timeout(config.timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          return AoneroomPlayResult.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('AoneroomClient: getPlay error for $subjectId: $e');
    }
    return null;
  }
}
