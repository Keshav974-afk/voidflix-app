import 'package:flutter/material.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import 'profile_provider.dart';

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

  // Profile-based Personalized Recommendations
  List<PersonalizedSection> _personalizedSections = [];
  bool _isLoadingPersonalized = false;
  String? _lastPersonalizedProfileId;

  List<PersonalizedSection> get personalizedSections => _personalizedSections;
  bool get isLoadingPersonalized => _isLoadingPersonalized;

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

  Future<void> fetchPersonalizedForProfile(UserProfile profile, {bool force = false}) async {
    if (!force && _lastPersonalizedProfileId == profile.id && _personalizedSections.isNotEmpty) {
      return;
    }

    _isLoadingPersonalized = true;
    _lastPersonalizedProfileId = profile.id;
    notifyListeners();

    try {
      final List<PersonalizedSection> sections = [];
      final Set<int> seenMediaIds = {};

      // 1. Language-based personalized sections
      for (final lang in profile.preferredLanguages) {
        if (lang == 'hi') {
          final hiMovies = await _apiService.discoverByLanguage('movie', 'hi');
          final uniqueHi = hiMovies.where((m) => seenMediaIds.add(m.id)).toList();
          if (uniqueHi.isNotEmpty) {
            sections.add(
              PersonalizedSection(
                title: 'Top Bollywood & Hindi Hits',
                subtitle: 'Curated based on your love for Hindi cinema',
                items: uniqueHi,
                forceType: 'movie',
              ),
            );
          }
        } else if (lang == 'ja') {
          final anime = await _apiService.getAnime();
          final uniqueAnime = anime.where((m) => seenMediaIds.add(m.id)).toList();
          if (uniqueAnime.isNotEmpty) {
            sections.add(
              PersonalizedSection(
                title: 'Anime Masterpieces For You',
                subtitle: 'Japanese animation selected for your taste',
                items: uniqueAnime,
                forceType: 'tv',
              ),
            );
          }
        } else if (lang == 'ko') {
          final kdrama = await _apiService.getAsianDrama();
          final uniqueKdrama = kdrama.where((m) => seenMediaIds.add(m.id)).toList();
          if (uniqueKdrama.isNotEmpty) {
            sections.add(
              PersonalizedSection(
                title: 'Trending K-Dramas & Asian Series',
                subtitle: 'Korean romantic and thriller hits',
                items: uniqueKdrama,
                forceType: 'tv',
              ),
            );
          }
        } else if (lang == 'te' || lang == 'ta') {
          final southCinema = await _apiService.discoverByLanguage('movie', lang);
          final uniqueSouth = southCinema.where((m) => seenMediaIds.add(m.id)).toList();
          if (uniqueSouth.isNotEmpty) {
            sections.add(
              PersonalizedSection(
                title: lang == 'te' ? 'Tollywood Blockbusters' : 'Kollywood Masterpieces',
                subtitle: 'High energy South Indian cinema',
                items: uniqueSouth,
                forceType: 'movie',
              ),
            );
          }
        }
      }

      // 2. Genre-based personalized sections
      for (final genreId in profile.preferredGenres) {
        String genreTitle = '';
        String genreSubtitle = '';
        String forceType = 'movie';
        List<MediaItem> genreItems = [];

        switch (genreId) {
          case 878: // Sci-Fi
            genreTitle = 'Mind-Bending Sci-Fi & Speculative Epics';
            genreSubtitle = 'Space odysseys, cybernetic futures, and time warps';
            genreItems = _sciFiMovies.isNotEmpty ? _sciFiMovies : await _apiService.getSciFiMovies();
            break;
          case 28: // Action
            genreTitle = 'High-Octane Action Picked For You';
            genreSubtitle = 'Pure adrenaline, martial arts, and explosions';
            genreItems = _actionMovies.isNotEmpty ? _actionMovies : await _apiService.getActionMovies();
            break;
          case 35: // Comedy
            genreTitle = 'Laugh-Out-Loud Comedies & Sitcoms';
            genreSubtitle = 'Feel-good comedy gems and hilarious comfort watches';
            genreItems = _comedyMovies.isNotEmpty ? _comedyMovies : await _apiService.getComedyMovies();
            break;
          case 27: // Horror
            genreTitle = 'Nightmare Fuel: Horror & Paranormal';
            genreSubtitle = 'Supernatural dread, psychological terrors, and slashers';
            genreItems = _horrorMovies.isNotEmpty ? _horrorMovies : await _apiService.getHorrorMovies();
            break;
          case 53: // Thriller
            genreTitle = 'Edge-of-Your-Seat Thrillers & Mystery';
            genreSubtitle = 'Plot twists, suspense, and cat-and-mouse chases';
            genreItems = _thrillerMovies.isNotEmpty ? _thrillerMovies : await _apiService.getThrillerMovies();
            break;
          case 16: // Animation
            genreTitle = 'Animated Universes & Fantasy';
            genreSubtitle = 'Timeless storytelling in stunning animated art';
            genreItems = _anime.isNotEmpty ? _anime : await _apiService.getAnime();
            forceType = 'tv';
            break;
          case 10749: // Romance
            genreTitle = 'Romance & Heartwarming Dramas';
            genreSubtitle = 'Emotional depth, chemistry, and captivating love stories';
            genreItems = await _apiService.discoverByGenre('movie', 10749);
            break;
          case 14: // Fantasy
            genreTitle = 'Mythic Fantasy & Mythological Legends';
            genreSubtitle = 'Swords, sorcery, dragons, and parallel realms';
            genreItems = await _apiService.discoverByGenre('movie', 14);
            break;
          case 80: // Crime
            genreTitle = 'Crime, Mafia & Underworld Chronicles';
            genreSubtitle = 'Heists, noir investigations, and gritty crime sagas';
            genreItems = await _apiService.discoverByGenre('movie', 80);
            break;
          case 99: // Documentary
            genreTitle = 'Eye-Opening Documentaries & Docuseries';
            genreSubtitle = 'Real history, true crime mysteries, and wonders of nature';
            genreItems = _documentaries.isNotEmpty ? _documentaries : await _apiService.getDocumentaries();
            break;
        }

        if (genreItems.isNotEmpty) {
          final unique = genreItems.where((m) => seenMediaIds.add(m.id)).toList();
          if (unique.isNotEmpty) {
            sections.add(
              PersonalizedSection(
                title: genreTitle,
                subtitle: genreSubtitle,
                items: unique,
                forceType: forceType,
              ),
            );
          }
        }
      }

      // 3. Favorite Actor/Director Spotlight sections
      for (final actor in profile.favoriteActors) {
        if (actor.trim().isEmpty) continue;
        final actorMedia = await _apiService.searchPersonMedia(actor.trim());
        final validActorMedia = actorMedia.where((m) => seenMediaIds.add(m.id)).toList();
        if (validActorMedia.isNotEmpty) {
          sections.add(
            PersonalizedSection(
              title: 'Spotlight: $actor',
              subtitle: 'Top acclaimed movies and appearances by $actor',
              items: validActorMedia,
            ),
          );
        }
      }

      // 4. Favorite Titles / Franchise sections
      for (final title in profile.favoriteTitles) {
        if (title.trim().isEmpty) continue;
        final titleResults = await _apiService.search(title.trim());
        final validTitleResults = titleResults.where((m) => seenMediaIds.add(m.id)).take(12).toList();
        if (validTitleResults.isNotEmpty) {
          sections.add(
            PersonalizedSection(
              title: 'Because You Like "$title"',
              subtitle: 'Similar titles, sagas, and recommendations',
              items: validTitleResults,
            ),
          );
        }
      }

      // 5. Curated Top Recommendations for the Profile
      final List<MediaItem> topPicks = [];
      for (final sec in sections) {
        if (sec.items.isNotEmpty) {
          topPicks.add(sec.items.first);
          if (sec.items.length > 1) {
            topPicks.add(sec.items[1]);
          }
        }
      }
      if (topPicks.isNotEmpty) {
        sections.insert(
          0,
          PersonalizedSection(
            title: 'Recommended For ${profile.name}',
            subtitle: 'Specially tuned to your favorite cinema tastes',
            items: topPicks,
          ),
        );
      }

      _personalizedSections = sections;
    } catch (e) {
      debugPrint('Error generating personalized feed: $e');
    } finally {
      _isLoadingPersonalized = false;
      notifyListeners();
    }
  }
}

class PersonalizedSection {
  final String title;
  final String subtitle;
  final List<MediaItem> items;
  final String? forceType;

  PersonalizedSection({
    required this.title,
    required this.subtitle,
    required this.items,
    this.forceType,
  });
}
