class MediaItem {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double voteAverage;
  final String? releaseDate;
  final String mediaType; // 'movie' or 'tv'
  final List<int> genreIds;
  final bool isAdult;
  final String originalLanguage;
  final double popularity;

  MediaItem({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.overview,
    required this.voteAverage,
    this.releaseDate,
    required this.mediaType,
    this.genreIds = const [],
    this.isAdult = false,
    this.originalLanguage = 'en',
    this.popularity = 0.0,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json, {String defaultType = 'movie'}) {
    final type = json['media_type'] as String? ?? defaultType;
    final title = (json['title'] ?? json['name'] ?? 'Untitled') as String;
    final releaseDate = (json['release_date'] ?? json['first_air_date']) as String?;

    return MediaItem(
      id: json['id'] as int? ?? 0,
      title: title,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: (json['overview'] ?? '') as String,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      releaseDate: releaseDate,
      mediaType: type == 'tv' ? 'tv' : 'movie',
      genreIds: (json['genre_ids'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
      isAdult: json['adult'] as bool? ?? false,
      originalLanguage: (json['original_language'] as String?) ?? 'en',
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'overview': overview,
      'vote_average': voteAverage,
      'release_date': releaseDate,
      'media_type': mediaType,
      'genre_ids': genreIds,
      'adult': isAdult,
      'original_language': originalLanguage,
      'popularity': popularity,
    };
  }

  String get displayTitle => title;

  String get year {
    if (releaseDate == null || releaseDate!.isEmpty) return '';
    return releaseDate!.split('-').first;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mediaType == other.mediaType;

  @override
  int get hashCode => Object.hash(id, mediaType);
}
