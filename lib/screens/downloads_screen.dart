import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/downloaded_item.dart';
import '../providers/download_provider.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
    final items = downloadProvider.items;

    int totalBytes = 0;
    for (final i in items) {
      totalBytes += i.fileSizeBytes;
    }
    final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Downloads',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$totalMb MB Used',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? _buildEmptyState(context)
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // Smart Downloads Header
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: AppTheme.primaryRed, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Downloads',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Watch anywhere offline with no internet needed.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Downloaded Items List
                ...items.map((item) {
                  return Dismissible(
                    key: Key(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      color: AppTheme.primaryRed,
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                    ),
                    onDismissed: (_) {
                      downloadProvider.deleteDownload(item.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Removed ${item.title} from downloads')),
                      );
                    },
                    child: InkWell(
                      onTap: () {
                        if (item.status == 'completed') {
                          _playOffline(context, item);
                        } else if (item.status == 'failed') {
                          _showFailedOptionsSheet(context, item, downloadProvider);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.white10)),
                        ),
                        child: Row(
                          children: [
                            // 16:9 Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 110,
                                    height: 64,
                                    child: item.backdropPath != null || item.posterPath != null
                                        ? CachedNetworkImage(
                                            imageUrl: ApiService.getImageUrl(
                                              item.backdropPath ?? item.posterPath,
                                              size: 'w300',
                                            ),
                                            fit: BoxFit.cover,
                                            errorWidget: (context, url, error) =>
                                                Container(color: const Color(0xFF24242A)),
                                          )
                                        : Container(color: const Color(0xFF24242A)),
                                  ),
                                  if (item.status == 'completed')
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  if (item.status == 'downloading')
                                    Container(
                                      width: 110,
                                      height: 64,
                                      color: Colors.black54,
                                      child: Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            value: item.progress > 0 ? item.progress : null,
                                            color: AppTheme.primaryRed,
                                            strokeWidth: 3,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 14),

                            // Title & Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (item.mediaType == 'tv')
                                    Text(
                                      'S${item.season}:E${item.episode} ${item.episodeTitle ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (item.status == 'completed') ...[
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.greenAccent,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${item.formattedSize} • Offline Ready',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ] else if (item.status == 'downloading') ...[
                                        const Icon(
                                          Icons.downloading_rounded,
                                          color: AppTheme.primaryRed,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${(item.progress * 100).toInt()}% • Downloading...',
                                          style: const TextStyle(
                                            color: AppTheme.primaryRed,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ] else ...[
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          color: Colors.orangeAccent,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Failed • Tap retry',
                                          style: TextStyle(
                                            color: Colors.orangeAccent,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Actions
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white60),
                              color: const Color(0xFF1E1E24),
                              onSelected: (val) {
                                if (val == 'play' && item.status == 'completed') {
                                  _playOffline(context, item);
                                } else if (val == 'delete') {
                                  downloadProvider.deleteDownload(item.id);
                                } else if (val == 'retry') {
                                  downloadProvider.startDownload(
                                    mediaId: item.mediaId,
                                    title: item.title,
                                    mediaType: item.mediaType,
                                    season: item.season,
                                    episode: item.episode,
                                    episodeTitle: item.episodeTitle,
                                    posterPath: item.posterPath,
                                    backdropPath: item.backdropPath,
                                  );
                                } else if (val == 'web_download') {
                                  DownloadProvider.launchWebDownload(
                                    mediaType: item.mediaType,
                                    mediaId: item.mediaId,
                                    season: item.season,
                                    episode: item.episode,
                                  );
                                }
                              },
                              itemBuilder: (ctx) => [
                                if (item.status == 'completed')
                                  const PopupMenuItem(
                                    value: 'play',
                                    child: Row(
                                      children: [
                                        Icon(Icons.play_arrow, color: Colors.white70, size: 20),
                                        SizedBox(width: 8),
                                        Text('Play Offline', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                if (item.status == 'failed') ...[
                                  const PopupMenuItem(
                                    value: 'retry',
                                    child: Row(
                                      children: [
                                        Icon(Icons.refresh, color: Colors.white70, size: 20),
                                        SizedBox(width: 8),
                                        Text('Retry Download', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'web_download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.open_in_browser, color: Colors.lightBlueAccent, size: 20),
                                        SizedBox(width: 8),
                                        Text('Open Web Download', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ],
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: AppTheme.primaryRed, size: 20),
                                      SizedBox(width: 8),
                                      Text('Delete Download', style: TextStyle(color: AppTheme.primaryRed)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  void _showFailedOptionsSheet(
    BuildContext context,
    DownloadedItem item,
    DownloadProvider downloadProvider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Direct streaming server was busy or blocked chunk requests. You can retry in-app or open the web resolver to download directly in your browser.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF282832),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                ),
                title: const Text('Retry In-App Download', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Attempt multi-source stream download again', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  downloadProvider.startDownload(
                    mediaId: item.mediaId,
                    title: item.title,
                    mediaType: item.mediaType,
                    season: item.season,
                    episode: item.episode,
                    episodeTitle: item.episodeTitle,
                    posterPath: item.posterPath,
                    backdropPath: item.backdropPath,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF282832),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.open_in_browser_rounded, color: Colors.lightBlueAccent, size: 20),
                ),
                title: const Text('Open Web Download Page', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Download .mp4 file directly using MovieBox/Voidflix web resolver', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  DownloadProvider.launchWebDownload(
                    mediaType: item.mediaType,
                    mediaId: item.mediaId,
                    season: item.season,
                    episode: item.episode,
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF282832),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: AppTheme.primaryRed, size: 20),
                ),
                title: const Text('Remove from Downloads', style: TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  downloadProvider.deleteDownload(item.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E26),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 1.5),
              ),
              child: const Center(
                child: Icon(
                  Icons.file_download_outlined,
                  color: AppTheme.primaryRed,
                  size: 46,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Never be without Voidflix',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Download shows and movies so you can watch offline wherever you go.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text(
                'Find Something to Download',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
