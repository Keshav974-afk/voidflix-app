import 'dart:math' as math;
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

  // Extended Netflix & Web Categories
  List<MediaItem> _nowPlayingMovies = [];
  List<MediaItem> _romanceMovies = [];
  List<MediaItem> _crimeTV = [];
  List<MediaItem> _actionMovies = [];
  List<MediaItem> _comedyMovies = [];
  List<MediaItem> _sciFiMovies = [];
  List<MediaItem> _horrorMovies = [];
  List<MediaItem> _thrillerMovies = [];
  List<MediaItem> _documentaries = [];
  List<MediaItem> _upcomingMovies = [];

  // Dedicated Kids Content (G/PG only)
  List<MediaItem> _kidsCartoons = [];
  List<MediaItem> _kidsAnimated = [];
  List<MediaItem> _kidsFamily = [];

  // Linear Programming Recommendations & Dynamic Rails
  List<MediaItem> _topPicksLinear = [];
  List<MediaItem> _becauseYouWatched = [];
  String _becauseYouWatchedTitle = '';

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

  List<MediaItem> get nowPlayingMovies => _nowPlayingMovies;
  List<MediaItem> get romanceMovies => _romanceMovies;
  List<MediaItem> get crimeTV => _crimeTV;
  List<MediaItem> get actionMovies => _actionMovies;
  List<MediaItem> get comedyMovies => _comedyMovies;
  List<MediaItem> get sciFiMovies => _sciFiMovies;
  List<MediaItem> get horrorMovies => _horrorMovies;
  List<MediaItem> get thrillerMovies => _thrillerMovies;
  List<MediaItem> get documentaries => _documentaries;
  List<MediaItem> get upcomingMovies => _upcomingMovies;

  List<MediaItem> get kidsCartoons => _kidsCartoons;
  List<MediaItem> get kidsAnimated => _kidsAnimated;
  List<MediaItem> get kidsFamily => _kidsFamily;

  List<MediaItem> get topPicksLinear => _topPicksLinear;
  List<MediaItem> get becauseYouWatched => _becauseYouWatched;
  String get becauseYouWatchedTitle => _becauseYouWatchedTitle;

  bool get isLoadingHome => _isLoadingHome;
  String? get error => _error;

  MediaItem? get heroItem => _trending.isNotEmpty ? _trending.first : null;

  Future<void> fetchHomeData({UserProfile? profile}) async {
    _isLoadingHome = true;
    _error = null;
    notifyListeners();

    try {
      final isKids = profile?.isKids ?? false;

      if (isKids) {
        // Strict Kids Mode: exclusively G/PG family, animation, and cartoons
        final results = await Future.wait([
          _apiService.getKidsAnimatedMovies(),
          _apiService.getKidsCartoons(),
          _apiService.getKidsFamilyMovies(),
          _apiService.getAnime(),
          _apiService.getComedyMovies(),
        ]);

        _kidsAnimated = results[0];
        _kidsCartoons = results[1];
        _kidsFamily = results[2];
        _anime = results[3].where((m) => !m.isAdult && m.genreIds.contains(16)).toList();
        _comedyMovies = results[4].where((m) => !m.isAdult && (m.genreIds.contains(10751) || m.genreIds.contains(16))).toList();

        // Populate rails with clean kids content
        _trending = [..._kidsAnimated, ..._kidsCartoons]..shuffle();
        _trendingTV = _kidsCartoons;
        _popularMovies = _kidsAnimated;
        _popularTV = _kidsCartoons;
        _topRatedMovies = _kidsAnimated;
        _topRatedTV = _kidsCartoons;

        // Clear out mature/horror rails
        _horrorMovies = [];
        _thrillerMovies = [];
        _actionMovies = [];
        _crimeTV = [];
      } else {
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
          _apiService.getNowPlayingMovies(),
          _apiService.getRomanceMovies(),
          _apiService.getCrimeTV(),
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
        _nowPlayingMovies = results[15];
        _romanceMovies = results[16];
        _crimeTV = results[17];
      }
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

  Future<void> fetchPersonalizedForProfile(
    UserProfile profile, {
    List<int>? watchedIds,
    String? latestWatchedTitle,
    int? latestWatchedId,
    String? latestWatchedType,
    bool force = false,
  }) async {
    if (!force && _lastPersonalizedProfileId == profile.id && _personalizedSections.isNotEmpty) {
      return;
    }

    _isLoadingPersonalized = true;
    _lastPersonalizedProfileId = profile.id;
    notifyListeners();

    try {
      final List<PersonalizedSection> sections = [];
      final Set<int> seenMediaIds = {};

      // If Kids Mode, provide strictly curated kids sections
      if (profile.isKids) {
        if (_kidsAnimated.isNotEmpty) {
          sections.add(
            PersonalizedSection(
              title: 'Animated Blockbusters',
              subtitle: 'Top cartoons and animations for kids',
              items: _kidsAnimated.where((m) => seenMediaIds.add(m.id)).toList(),
              forceType: 'movie',
            ),
          );
        }
        if (_kidsCartoons.isNotEmpty) {
          sections.add(
            PersonalizedSection(
              title: 'Fun Cartoons & Kids TV',
              subtitle: 'Exciting series and episodes for young minds',
              items: _kidsCartoons.where((m) => seenMediaIds.add(m.id)).toList(),
              forceType: 'tv',
            ),
          );
        }
        if (_kidsFamily.isNotEmpty) {
          sections.add(
            PersonalizedSection(
              title: 'Family Movie Night',
              subtitle: 'Wholesome movies the whole family can enjoy together',
              items: _kidsFamily.where((m) => seenMediaIds.add(m.id)).toList(),
              forceType: 'movie',
            ),
          );
        }
        _personalizedSections = sections;
        return;
      }

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
            genreItems = _romanceMovies.isNotEmpty ? _romanceMovies : await _apiService.discoverByGenre('movie', 10749);
            break;
          case 14: // Fantasy
            genreTitle = 'Mythic Fantasy & Mythological Legends';
            genreSubtitle = 'Swords, sorcery, dragons, and parallel realms';
            genreItems = await _apiService.discoverByGenre('movie', 14);
            break;
          case 80: // Crime
            genreTitle = 'Crime, Mafia & Underworld Chronicles';
            genreSubtitle = 'Heists, noir investigations, and gritty crime sagas';
            genreItems = _crimeTV.isNotEmpty ? _crimeTV : await _apiService.discoverByGenre('tv', 80);
            forceType = 'tv';
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

      // 5. Linear Scoring Optimization Model for Top Picks
      final pool = <MediaItem>{
        ..._trending,
        ..._popularMovies,
        ..._popularTV,
        ..._topRatedMovies,
        ..._nowPlayingMovies,
        ..._actionMovies,
        ..._sciFiMovies,
        ..._comedyMovies,
      }.toList();

      final genreCounts = <int, int>{};
      final scoredCandidates = <MapEntry<MediaItem, double>>[];

      for (final m in pool) {
        if (watchedIds != null && watchedIds.contains(m.id)) continue;

        double score = 0.0;
        final genreMatch = m.genreIds.where((g) => profile.preferredGenres.contains(g)).length;
        score += genreMatch * 2.5;

        if (profile.preferredLanguages.contains(m.originalLanguage)) {
          score += 2.0;
        }

        score += (m.voteAverage / 10.0) * 1.5;
        final pop = m.popularity > 1.0 ? m.popularity : 1.0;
        score += (math.log(pop) / math.ln10) * 1.0;

        scoredCandidates.add(MapEntry(m, score));
      }

      scoredCandidates.sort((a, b) => b.value.compareTo(a.value));

      final selectedTopPicks = <MediaItem>[];
      for (final entry in scoredCandidates) {
        final item = entry.key;
        final primaryGenre = item.genreIds.isNotEmpty ? item.genreIds.first : 0;
        final currentCount = genreCounts[primaryGenre] ?? 0;
        if (currentCount < 4) {
          selectedTopPicks.add(item);
          genreCounts[primaryGenre] = currentCount + 1;
        }
        if (selectedTopPicks.length >= 15) break;
      }
      _topPicksLinear = selectedTopPicks;

      if (_topPicksLinear.isNotEmpty) {
        sections.insert(
          0,
          PersonalizedSection(
            title: 'Top Picks For ${profile.name}',
            subtitle: 'Personalized based on your viewing tastes & preferences',
            items: _topPicksLinear,
          ),
        );
      }

      // 6. Because You Watched {Title}
      if (latestWatchedId != null && latestWatchedTitle != null && latestWatchedTitle.isNotEmpty) {
        _becauseYouWatchedTitle = latestWatchedTitle;
        try {
          final recs = await _apiService.getRecommendations(latestWatchedType ?? 'movie', latestWatchedId);
          _becauseYouWatched = recs.where((m) => !seenMediaIds.contains(m.id)).take(12).toList();
        } catch (_) {}
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
