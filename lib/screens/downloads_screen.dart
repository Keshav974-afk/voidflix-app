import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/theme_constants.dart';
import '../models/downloaded_item.dart';
import '../providers/download_provider.dart';
import 'player_screen.dart';

/// Downloads Screen matching official Netflix design from Screenshots 2 & 3.
///
/// Features:
/// 1. Top bar: Back arrow with Series Title or 'Downloads', and Edit pencil button.
/// 2. Subheader: Clean "Smart Downloads" with settings gear icon.
/// 3. Empty State (Screenshot 2):
///    - Large circular download graphic with downward arrow and curved tray baseline.
///    - "Movies and shows that you download appear here."
///    - Crisp white "View More Episodes" button.
/// 4. Active Downloads (Screenshot 3):
///    - Grouped by Season (e.g. "Season 1").
///    - 16:9 landscape thumbnail with translucent Play circle overlay.
///    - Title (e.g. "1. Pilot"), "Downloading - XX%" / "Ready to Play".
///    - Circular pie progress indicator on the right.
///    - Dark charcoal "View More Episodes" button at bottom.
class DownloadsScreen extends StatefulWidget {
  final String? seriesTitle;

  const DownloadsScreen({super.key, this.seriesTitle});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _isEditing = false;

  void _playOffline(BuildContext context, DownloadedItem item) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => PlayerScreen(
          mediaId: item.mediaId,
          mediaTitle: item.mediaType == 'tv' && item.episodeTitle != null
              ? '${item.title}: S${item.season}E${item.episode} "${item.episodeTitle}"'
              : item.title,
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

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final allItems = downloadProvider.items;

    // Filter by series if seriesTitle is provided
    final items = widget.seriesTitle != null && widget.seriesTitle!.isNotEmpty
        ? allItems.where((i) => i.title.toLowerCase() == widget.seriesTitle!.toLowerCase()).toList()
        : allItems;

    final displayTitle = widget.seriesTitle ?? (items.isNotEmpty ? items.first.title : 'Downloads');

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
          : _buildActiveState(context, items, downloadProvider),
    );
  }

  /// Empty State matching Screenshot 2
  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        // Smart Downloads Subheader (Screenshot 2)
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

        // Large Circular Download Badge (Screenshot 2)
        CustomPaint(
          size: const Size(180, 180),
          painter: _NetflixDownloadBadgePainter(),
        ),

        const SizedBox(height: 28),

        // Subtitle text (Screenshot 2)
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

        // Crisp White Button: "View More Episodes" (Screenshot 2)
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
              'View More Episodes',
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

  /// Active Downloads List matching Screenshot 3
  Widget _buildActiveState(
    BuildContext context,
    List<DownloadedItem> items,
    DownloadProvider downloadProvider,
  ) {
    // Group items by season
    final Map<int, List<DownloadedItem>> seasonGroups = {};
    for (final item in items) {
      final s = item.season;
      seasonGroups.putIfAbsent(s, () => []).add(item);
    }
    final sortedSeasons = seasonGroups.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        // Smart Downloads Subheader (Screenshot 3)
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

        // Season groups
        ...sortedSeasons.map((seasonNum) {
          final seasonItems = seasonGroups[seasonNum]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Season Header (Screenshot 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                return _buildEpisodeItem(context, item, downloadProvider);
              }),
            ],
          );
        }),

        const SizedBox(height: 36),

        // Dark Charcoal Button: "View More Episodes" (Screenshot 3)
        Center(
          child: SizedBox(
            width: 210,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'View More Episodes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Episode Item matching Screenshot 3
  Widget _buildEpisodeItem(
    BuildContext context,
    DownloadedItem item,
    DownloadProvider downloadProvider,
  ) {
    final isDownloading = item.status == 'downloading';
    final isCompleted = item.status == 'completed';
    final progress = item.progress.clamp(0.0, 1.0);
    final percentInt = (progress * 100).toInt();

    final episodeTitle = item.episodeTitle != null && item.episodeTitle!.isNotEmpty
        ? '${item.episode}. ${item.episodeTitle}'
        : item.title;

    final imagePath = item.backdropPath ?? item.posterPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          if (isCompleted) {
            _playOffline(context, item);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 16:9 Landscape Thumbnail with Play Overlay (Screenshot 3)
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 120,
                    height: 68,
                    color: const Color(0xFF222228),
                    child: imagePath != null
                        ? CachedNetworkImage(
                            imageUrl: imagePath,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: const Color(0xFF222228)),
                            errorWidget: (context, url, error) => const Icon(Icons.movie, color: Colors.white24),
                          )
                        : const Icon(Icons.movie, color: Colors.white24),
                  ),
                ),
                // Semi-transparent circle overlay with play triangle
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white60, width: 1.5),
                  ),
                  child: const Center(
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 14),

            // Middle Info Column (Screenshot 3)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episodeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDownloading ? 'Downloading - $percentInt%' : item.formattedSize,
                    style: TextStyle(
                      color: isDownloading ? Colors.white70 : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ready to Play',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Right Progress Pie Indicator (Screenshot 3)
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
            else
              const Icon(Icons.check_circle_rounded, color: Colors.white70, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Large Circular Download Badge with Downward Arrow & Curved Baseline (Screenshot 2)
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

/// Circular Pie Progress Indicator (Screenshot 3)
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
      ..color = Colors.white
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
