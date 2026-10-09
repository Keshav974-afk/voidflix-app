import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import '../models/watch_progress.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../screens/player_screen.dart';
import 'detail_modal.dart';

class ContinueWatchingRow extends StatelessWidget {
  const ContinueWatchingRow({super.key});

  void _showMoreOptions(
    BuildContext context, {
    required int id,
    required String title,
    required String mediaType,
    int season = 1,
    int episode = 1,
    String? posterPath,
    String? backdropPath,
    required VoidCallback onRemove,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(color: AppTheme.border),

              // Play
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.white),
                title: const Text('Play', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        mediaId: id,
                        mediaTitle: title,
                        mediaType: mediaType,
                        season: season,
                        episode: episode,
                        posterPath: posterPath,
                        backdropPath: backdropPath,
                      ),
                    ),
                  );
                },
              ),

              // Episodes & Info
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white),
                title: const Text('Episodes & Info', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  final item = MediaItem(
                    id: id,
                    title: title,
                    overview: '',
                    voteAverage: 8.0,
                    mediaType: mediaType,
                    posterPath: posterPath,
                    backdropPath: backdropPath,
                  );
                  DetailModal.show(context, item);
                },
              ),

              // Download
              ListTile(
                leading: const Icon(Icons.file_download_outlined, color: Colors.white),
                title: const Text('Download', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Starting download for $title...')),
                  );
                },
              ),

              // Share
              ListTile(
                leading: const Icon(Icons.share, color: Colors.white),
                title: const Text('Share', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sharing $title...')),
                  );
                },
              ),

              // Remove from Continue Watching
              ListTile(
                leading: const Icon(Icons.close, color: AppTheme.primaryRed),
                title: const Text(
                  'Remove From Continue Watching',
                  style: TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onRemove();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyProvider = context.watch<HistoryProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final activeProfileName = profileProvider.activeProfile.name;

    final realHistory = historyProvider.history;

    // Only show Continue Watching when the user has actual watch history
    if (realHistory.isEmpty) return const SizedBox.shrink();

    final List<WatchProgress> displayItems = realHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header matching Netflix: "Continue Watching for {username}"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Continue Watching for $activeProfileName',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: AppTheme.textPrimary,
            ),
          ),
        ),

        // Horizontal Portrait Cards Row matching Netflix
        SizedBox(
          height: 204,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            separatorBuilder: (c, i) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final raw = displayItems[index];

              final int id = raw.id;
              final String title = raw.title;
              final String? posterPath = raw.posterPath;
              final String? backdropPath = raw.backdropPath;
              final String mediaType = raw.mediaType;
              final int season = raw.season;
              final int episode = raw.episode;
              final double progress = raw.progress > 0 ? raw.progress : 0.05;

              final imageUrl = ApiConstants.getImageUrl(posterPath ?? backdropPath, size: 'w342');

              final mediaItem = MediaItem(
                id: id,
                title: title,
                overview: '',
                voteAverage: 8.0,
                mediaType: mediaType,
                posterPath: posterPath,
                backdropPath: backdropPath,
              );

              return Container(
                width: 118,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF1E1E26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Top: Poster Artwork with Centered Play Button & Progress Bar
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                mediaId: id,
                                mediaTitle: title,
                                mediaType: mediaType,
                                season: season,
                                episode: episode,
                                posterPath: posterPath,
                                backdropPath: backdropPath,
                              ),
                            ),
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Poster image
                            imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (c, u) => Container(color: AppTheme.surfaceVariant),
                                    errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                                  )
                                : Container(color: AppTheme.surfaceVariant),

                            // Translucent scrim
                            Container(
                              color: Colors.black.withValues(alpha: 0.2),
                            ),

                            // Centered circular play button overlay (Screenshot 2)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.55),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),

                            // Thin red progress indicator at bottom of poster (Screenshot 2)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.05, 1.0),
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
                                minHeight: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Control Bar with Info (ⓘ) and More (⫶) (Screenshot 2)
                    Container(
                      height: 38,
                      color: const Color(0xFF1E1E26),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Info Icon Button
                          IconButton(
                            icon: const Icon(
                              Icons.info_outline,
                              color: Colors.white70,
                              size: 19,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Info',
                            onPressed: () => DetailModal.show(context, mediaItem),
                          ),

                          // Three dots More Options Button
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white70,
                              size: 19,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'More',
                            onPressed: () {
                              _showMoreOptions(
                                context,
                                id: id,
                                title: title,
                                mediaType: mediaType,
                                season: season,
                                episode: episode,
                                posterPath: posterPath,
                                backdropPath: backdropPath,
                                onRemove: () {
                                  historyProvider.removeProgress(id);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
