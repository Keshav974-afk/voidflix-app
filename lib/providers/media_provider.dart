import 'package:flutter/material.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';

class MediaProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<MediaItem> _trending = [];
  List<MediaItem> _trendingTV = [];
  List<MediaItem> _popularMovies = [];
  List<MediaItem> _topRatedMovies = [];
  List<MediaItem> _popularTV = [];
  List<MediaItem> _topRatedTV = [];
  List<MediaItem> _anime = [];
  List<MediaItem> _asianDrama = [];

  // Extended Netflix Categories
  List<MediaItem> _actionMovies = [];
  List<MediaItem> _comedyMovies = [];
  List<MediaItem> _sciFiMovies = [];
  List<MediaItem> _horrorMovies = [];
  List<MediaItem> _thrillerMovies = [];
  List<MediaItem> _documentaries = [];
  List<MediaItem> _upcomingMovies = [];

  bool _isLoadingHome = false;
  String? _error;

  List<MediaItem> get trending => _trending;
  List<MediaItem> get trendingTV => _trendingTV;
  List<MediaItem> get popularMovies => _popularMovies;
  List<MediaItem> get topRatedMovies => _topRatedMovies;
  List<MediaItem> get popularTV => _popularTV;
  List<MediaItem> get topRatedTV => _topRatedTV;
  List<MediaItem> get anime => _anime;
  List<MediaItem> get asianDrama => _asianDrama;

  List<MediaItem> get actionMovies => _actionMovies;
  List<MediaItem> get comedyMovies => _comedyMovies;
  List<MediaItem> get sciFiMovies => _sciFiMovies;
  List<MediaItem> get horrorMovies => _horrorMovies;
  List<MediaItem> get thrillerMovies => _thrillerMovies;
  List<MediaItem> get documentaries => _documentaries;
  List<MediaItem> get upcomingMovies => _upcomingMovies;

  bool get isLoadingHome => _isLoadingHome;
  String? get error => _error;

  MediaItem? get heroItem => _trending.isNotEmpty ? _trending.first : null;

  Future<void> fetchHomeData() async {
    _isLoadingHome = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _apiService.getTrendingAll(),
        _apiService.getTrendingTV(),
        _apiService.getPopularMovies(),
        _apiService.getTopRatedMovies(),
        _apiService.getPopularTV(),
        _apiService.getTopRatedTV(),
        _apiService.getAnime(),
        _apiService.getAsianDrama(),
        _apiService.getActionMovies(),
        _apiService.getComedyMovies(),
        _apiService.getSciFiMovies(),
        _apiService.getHorrorMovies(),
        _apiService.getThrillerMovies(),
        _apiService.getDocumentaries(),
        _apiService.getUpcomingMovies(),
      ]);

      _trending = results[0];
      _trendingTV = results[1];
      _popularMovies = results[2];
      _topRatedMovies = results[3];
      _popularTV = results[4];
      _topRatedTV = results[5];
      _anime = results[6];
      _asianDrama = results[7];
      _actionMovies = results[8];
      _comedyMovies = results[9];
      _sciFiMovies = results[10];
      _horrorMovies = results[11];
      _thrillerMovies = results[12];
      _documentaries = results[13];
      _upcomingMovies = results[14];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  // Genre filtering and explore queries
  List<MediaItem> _genreFilteredItems = [];
  bool _isLoadingGenre = false;
  List<MediaItem> get genreFilteredItems => _genreFilteredItems;
  bool get isLoadingGenre => _isLoadingGenre;

  Future<void> fetchByGenre(String type, int genreId) async {
    _isLoadingGenre = true;
    notifyListeners();
    try {
      _genreFilteredItems = await _apiService.discoverByGenre(type, genreId);
    } catch (e) {
      _genreFilteredItems = [];
    } finally {
      _isLoadingGenre = false;
      notifyListeners();
    }
  }
}
