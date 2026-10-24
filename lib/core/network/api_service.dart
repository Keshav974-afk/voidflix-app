import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../models/media_item.dart';
import '../../models/media_detail.dart';

class ApiService {
  final http.Client _client = http.Client();
  static bool _preferProxy = false;
  static const String _edgeProxyBase = 'https://voidflix.org/api/public/tmdb';

  static String getImageUrl(String? path, {String size = 'w500'}) {
    return ApiConstants.getImageUrl(path, size: size);
  }

  Future<List<MediaItem>> getTrending() => getTrendingAll();

  Future<dynamic> _get(String endpoint, [Map<String, String>? queryParams]) async {
    if (_preferProxy) {
      return _fetchFromProxy(endpoint, queryParams);
    }

    try {
      final params = {
        'api_key': ApiConstants.tmdbApiKey,
        ...?queryParams,
      };

      final uri = Uri.parse('${ApiConstants.tmdbBaseUrl}$endpoint').replace(queryParameters: params);
      final response = await _client.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('TMDB API Error: ${response.statusCode}');
      }
    } catch (_) {
      _preferProxy = true;
      return _fetchFromProxy(endpoint, queryParams);
    }
  }

  Future<dynamic> _fetchFromProxy(String endpoint, [Map<String, String>? queryParams]) async {
    try {
      final proxyParams = {
        'path': endpoint,
        ...?queryParams,
      };

      final uri = Uri.parse(_edgeProxyBase).replace(queryParameters: proxyParams);
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Proxy TMDB Error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load media: $e');
    }
  }

  Future<List<MediaItem>> getTrendingAll() async {
    final data = await _get('/trending/all/day');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<MediaItem>> getTrendingMovies() async {
    final data = await _get('/trending/movie/day');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getTrendingTV() async {
    final data = await _get('/trending/tv/day');
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> getPopularMovies({int page = 1}) async {
    final data = await _get('/movie/popular', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getTopRatedMovies({int page = 1}) async {
    final data = await _get('/movie/top_rated', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getPopularTV({int page = 1}) async {
    final data = await _get('/tv/popular', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> getTopRatedTV({int page = 1}) async {
    final data = await _get('/tv/top_rated', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> getUpcomingMovies({int page = 1}) async {
    final data = await _get('/movie/upcoming', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getAnime({int page = 1}) async {
    // Animation genre ID is 16, with origin country JP
    final data = await _get('/discover/tv', {
      'page': '$page',
      'with_genres': '16',
      'with_original_language': 'ja',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> getAsianDrama({int page = 1}) async {
    // Korean / Asian drama TV shows
    final data = await _get('/discover/tv', {
      'page': '$page',
      'with_original_language': 'ko',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> discoverByGenre(String type, int genreId, {int page = 1}) async {
    final data = await _get('/discover/$type', {
      'page': '$page',
      'with_genres': '$genreId',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: type)).toList();
  }

  Future<List<MediaItem>> getNowPlayingMovies({int page = 1}) async {
    final data = await _get('/movie/now_playing', {'page': '$page'});
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getActionMovies({int page = 1}) => discoverByGenre('movie', 28, page: page);
  Future<List<MediaItem>> getComedyMovies({int page = 1}) => discoverByGenre('movie', 35, page: page);
  Future<List<MediaItem>> getSciFiMovies({int page = 1}) => discoverByGenre('movie', 878, page: page);
  Future<List<MediaItem>> getHorrorMovies({int page = 1}) => discoverByGenre('movie', 27, page: page);
  Future<List<MediaItem>> getThrillerMovies({int page = 1}) => discoverByGenre('movie', 53, page: page);
  Future<List<MediaItem>> getRomanceMovies({int page = 1}) => discoverByGenre('movie', 10749, page: page);
  Future<List<MediaItem>> getCrimeTV({int page = 1}) => discoverByGenre('tv', 80, page: page);
  Future<List<MediaItem>> getDocumentaries({int page = 1}) => discoverByGenre('movie', 99, page: page);
  Future<List<MediaItem>> getFamilyMovies({int page = 1}) => discoverByGenre('movie', 10751, page: page);

  // Dedicated Kids Zone Endpoints (G and PG certified, no adult content)
  Future<List<MediaItem>> getKidsCartoons({int page = 1}) async {
    final data = await _get('/discover/tv', {
      'page': '$page',
      'with_genres': '16,10762',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'tv')).toList();
  }

  Future<List<MediaItem>> getKidsAnimatedMovies({int page = 1}) async {
    final data = await _get('/discover/movie', {
      'page': '$page',
      'with_genres': '16',
      'certification_country': 'US',
      'certification.lte': 'PG',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getKidsFamilyMovies({int page = 1}) async {
    final data = await _get('/discover/movie', {
      'page': '$page',
      'with_genres': '10751',
      'certification_country': 'US',
      'certification.lte': 'PG',
      'include_adult': 'false',
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: 'movie')).toList();
  }

  Future<List<MediaItem>> getRecommendations(String type, int id) async {
    try {
      final data = await _get('/$type/$id/recommendations');
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: type)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaItem>> discoverByLanguage(String type, String langCode, {int page = 1}) async {
    final data = await _get('/discover/$type', {
      'page': '$page',
      'with_original_language': langCode,
      'sort_by': 'popularity.desc',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: type)).toList();
  }

  Future<List<MediaItem>> discoverByGenreAndLanguage(String type, int genreId, {String? langCode, int page = 1}) async {
    final params = {
      'page': '$page',
      'with_genres': '$genreId',
      'sort_by': 'popularity.desc',
    };
    if (langCode != null && langCode.isNotEmpty) {
      params['with_original_language'] = langCode;
    }
    final data = await _get('/discover/$type', params);
    final results = data['results'] as List<dynamic>? ?? [];
    return results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: type)).toList();
  }

  Future<List<MediaItem>> searchPersonMedia(String personName) async {
    try {
      final data = await _get('/search/person', {
        'query': personName,
        'page': '1',
      });
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return [];
      final firstPerson = results.first as Map<String, dynamic>;
      final knownFor = firstPerson['known_for'] as List<dynamic>? ?? [];
      return knownFor
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .where((m) => m.posterPath != null)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPopularPeople({int page = 1}) async {
    try {
      final data = await _get('/person/popular', {'page': '$page'});
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchPeople(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    try {
      final data = await _get('/search/person', {
        'query': query,
        'page': '$page',
      });
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<MediaDetail> getDetails(String type, int id) async {
    final data = await _get('/$type/$id', {
      'append_to_response': 'credits,recommendations,videos,release_dates,content_ratings,images',
      'include_image_language': 'en,null',
    });
    return MediaDetail.fromJson(data as Map<String, dynamic>, type);
  }

  Future<List<TvEpisode>> getSeasonEpisodes(int id, int seasonNumber) async {
    final data = await _get('/tv/$id/season/$seasonNumber');
    final episodes = data['episodes'] as List<dynamic>? ?? [];
    return episodes.map((e) => TvEpisode.fromJson(e as Map<String, dynamic>)).toList();
  }

  static const Map<String, String> _languageMap = {
    'hindi': 'hi',
    'bollywood': 'hi',
    'nepali': 'ne',
    'tamil': 'ta',
    'kollywood': 'ta',
    'telugu': 'te',
    'tollywood': 'te',
    'punjabi': 'pa',
    'malayalam': 'ml',
    'korean': 'ko',
    'k-drama': 'ko',
    'kdrama': 'ko',
    'japanese': 'ja',
    'anime': 'ja',
    'english': 'en',
    'hollywood': 'en',
    'spanish': 'es',
    'french': 'fr',
    'chinese': 'zh',
  };

  static const Map<String, int> _genreMap = {
    'comedy': 35,
    'funny': 35,
    'hilarious': 35,
    'sad': 18,
    'emotional': 18,
    'drama': 18,
    'tearjerker': 18,
    'heartbreak': 18,
    'crying': 18,
    'horror': 27,
    'scary': 27,
    'spooky': 27,
    'ghost': 27,
    'action': 28,
    'fighting': 28,
    'fight': 28,
    'romance': 10749,
    'romantic': 10749,
    'love': 10749,
    'sci-fi': 878,
    'scifi': 878,
    'space': 878,
    'thriller': 53,
    'suspense': 53,
    'mystery': 9648,
    'animation': 16,
    'animated': 16,
    'cartoon': 16,
    'crime': 80,
    'gangster': 80,
    'mafia': 80,
    'adventure': 12,
    'fantasy': 14,
  };

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    final smart = await smartSearch(query, page: page);
    return smart.results;
  }

  Future<SmartSearchResult> smartSearch(String rawQuery, {int page = 1}) async {
    final q = rawQuery.trim();
    if (q.isEmpty) return const SmartSearchResult(results: []);

    // 1. Detect concatenated year: e.g. 'genius2018' -> 'genius 2018'
    String normalized = q;
    final concatMatch = RegExp(r'^([a-zA-Z\s]+?)(\d{4})$').firstMatch(normalized);
    if (concatMatch != null) {
      normalized = '${concatMatch.group(1)} ${concatMatch.group(2)}';
    }

    // 2. Extract 4-digit year (1900-2099)
    final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(normalized);
    final detectedYear = yearMatch?.group(1);

    String cleanTitle = normalized
        .replaceAll(RegExp(r'[\(\[\{]?(19\d\d|20\d\d)[\)\]\}]?'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // 3. Semantic Intent & Category Parsing (e.g. 'hindi movie', 'hindi comedy', 'nepali', 'sad movie')
    final lower = normalized.toLowerCase();
    final tokens = RegExp(r'\b[a-zA-Z\-]+\b').allMatches(lower).map((m) => m.group(0)!).toList();

    String? detectedLang;
    String? detectedLangName;
    final detectedGenres = <int>[];
    final detectedGenreNames = <String>[];
    String? detectedType;
    final consumedTokens = <String>{};

    for (final t in tokens) {
      if (t == 'movie' || t == 'movies' || t == 'film' || t == 'films' || t == 'cinema') {
        detectedType = 'movie';
        consumedTokens.add(t);
      } else if (t == 'series' || t == 'show' || t == 'shows' || t == 'tv' || t == 'drama' || t == 'dramas' || t == 'kdrama' || t == 'k-drama') {
        if (t == 'kdrama' || t == 'k-drama') {
          detectedLang = 'ko';
          detectedLangName = 'Korean';
        }
        detectedType = detectedType ?? 'tv';
        consumedTokens.add(t);
      } else if (_languageMap.containsKey(t)) {
        detectedLang = _languageMap[t];
        detectedLangName = t[0].toUpperCase() + t.substring(1);
        consumedTokens.add(t);
      } else if (_genreMap.containsKey(t)) {
        final gId = _genreMap[t]!;
        if (!detectedGenres.contains(gId)) {
          detectedGenres.add(gId);
          detectedGenreNames.add(t[0].toUpperCase() + t.substring(1));
        }
        consumedTokens.add(t);
      }
    }

    final remainderTokens = tokens.where((t) => !consumedTokens.contains(t)).toList();
    final isPureCategory = remainderTokens.isEmpty && (detectedLang != null || detectedGenres.isNotEmpty);
    String? categoryLabel;
    if (detectedLangName != null || detectedGenreNames.isNotEmpty) {
      final parts = <String>[];
      if (detectedLangName != null) parts.add(detectedLangName);
      if (detectedGenreNames.isNotEmpty) parts.add(detectedGenreNames.join(' & '));
      if (detectedType != null) parts.add(detectedType == 'tv' ? 'Shows' : 'Movies');
      categoryLabel = parts.join(' ');
    }

    final queryTerm = cleanTitle.isNotEmpty ? cleanTitle : q;
    final seenKeys = <String>{};
    final combinedResults = <MediaItem>[];

    void addItems(List<MediaItem> items) {
      for (final item in items) {
        final key = '${item.mediaType}_${item.id}';
        if (seenKeys.add(key)) {
          combinedResults.add(item);
        }
      }
    }

    Future<List<MediaItem>> fetchItems(String endpoint, Map<String, String> params) async {
      try {
        final data = await _get(endpoint, params);
        final list = data['results'] as List<dynamic>? ?? [];
        final defaultType = endpoint.contains('/tv') ? 'tv' : 'movie';
        return list
            .where((e) => e['media_type'] == 'movie' || e['media_type'] == 'tv' || !endpoint.contains('/multi'))
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: defaultType))
            .toList();
      } catch (_) {
        return [];
      }
    }

    // Branch A: Pure Category Search (e.g. 'hindi movie', 'hindi comedy', 'nepali', 'sad movie')
    if (isPureCategory) {
      final discoverParams = <String, String>{
        'sort_by': 'popularity.desc',
        'page': '$page',
      };
      if (detectedLang != null) discoverParams['with_original_language'] = detectedLang;
      if (detectedGenres.isNotEmpty) discoverParams['with_genres'] = detectedGenres.join(',');

      if (detectedType == 'tv') {
        final tvs = await fetchItems('/discover/tv', discoverParams);
        addItems(tvs);
      } else if (detectedType == 'movie') {
        final movies = await fetchItems('/discover/movie', discoverParams);
        addItems(movies);
      } else {
        final disco = await Future.wait([
          fetchItems('/discover/movie', discoverParams),
          fetchItems('/discover/tv', discoverParams),
        ]);
        addItems(disco[0]);
        addItems(disco[1]);
        combinedResults.sort((a, b) => b.popularity.compareTo(a.popularity));
      }

      return SmartSearchResult(
        results: combinedResults,
        originalQuery: q,
        detectedCategory: categoryLabel,
      );
    }

    // Branch B: Title / Specific Movie Search (with optional year and category boosting)
    if (detectedYear != null && cleanTitle.isNotEmpty) {
      final yearResults = await Future.wait([
        fetchItems('/search/movie', {
          'query': cleanTitle,
          'primary_release_year': detectedYear,
        }),
        fetchItems('/search/tv', {
          'query': cleanTitle,
          'first_air_date_year': detectedYear,
        }),
      ]);
      addItems(yearResults[0]);
      addItems(yearResults[1]);
    }

    // Multi-search on clean title (fetch page 1 and page 2 for high recall)
    final multiResults = await Future.wait([
      fetchItems('/search/multi', {'query': queryTerm, 'page': '$page'}),
      if (page == 1) fetchItems('/search/multi', {'query': queryTerm, 'page': '2'}),
    ]);
    for (final list in multiResults) {
      addItems(list);
    }

    // If year was specified, sort exact year match to the top
    if (detectedYear != null && combinedResults.isNotEmpty) {
      combinedResults.sort((a, b) {
        final aMatch = a.year == detectedYear ? 1 : 0;
        final bMatch = b.year == detectedYear ? 1 : 0;
        if (aMatch != bMatch) return bMatch.compareTo(aMatch);
        return b.popularity.compareTo(a.popularity);
      });
    }

    // Typo / Spelling Correction fallback if 0 results
    String? correctedQuery;
    bool wasAutoCorrected = false;

    if (combinedResults.isEmpty) {
      final suggestion = await _getSpellingSuggestion(queryTerm);
      if (suggestion != null && suggestion.toLowerCase() != queryTerm.toLowerCase()) {
        correctedQuery = suggestion;
        wasAutoCorrected = true;

        if (detectedYear != null) {
          final yearMovies = await fetchItems('/search/movie', {
            'query': correctedQuery,
            'primary_release_year': detectedYear,
          });
          addItems(yearMovies);
        }

        final corrMulti = await Future.wait([
          fetchItems('/search/multi', {'query': correctedQuery, 'page': '$page'}),
          if (page == 1) fetchItems('/search/multi', {'query': correctedQuery, 'page': '2'}),
        ]);
        for (final list in corrMulti) {
          addItems(list);
        }
      }
    }

    return SmartSearchResult(
      results: combinedResults,
      originalQuery: q,
      detectedYear: detectedYear,
      correctedQuery: correctedQuery,
      detectedCategory: categoryLabel,
      wasAutoCorrected: wasAutoCorrected,
    );
  }

  Future<String?> _getSpellingSuggestion(String query) async {
    try {
      final uri = Uri.parse('https://suggestqueries.google.com/complete/search?client=firefox&q=${Uri.encodeComponent(query)}');
      final response = await _client.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.length > 1 && data[1] is List) {
          final list = data[1] as List;
          if (list.isNotEmpty) {
            String first = list.first.toString().trim();
            first = first.replaceAll(RegExp(r'\b(movie|film|cast|meaning|trailer|full movie|download)\b', caseSensitive: false), '').trim();
            if (first.isNotEmpty) return first;
          }
        }
      }
    } catch (_) {}

    try {
      final kwData = await _get('/search/keyword', {'query': query});
      final kwList = kwData['results'] as List<dynamic>? ?? [];
      if (kwList.isNotEmpty) {
        final name = kwList.first['name'] as String?;
        if (name != null && name.trim().isNotEmpty) {
          return name.trim();
        }
      }
    } catch (_) {}

    return null;
  }

  Future<List<Map<String, dynamic>>> getGenres(String type) async {
    final data = await _get('/genre/$type/list');
    final genres = data['genres'] as List<dynamic>? ?? [];
    return genres.map((e) => {'id': e['id'] as int, 'name': e['name'] as String}).toList();
  }
}

class SmartSearchResult {
  final List<MediaItem> results;
  final String? originalQuery;
  final String? detectedYear;
  final String? correctedQuery;
  final String? detectedCategory;
  final bool wasAutoCorrected;

  const SmartSearchResult({
    required this.results,
    this.originalQuery,
    this.detectedYear,
    this.correctedQuery,
    this.detectedCategory,
    this.wasAutoCorrected = false,
  });
}
