import 'media_item.dart';
import '../core/utils/language_utils.dart';

class CastMember {
  final int id;
  final String name;
  final String character;
  final String? profilePath;

  CastMember({
    required this.id,
    required this.name,
    required this.character,
    this.profilePath,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] as int? ?? 0,
      name: (json['name'] ?? '') as String,
      character: (json['character'] ?? '') as String,
      profilePath: json['profile_path'] as String?,
    );
  }
}

class TvSeason {
  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;

  TvSeason({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath,
  });

  factory TvSeason.fromJson(Map<String, dynamic> json) {
    return TvSeason(
      id: json['id'] as int? ?? 0,
      seasonNumber: json['season_number'] as int? ?? 1,
      name: (json['name'] ?? '') as String,
      episodeCount: json['episode_count'] as int? ?? 0,
      posterPath: json['poster_path'] as String?,
    );
  }
}

class TvEpisode {
  final int episodeNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final int runtime;

  TvEpisode({
    required this.episodeNumber,
    required this.name,
    required this.overview,
    this.stillPath,
    this.runtime = 0,
  });

  factory TvEpisode.fromJson(Map<String, dynamic> json) {
    return TvEpisode(
      episodeNumber: json['episode_number'] as int? ?? 1,
      name: (json['name'] ?? 'Episode ${json['episode_number']}') as String,
      overview: (json['overview'] ?? '') as String,
      stillPath: json['still_path'] as String?,
      runtime: json['runtime'] as int? ?? 0,
    );
  }
}

class MediaVideo {
  final String id;
  final String name;
  final String key;
  final String site;
  final String type;
  final String iso6391;
  final bool official;

  MediaVideo({
    required this.id,
    required this.name,
    required this.key,
    required this.site,
    required this.type,
    this.iso6391 = 'en',
    this.official = false,
  });

  factory MediaVideo.fromJson(Map<String, dynamic> json) {
    return MediaVideo(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? 'Trailer') as String,
      key: (json['key'] ?? '') as String,
      site: (json['site'] ?? 'YouTube') as String,
      type: (json['type'] ?? 'Trailer') as String,
      iso6391: (json['iso_639_1'] ?? 'en') as String,
      official: json['official'] == true,
    );
  }

  bool get isYouTube => site.toLowerCase() == 'youtube' && key.isNotEmpty;

  bool get isTrailer => type.toLowerCase().trim() == 'trailer';
  bool get isTeaser => type.toLowerCase().trim() == 'teaser';
  bool get isTrailerOrTeaser => isTrailer || isTeaser;

  bool get isClip => type.toLowerCase().trim() == 'clip' || type.toLowerCase().contains('clip');
  bool get isBehindTheScenes {
    final t = type.toLowerCase().trim();
    return t == 'behind the scenes' ||
        t.contains('behind') ||
        t == 'featurette' ||
        t.contains('featurette') ||
        t == 'bloopers' ||
        t.contains('blooper');
  }

  bool get isClipOrBTS => isClip || isBehindTheScenes;

  bool get isOfficial {
    if (official) return true;
    final n = name.toLowerCase();
    return n.contains('official');
  }

  String get youtubeThumbnailUrl => 'https://img.youtube.com/vi/$key/mqdefault.jpg';
}

class MediaDetail {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double voteAverage;
  final String? releaseDate;
  final String mediaType;
  final List<String> genres;
  final int? runtime;
  final String? tagline;
  final List<CastMember> cast;
  final List<MediaItem> recommendations;
  final List<TvSeason> seasons;
  final String? trailerKey;
  final List<MediaVideo> videos;
  final String? logoPath;
  final String? originalLanguage;

  MediaDetail({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.overview,
    required this.voteAverage,
    this.releaseDate,
    required this.mediaType,
    this.genres = const [],
    this.runtime,
    this.tagline,
    this.cast = const [],
    this.recommendations = const [],
    this.seasons = const [],
    this.trailerKey,
    this.videos = const [],
    this.logoPath,
    this.originalLanguage,
  });

