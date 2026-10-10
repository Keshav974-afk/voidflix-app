class DownloadedItem {
  final String id; // 'movie_123' or 'tv_123_s1_e1'
  final int mediaId;
  final String title;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? episodeTitle;
  final String? episodeDescription;
  final String? posterPath;
  final String? backdropPath;
  final String? stillPath;
  final int runtime;
  final String localFilePath;
  final String? localThumbnailPath;
  final String? localSubtitlePath;
  final int fileSizeBytes;
  final int downloadedBytes;
  final int totalBytes;
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
    this.episodeDescription,
    this.posterPath,
    this.backdropPath,
    this.stillPath,
    this.runtime = 0,
    required this.localFilePath,
    this.localThumbnailPath,
    this.localSubtitlePath,
    this.fileSizeBytes = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    required this.status,
    this.progress = 0.0,
    required this.downloadedAt,
    this.quality = 'HD',
  });

  DownloadedItem copyWith({
    String? title,
    String? status,
    double? progress,
    int? fileSizeBytes,
    int? downloadedBytes,
    int? totalBytes,
    String? localFilePath,
    String? localThumbnailPath,
    String? localSubtitlePath,
    String? quality,
    String? episodeDescription,
    String? stillPath,
    int? runtime,
  }) {
    return DownloadedItem(
      id: id,
      mediaId: mediaId,
      title: title ?? this.title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      episodeDescription: episodeDescription ?? this.episodeDescription,
      posterPath: posterPath,
      backdropPath: backdropPath,
      stillPath: stillPath ?? this.stillPath,
      runtime: runtime ?? this.runtime,
      localFilePath: localFilePath ?? this.localFilePath,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      localSubtitlePath: localSubtitlePath ?? this.localSubtitlePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
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
        'episodeDescription': episodeDescription,
        'posterPath': posterPath,
        'backdropPath': backdropPath,
        'stillPath': stillPath,
        'runtime': runtime,
        'localFilePath': localFilePath,
        'localThumbnailPath': localThumbnailPath,
        'localSubtitlePath': localSubtitlePath,
        'fileSizeBytes': fileSizeBytes,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
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
        episodeDescription: json['episodeDescription'] as String?,
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        stillPath: json['stillPath'] as String?,
        runtime: json['runtime'] as int? ?? 0,
        localFilePath: json['localFilePath'] as String? ?? '',
        localThumbnailPath: json['localThumbnailPath'] as String?,
        localSubtitlePath: json['localSubtitlePath'] as String?,
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        totalBytes: json['totalBytes'] as int? ?? 0,
        status: json['status'] as String? ?? 'completed',
        progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
        downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now(),
        quality: json['quality'] as String? ?? 'HD',
      );

  String get formattedSize {
    final bytes = fileSizeBytes > 0 ? fileSizeBytes : downloadedBytes;
    if (bytes <= 0) return 'Unknown size';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      final gb = mb / 1024;
      return '${gb.toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}
