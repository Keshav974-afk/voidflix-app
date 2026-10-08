import 'media_item.dart';

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

  MediaVideo({
    required this.id,
    required this.name,
    required this.key,
    required this.site,
    required this.type,
  });

  factory MediaVideo.fromJson(Map<String, dynamic> json) {
    return MediaVideo(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? 'Trailer') as String,
      key: (json['key'] ?? '') as String,
      site: (json['site'] ?? 'YouTube') as String,
      type: (json['type'] ?? 'Trailer') as String,
    );
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
          .where((v) => v['site'] == 'YouTube' && v['key'] != null)
          .map((v) => MediaVideo.fromJson(v as Map<String, dynamic>))
          .toList();

      final match = rawList.firstWhere(
        (v) => (v['type'] == 'Trailer' || v['type'] == 'Teaser') && v['site'] == 'YouTube',
        orElse: () => null,
      );
      if (match != null) {
        trailer = match['key'] as String?;
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
    );
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