  factory MediaDetail.fromJson(Map<String, dynamic> json, String type) {
    final title = (json['title'] ?? json['name'] ?? 'Untitled') as String;
    final releaseDate = (json['release_date'] ?? json['first_air_date']) as String?;

    final genresList = (json['genres'] as List<dynamic>?)
            ?.map((e) => (e['name'] ?? '') as String)
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final credits = json['credits'] as Map<String, dynamic>?;
    final castList = (credits?['cast'] as List<dynamic>?)
            ?.take(15)
            .map((e) => CastMember.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final recs = json['recommendations'] as Map<String, dynamic>?;
    final recList = (recs?['results'] as List<dynamic>?)
            ?.map((e) => MediaItem.fromJson(e as Map<String, dynamic>, defaultType: type))
            .toList() ??
        [];

    final seasonsList = (json['seasons'] as List<dynamic>?)
            ?.map((e) => TvSeason.fromJson(e as Map<String, dynamic>))
            .where((s) => s.seasonNumber > 0)
            .toList() ??
        [];

    final videos = json['videos'] as Map<String, dynamic>?;
    String? trailer;
    List<MediaVideo> videoResults = [];
    if (videos != null && videos['results'] != null) {
      final rawList = videos['results'] as List<dynamic>;
      videoResults = rawList
          .where((v) => v['site'] == 'YouTube' && v['key'] != null && (v['key'] as String).isNotEmpty)
          .map((v) => MediaVideo.fromJson(v as Map<String, dynamic>))
          .toList();

      final trailerMatch = videoResults.where((v) => v.isTrailerOrTeaser).toList();
      if (trailerMatch.isNotEmpty) {
        trailerMatch.sort((a, b) {
          int score(MediaVideo v) {
            int s = 0;
            if (v.isOfficial) s += 200;
            if (v.isTrailer) s += 100;
            return s;
          }
          return score(b) - score(a);
        });
        trailer = trailerMatch.first.key;
      }
    }

    final images = json['images'] as Map<String, dynamic>?;
    String? logoPath;
    if (images != null && images['logos'] != null) {
      final logosList = images['logos'] as List<dynamic>;
      if (logosList.isNotEmpty) {
        final enLogo = logosList.firstWhere(
          (l) => l['iso_639_1'] == 'en',
          orElse: () => null,
        );
        final neutralLogo = logosList.firstWhere(
          (l) => l['iso_639_1'] == null || l['iso_639_1'] == 'xx' || l['iso_639_1'] == '',
          orElse: () => null,
        );
        final picked = enLogo ?? neutralLogo ?? logosList.first;
        logoPath = picked['file_path'] as String?;
      }
    }

    return MediaDetail(
      id: json['id'] as int? ?? 0,
      title: title,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: (json['overview'] ?? '') as String,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: releaseDate,
      mediaType: type,
      genres: genresList,
      runtime: (json['runtime'] ?? (json['episode_run_time'] as List<dynamic>?)?.firstOrNull) as int?,
      tagline: json['tagline'] as String?,
      cast: castList,
      recommendations: recList,
      seasons: seasonsList,
      trailerKey: trailer,
      videos: videoResults,
      logoPath: logoPath,
      originalLanguage: json['original_language'] as String?,
    );
  }

  /// Finds the official trailer or teaser key for the app trailer section.
  /// Strictly filters to Trailers and Teasers only (no clips, no behind the scenes).
  /// Priority:
  /// 1. Official trailer / teaser in user preferred language
  /// 2. Official trailer / teaser in media original language
  /// 3. English official trailer / teaser fallback
  /// 4. Any official trailer / teaser
  /// Returns null if no trailer or teaser exists (never returns clips/BTS).
  String? findTrailerKey({String? preferredLangCode}) {
    final ytTrailers = videos.where((v) => v.isYouTube && v.isTrailerOrTeaser).toList();
    if (ytTrailers.isEmpty) {
      return trailerKey;
    }

    int scoreTrailer(MediaVideo v, {String? targetLang}) {
      int score = 0;
      if (targetLang != null && targetLang.isNotEmpty) {
        if (LanguageUtils.matches(v.iso6391, targetLang)) {
          score += 1000;
        } else if (LanguageUtils.matches(v.name, targetLang)) {
          score += 500;
        }
      }

      // Official status
      if (v.official) score += 300;
      if (v.name.toLowerCase().contains('official')) score += 200;

      // Trailer vs Teaser
      if (v.isTrailer) {
        score += 150;
        final n = v.name.toLowerCase();
        if (n.contains('official trailer') || n.contains('main trailer') || n.contains('final trailer')) {
          score += 100;
        }
      } else if (v.isTeaser) {
        score += 80;
        final n = v.name.toLowerCase();
        if (n.contains('official teaser') || n.contains('teaser trailer')) {
          score += 40;
        }
      }
      return score;
    }

    // 1. Check user preferred language
    if (preferredLangCode != null && preferredLangCode.isNotEmpty) {
      final prefMatches = ytTrailers.where(
        (v) => LanguageUtils.matches(v.iso6391, preferredLangCode) ||
               LanguageUtils.matches(v.name, preferredLangCode),
      ).toList();

      if (prefMatches.isNotEmpty) {
        prefMatches.sort((a, b) => scoreTrailer(b, targetLang: preferredLangCode) - scoreTrailer(a, targetLang: preferredLangCode));
        return prefMatches.first.key;
      }
    }

    // 2. Check original language of the media
    if (originalLanguage != null && originalLanguage!.isNotEmpty) {
      final origMatches = ytTrailers.where(
        (v) => LanguageUtils.matches(v.iso6391, originalLanguage!) ||
               v.iso6391.toLowerCase() == originalLanguage!.toLowerCase() ||
               LanguageUtils.matches(v.name, originalLanguage!),
      ).toList();

      if (origMatches.isNotEmpty) {
        origMatches.sort((a, b) => scoreTrailer(b, targetLang: originalLanguage) - scoreTrailer(a, targetLang: originalLanguage));
        return origMatches.first.key;
      }
    }

    // 3. Fallback: English trailer or teaser
    final enMatches = ytTrailers.where(
      (v) => LanguageUtils.matches(v.iso6391, 'en') ||
             v.iso6391.toLowerCase() == 'en' ||
             LanguageUtils.matches(v.name, 'english'),
    ).toList();

    if (enMatches.isNotEmpty) {
      enMatches.sort((a, b) => scoreTrailer(b, targetLang: 'en') - scoreTrailer(a, targetLang: 'en'));
      return enMatches.first.key;
    }

    // 4. Any Trailer or Teaser available (sorted by score)
    ytTrailers.sort((a, b) => scoreTrailer(b) - scoreTrailer(a));
    return ytTrailers.first.key;
  }

  /// Finds the best clip or behind-the-scenes video for the Clips section.
  /// Prioritizes actual Clips and Behind the Scenes in preferred / original language.
  /// If no clips/BTS exist on TMDB, falls back to trailer or teaser.
  MediaVideo? findBestClipVideo({String? preferredLangCode}) {
    if (videos.isEmpty) return null;
    final yt = videos.where((v) => v.isYouTube).toList();
    if (yt.isEmpty) return null;

    final clipsAndBts = yt.where((v) => v.isClipOrBTS).toList();

    int scoreClip(MediaVideo v, {String? targetLang}) {
      int score = 0;
      if (targetLang != null && targetLang.isNotEmpty) {
        if (LanguageUtils.matches(v.iso6391, targetLang)) {
          score += 1000;
        } else if (LanguageUtils.matches(v.name, targetLang)) {
          score += 500;
        }
      }
      if (v.isClip) {
        score += 300;
      } else if (v.isBehindTheScenes) {
        score += 200;
      }
      if (v.official) {
        score += 50;
      }
      return score;
    }

    // Prioritize actual clips and behind the scenes
    if (clipsAndBts.isNotEmpty) {
      // 1. Check preferred language
      if (preferredLangCode != null && preferredLangCode.isNotEmpty) {
        final prefMatches = clipsAndBts.where(
          (v) => LanguageUtils.matches(v.iso6391, preferredLangCode) ||
                 LanguageUtils.matches(v.name, preferredLangCode),
        ).toList();
        if (prefMatches.isNotEmpty) {
          prefMatches.sort((a, b) => scoreClip(b, targetLang: preferredLangCode) - scoreClip(a, targetLang: preferredLangCode));
          return prefMatches.first;
        }
      }

      // 2. Check original language
      if (originalLanguage != null && originalLanguage!.isNotEmpty) {
        final origMatches = clipsAndBts.where(
          (v) => LanguageUtils.matches(v.iso6391, originalLanguage!) ||
                 v.iso6391.toLowerCase() == originalLanguage!.toLowerCase() ||
                 LanguageUtils.matches(v.name, originalLanguage!),
        ).toList();
        if (origMatches.isNotEmpty) {
          origMatches.sort((a, b) => scoreClip(b, targetLang: originalLanguage) - scoreClip(a, targetLang: originalLanguage));
          return origMatches.first;
        }
      }

      // 3. Fallback: English clips or BTS
      final enMatches = clipsAndBts.where(
        (v) => LanguageUtils.matches(v.iso6391, 'en') ||
               v.iso6391.toLowerCase() == 'en' ||
               LanguageUtils.matches(v.name, 'english'),
      ).toList();
      if (enMatches.isNotEmpty) {
        enMatches.sort((a, b) => scoreClip(b, targetLang: 'en') - scoreClip(a, targetLang: 'en'));
        return enMatches.first;
      }

      // 4. Any clips or BTS
      clipsAndBts.sort((a, b) => scoreClip(b) - scoreClip(a));
      return clipsAndBts.first;
    }

    // If no clips or BTS exist on TMDB, fall back to official trailer/teaser
    final trailerKey = findTrailerKey(preferredLangCode: preferredLangCode);
    if (trailerKey != null) {
      return yt.firstWhere((v) => v.key == trailerKey, orElse: () => yt.first);
    }

    return null;
  }

  String? findClipKey({String? preferredLangCode}) {
    return findBestClipVideo(preferredLangCode: preferredLangCode)?.key;
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      title: title,
      posterPath: posterPath,
      backdropPath: backdropPath,
      overview: overview,
      voteAverage: voteAverage,
      releaseDate: releaseDate,
      mediaType: mediaType,
    );
  }
}
