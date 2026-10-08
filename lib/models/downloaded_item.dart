class DownloadedItem {
  final String id; // 'movie_123' or 'tv_123_s1_e1'
  final int mediaId;
  final String title;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? episodeTitle;
  final String? posterPath;
  final String? backdropPath;
  final String localFilePath;
  final int fileSizeBytes;
  final String status; // 'downloading', 'completed', 'failed', 'paused'
  final double progress; // 0.0 to 1.0
  final DateTime downloadedAt;
  final String quality;

  const DownloadedItem({
    required this.id,
    required this.mediaId,
    required this.title,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    this.episodeTitle,
    this.posterPath,
    this.backdropPath,
    required this.localFilePath,
    this.fileSizeBytes = 0,
    required this.status,
    this.progress = 0.0,
    required this.downloadedAt,
    this.quality = 'HD',
  });

  DownloadedItem copyWith({
    String? status,
    double? progress,
    int? fileSizeBytes,
    String? localFilePath,
    String? quality,
  }) {
    return DownloadedItem(
      id: id,
      mediaId: mediaId,
      title: title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      posterPath: posterPath,
      backdropPath: backdropPath,
      localFilePath: localFilePath ?? this.localFilePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedAt: downloadedAt,
      quality: quality ?? this.quality,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaId': mediaId,
        'title': title,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'localFilePath': localFilePath,
        'fileSizeBytes': fileSizeBytes,
        'status': status,
        'progress': progress,
        'downloadedAt': downloadedAt.toIso8601String(),
        'quality': quality,
      };

  factory DownloadedItem.fromJson(Map<String, dynamic> json) => DownloadedItem(
        id: json['id'] as String,
        mediaId: json['mediaId'] as int,
        title: json['title'] as String,
        mediaType: json['mediaType'] as String,
        season: json['season'] as int? ?? 1,
        episode: json['episode'] as int? ?? 1,
        episodeTitle: json['episodeTitle'] as String?,
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        localFilePath: json['localFilePath'] as String? ?? '',
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        status: json['status'] as String? ?? 'completed',
        progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
        downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now(),
        quality: json['quality'] as String? ?? 'HD',
      );

  String get formattedSize {
    if (fileSizeBytes <= 0) return 'Unknown size';
    final mb = fileSizeBytes / (1024 * 1024);
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}
