import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../models/media_item.dart';
import '../../models/media_detail.dart';

class ApiService {
  final http.Client _client = http.Client();

  static String getImageUrl(String? path, {String size = 'w500'}) {
    return ApiConstants.getImageUrl(path, size: size);
  }

  Future<List<MediaItem>> getTrending() => getTrendingAll();

  Future<dynamic> _get(String endpoint, [Map<String, String>? queryParams]) async {
    final params = {
      'api_key': ApiConstants.tmdbApiKey,
      ...?queryParams,
    };

    final uri = Uri.parse('${ApiConstants.tmdbBaseUrl}$endpoint').replace(queryParameters: params);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('TMDB API Error: ${response.statusCode}');
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

  Future<List<MediaItem>> getActionMovies({int page = 1}) => discoverByGenre('movie', 28, page: page);
  Future<List<MediaItem>> getComedyMovies({int page = 1}) => discoverByGenre('movie', 35, page: page);
  Future<List<MediaItem>> getSciFiMovies({int page = 1}) => discoverByGenre('movie', 878, page: page);
  Future<List<MediaItem>> getHorrorMovies({int page = 1}) => discoverByGenre('movie', 27, page: page);
  Future<List<MediaItem>> getThrillerMovies({int page = 1}) => discoverByGenre('movie', 53, page: page);
  Future<List<MediaItem>> getDocumentaries({int page = 1}) => discoverByGenre('movie', 99, page: page);
  Future<List<MediaItem>> getFamilyMovies({int page = 1}) => discoverByGenre('movie', 10751, page: page);

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

  Future<MediaDetail> getDetails(String type, int id) async {
    final data = await _get('/$type/$id', {
      'append_to_response': 'credits,recommendations,videos,release_dates,content_ratings',
    });
    return MediaDetail.fromJson(data as Map<String, dynamic>, type);
  }

  Future<List<TvEpisode>> getSeasonEpisodes(int id, int seasonNumber) async {
    final data = await _get('/tv/$id/season/$seasonNumber');
    final episodes = data['episodes'] as List<dynamic>? ?? [];
    return episodes.map((e) => TvEpisode.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/multi', {
      'query': query,
      'page': '$page',
    });
    final results = data['results'] as List<dynamic>? ?? [];
    return results
        .where((e) => e['media_type'] == 'movie' || e['media_type'] == 'tv')
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getGenres(String type) async {
    final data = await _get('/genre/$type/list');
    final genres = data['genres'] as List<dynamic>? ?? [];
    return genres.map((e) => {'id': e['id'] as int, 'name': e['name'] as String}).toList();
  }
}
