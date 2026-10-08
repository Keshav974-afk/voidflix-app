class WatchProgress {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String mediaType;
  final int season;
  final int episode;
  final double progress; // 0.0 to 1.0
  final DateTime lastWatched;

  WatchProgress({
    required this.id,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    this.progress = 0.0,
    required this.lastWatched,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'media_type': mediaType,
        'season': season,
        'episode': episode,
        'progress': progress,
        'last_watched': lastWatched.toIso8601String(),
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        id: json['id'] as int,
        title: (json['title'] ?? '') as String,
        posterPath: json['poster_path'] as String?,
        backdropPath: json['backdrop_path'] as String?,
        mediaType: (json['media_type'] ?? 'movie') as String,
        season: json['season'] as int? ?? 1,
        episode: json['episode'] as int? ?? 1,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        lastWatched: DateTime.tryParse(json['last_watched'] ?? '') ?? DateTime.now(),
      );
}
