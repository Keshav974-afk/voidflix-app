import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/theme_constants.dart';
import '../models/downloaded_item.dart';
import '../providers/download_provider.dart';
import 'player_screen.dart';

/// Downloads Screen matching Netflix mobile application design.
///
/// Features:
/// 1. Top-level View: Groups downloads by Movie & Series.
///    - Movie card shows Title, "Movie • Size • HD", and direct offline playback.
///    - Series card shows Series Name, "X Episodes • Total Size", and navigates to the series episodes view.
/// 2. Series Detail View:
///    - Displays all downloaded episodes for that series grouped by Season.
///    - 16:9 offline local thumbnail with translucent play button overlay.
///    - Episode number & Title (e.g. "1. Pilot").
///    - Full episode synopsis / description for offline reading.
///    - Runtime, file size, status badge.
///    - Direct offline playback and resumption support.
class DownloadsScreen extends StatefulWidget {
  final int? seriesMediaId;
  final String? seriesTitle;

  const DownloadsScreen({
    super.key,
    this.seriesMediaId,
    this.seriesTitle,
  });

  /// Sanitizes title by removing any attached season/episode tags (e.g. ": S1E2 ...")
  static String sanitizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return rawTitle;
    final regex = RegExp(r':\s*S\d+.*$', caseSensitive: false);
    return rawTitle.replaceAll(regex, '').trim();
  }

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _isEditing = false;

  void _playOffline(BuildContext context, DownloadedItem item) {
    if (item.status != 'completed') {
      context.read<DownloadProvider>().resumeDownload(item.id);
      return;
    }

    final cleanTitle = DownloadsScreen.sanitizeTitle(item.title);

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => PlayerScreen(
          mediaId: item.mediaId,
          mediaTitle: cleanTitle,
          mediaType: item.mediaType,
          season: item.season,
          episode: item.episode,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          localFilePath: item.localFilePath,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  Widget _buildThumbnailWidget({
    required DownloadedItem item,
    required double width,
    required double height,
    bool is16x9 = true,
  }) {
    ImageProvider? imageProvider;

    // 1. Prefer locally downloaded thumbnail for 100% offline access
    if (item.localThumbnailPath != null && item.localThumbnailPath!.isNotEmpty) {
      final localFile = File(item.localThumbnailPath!);
      if (localFile.existsSync() && localFile.lengthSync() > 100) {
        imageProvider = FileImage(localFile);
      }
    }

    // 2. Fallback to cached network image
    if (imageProvider == null) {
      final relPath = is16x9
          ? (item.stillPath ?? item.backdropPath ?? item.posterPath)
          : (item.posterPath ?? item.backdropPath);
      if (relPath != null && relPath.isNotEmpty) {
        final url = relPath.startsWith('http')
            ? relPath
            : 'https://image.tmdb.org/t/p/w500$relPath';
        imageProvider = CachedNetworkImageProvider(url);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF222228),
        child: imageProvider != null
            ? Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Icon(Icons.movie_outlined, color: Colors.white24)),
              )
            : const Center(child: Icon(Icons.movie_outlined, color: Colors.white24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final allItems = downloadProvider.items;

    final isSeriesSubView = widget.seriesMediaId != null ||
        (widget.seriesTitle != null && widget.seriesTitle!.isNotEmpty);

    // Filter if viewing a specific series
    final items = isSeriesSubView
        ? allItems.where((i) {
            if (widget.seriesMediaId != null) {
              return i.mediaId == widget.seriesMediaId;
            }
            return DownloadsScreen.sanitizeTitle(i.title).toLowerCase() ==
                DownloadsScreen.sanitizeTitle(widget.seriesTitle!).toLowerCase();
          }).toList()
        : allItems;

    final displayTitle = isSeriesSubView
        ? (widget.seriesTitle ?? (items.isNotEmpty ? DownloadsScreen.sanitizeTitle(items.first.title) : 'Downloads'))
        : 'Downloads';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          displayTitle,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: Icon(
                _isEditing ? Icons.check : Icons.edit_outlined,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () {
                setState(() => _isEditing = !_isEditing);
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? _buildEmptyState(context)
          : isSeriesSubView
              ? _buildSeriesDetailView(context, items, downloadProvider)
              : _buildTopLevelGroupedView(context, allItems, downloadProvider),
    );
  }

  /// Empty State matching Netflix design
  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text(
                'Smart Downloads',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        CustomPaint(
          size: const Size(180, 180),
          painter: _NetflixDownloadBadgePainter(),
        ),
        const SizedBox(height: 28),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Movies and shows that you download\nappear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 38),
        SizedBox(
          width: 210,
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text(
              'Find More to Download',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const Spacer(flex: 4),
      ],
    );
  }

  /// Top-Level View: Groups downloads by Movie & Series
  Widget _buildTopLevelGroupedView(
    BuildContext context,
    List<DownloadedItem> allItems,
    DownloadProvider downloadProvider,
  ) {
    // 1. Separate Movies and TV Shows
    final movies = allItems.where((i) => i.mediaType == 'movie').toList();
    final tvItems = allItems.where((i) => i.mediaType == 'tv').toList();

    // 2. Group TV items by Series mediaId (guarantees exactly 1 card per TV show)
    final Map<int, List<DownloadedItem>> seriesGroups = {};
    for (final item in tvItems) {
      seriesGroups.putIfAbsent(item.mediaId, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        // Smart Downloads Subheader
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Smart Downloads',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  _isEditing ? Icons.check : Icons.edit_outlined,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () {
                  setState(() => _isEditing = !_isEditing);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // --- Series Cards ---
        if (seriesGroups.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Text(
              'TV SHOWS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...seriesGroups.entries.map((entry) {
            final seriesMediaId = entry.key;
            final eps = entry.value;
            final first = eps.first;

            // Extract clean series title
            final seriesTitle = eps
                .map((e) => DownloadsScreen.sanitizeTitle(e.title))
                .firstWhere((t) => t.isNotEmpty, orElse: () => first.title);

            int totalBytes = 0;
            int completedCount = 0;
            bool hasDownloading = false;
            double avgProgress = 0.0;

            for (final e in eps) {
              totalBytes += (e.fileSizeBytes > 0 ? e.fileSizeBytes : e.downloadedBytes);
              if (e.status == 'completed') completedCount++;
              if (e.status == 'downloading') {
                hasDownloading = true;
                avgProgress += e.progress;
              }
            }
            if (hasDownloading) {
              avgProgress = avgProgress / eps.length;
            }

            final totalSizeMb = totalBytes / (1024 * 1024);
            final formattedSize = totalSizeMb >= 1024
                ? '${(totalSizeMb / 1024).toStringAsFixed(1)} GB'
                : '${totalSizeMb.toStringAsFixed(0)} MB';

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DownloadsScreen(
                        seriesMediaId: seriesMediaId,
                        seriesTitle: seriesTitle,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      _buildThumbnailWidget(
                        item: first,
                        width: 72,
                        height: 96,
                        is16x9: false,
                      ),
                      const SizedBox(width: 14),

                      // Metadata
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seriesTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${eps.length} ${eps.length == 1 ? "Episode" : "Episodes"} • $formattedSize',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (hasDownloading)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      value: avgProgress > 0 ? avgProgress : null,
                                      strokeWidth: 2,
                                      color: AppTheme.primaryRed,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Downloading ${(avgProgress * 100).toInt()}%',
                                    style: const TextStyle(
                                      color: AppTheme.primaryRed,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                completedCount == eps.length
                                    ? 'All episodes downloaded'
                                    : '$completedCount of ${eps.length} ready',
                                style: TextStyle(
                                  color: completedCount == eps.length
                                      ? const Color(0xFF2ECC71)
                                      : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Action / Trailing
                      if (_isEditing)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.primaryRed, size: 24),
                          onPressed: () {
                            for (final e in eps) {
                              downloadProvider.deleteDownload(e.id);
                            }
                          },
                        )
                      else
                        const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 26),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],

        // --- Movie Cards ---
        if (movies.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 20, 18, 6),
            child: Text(
              'MOVIES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...movies.map((item) {
            final isDownloading = item.status == 'downloading';
            final isCompleted = item.status == 'completed';
            final progress = item.progress.clamp(0.0, 1.0);
            final percentInt = (progress * 100).toInt();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (isCompleted) {
                    _playOffline(context, item);
                  } else {
                    downloadProvider.resumeDownload(item.id);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildThumbnailWidget(
                            item: item,
                            width: 100,
                            height: 60,
                            is16x9: true,
                          ),
                          if (isCompleted)
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white70, width: 1.2),
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),

                      // Movie Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Movie • ${item.formattedSize} • ${item.quality}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDownloading
                                  ? 'Downloading - $percentInt%'
                                  : item.status == 'paused'
                                      ? 'Paused - Tap to resume'
                                      : item.status == 'failed'
                                          ? 'Interrupted - Tap to restart'
                                          : 'Ready to Play',
                              style: TextStyle(
                                color: isDownloading
                                    ? AppTheme.primaryRed
                                    : item.status == 'paused'
                                        ? Colors.amber
                                        : item.status == 'failed'
                                            ? AppTheme.primaryRed
                                            : const Color(0xFF2ECC71),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Trailing action
                      if (_isEditing)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.primaryRed, size: 24),
                          onPressed: () => downloadProvider.deleteDownload(item.id),
                        )
                      else if (isDownloading)
                        CustomPaint(
                          size: const Size(26, 26),
                          painter: _PieProgressPainter(progress: progress),
                        )
                      else if (item.status == 'paused')
                        IconButton(
                          icon: const Icon(Icons.play_circle_filled_rounded, color: Colors.amber, size: 26),
                          onPressed: () => downloadProvider.resumeDownload(item.id),
                        )
                      else
                        const Icon(Icons.check_circle_rounded, color: Colors.white70, size: 24),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  /// Series Detail View: Displays all downloaded episodes for that series grouped by Season
  Widget _buildSeriesDetailView(
    BuildContext context,
    List<DownloadedItem> items,
    DownloadProvider downloadProvider,
  ) {
    // Group episodes by season
    final Map<int, List<DownloadedItem>> seasonGroups = {};
    for (final item in items) {
      final s = item.season;
      seasonGroups.putIfAbsent(s, () => []).add(item);
    }
    final sortedSeasons = seasonGroups.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        ...sortedSeasons.map((seasonNum) {
          final seasonItems = seasonGroups[seasonNum]!;
          // Sort by episode number
          seasonItems.sort((a, b) => a.episode.compareTo(b.episode));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Season Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Text(
                  'Season $seasonNum',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Episode Items
              ...seasonItems.map((item) {
                return _buildSeriesEpisodeCard(context, item, downloadProvider);
              }),
            ],
          );
        }),
      ],
    );
  }

  /// Detailed Episode Card: 16:9 Thumbnail, Title, Description Synopsis, Metadata & Offline Play
  Widget _buildSeriesEpisodeCard(
    BuildContext context,
    DownloadedItem item,
    DownloadProvider downloadProvider,
  ) {
    final isDownloading = item.status == 'downloading';
    final isCompleted = item.status == 'completed';
    final progress = item.progress.clamp(0.0, 1.0);
    final percentInt = (progress * 100).toInt();

    final epTitle = item.episodeTitle != null && item.episodeTitle!.isNotEmpty
        ? '${item.episode}. ${item.episodeTitle}'
        : 'Episode ${item.episode}';

    final runtimeStr = item.runtime > 0 ? '${item.runtime}m • ' : '';
    final metaText = isDownloading
        ? 'Downloading $percentInt%'
        : item.status == 'paused'
            ? 'Paused • Tap to resume'
            : item.status == 'failed'
                ? 'Interrupted • Tap to retry'
                : '$runtimeStr${item.formattedSize} • ${item.quality}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 16:9 Episode Thumbnail with Play Overlay
                GestureDetector(
                  onTap: () {
                    if (isCompleted) {
                      _playOffline(context, item);
                    } else {
                      downloadProvider.resumeDownload(item.id);
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildThumbnailWidget(
                        item: item,
                        width: 124,
                        height: 70,
                        is16x9: true,
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                        child: Center(
                          child: Icon(
                            isCompleted
                                ? Icons.play_arrow_rounded
                                : item.status == 'paused'
                                    ? Icons.refresh_rounded
                                    : Icons.file_download_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 14),

                // Title & Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        epTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        metaText,
                        style: TextStyle(
                          color: isDownloading
                              ? AppTheme.primaryRed
                              : item.status == 'paused'
                                  ? Colors.amber
                                  : item.status == 'failed'
                                      ? AppTheme.primaryRed
                                      : Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Trailing Action Button
                if (_isEditing)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.primaryRed, size: 24),
                    onPressed: () => downloadProvider.deleteDownload(item.id),
                  )
                else if (isDownloading)
                  CustomPaint(
                    size: const Size(26, 26),
                    painter: _PieProgressPainter(progress: progress),
                  )
                else if (item.status == 'paused')
                  IconButton(
                    icon: const Icon(Icons.play_circle_filled_rounded, color: Colors.amber, size: 26),
                    onPressed: () => downloadProvider.resumeDownload(item.id),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white70, size: 26),
                    onPressed: () => _playOffline(context, item),
                  ),
              ],
            ),

            // Episode Synopsis / Description
            if (item.episodeDescription != null && item.episodeDescription!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                item.episodeDescription!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Large Circular Download Badge with Downward Arrow & Curved Baseline
class _NetflixDownloadBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Dark gray circle background
    final circlePaint = Paint()
      ..color = const Color(0xFF424248)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    // 2. Black arrow inside
    final arrowPaint = Paint()
      ..color = const Color(0xFF141416)
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Arrow vertical stem
    canvas.drawLine(
      Offset(center.dx, center.dy - 38),
      Offset(center.dx, center.dy + 16),
      arrowPaint,
    );

    // Arrow head (v-shape)
    final arrowHeadPath = Path();
    arrowHeadPath.moveTo(center.dx - 22, center.dy - 6);
    arrowHeadPath.lineTo(center.dx, center.dy + 18);
    arrowHeadPath.lineTo(center.dx + 22, center.dy - 6);
    canvas.drawPath(arrowHeadPath, arrowPaint);

    // 3. Curved smile/tray baseline under the arrow
    final trayPaint = Paint()
      ..color = const Color(0xFF141416)
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final trayPath = Path();
    trayPath.moveTo(center.dx - 54, center.dy + 38);
    trayPath.quadraticBezierTo(
      center.dx,
      center.dy + 34,
      center.dx + 54,
      center.dy + 38,
    );
    canvas.drawPath(trayPath, trayPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Circular Pie Progress Indicator
class _PieProgressPainter extends CustomPainter {
  final double progress;

  _PieProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer circle outline
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, outlinePaint);

    // Filled pie sector
    final fillPaint = Paint()
      ..color = AppTheme.primaryRed
      ..style = PaintingStyle.fill;

    final sweepAngle = (progress.clamp(0.0, 1.0)) * 2 * 3.1415926535;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      -3.1415926535 / 2, // start at top
      sweepAngle,
      true, // draw pie sector to center
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
