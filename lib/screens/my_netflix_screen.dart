import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import '../providers/history_provider.dart';
import '../providers/media_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/detail_modal.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_switcher_sheet.dart';
import 'player_screen.dart';
import 'watchlist_screen.dart';

class MyVoidflixScreen extends StatelessWidget {
  const MyVoidflixScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final historyProvider = context.watch<HistoryProvider>();
    final watchlistProvider = context.watch<WatchlistProvider>();
    final mediaProvider = context.watch<MediaProvider>();
    final notifProvider = context.watch<NotificationProvider>();

    final activeProfile = profileProvider.activeProfile;
    final historyItems = historyProvider.history;
    final watchlistItems = watchlistProvider.watchlist;
    final likedItems = mediaProvider.trending.take(6).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: () => ProfileSwitcherSheet.show(context),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatarTile.fromProfile(
                profile: activeProfile,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                activeProfile.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 22),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 24),
            tooltip: 'Downloads',
            onPressed: () {},
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                tooltip: 'Notifications',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const FractionallySizedBox(
                      heightFactor: 0.75,
                      child: NotificationsSheet(),
                    ),
                  );
                },
              ),
              if (notifProvider.unreadCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${notifProvider.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 90),
        children: [
          // 1. Downloads Box (Screenshot 5)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16161E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.file_download_outlined, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Downloads',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Movies and shows that you download appear here.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 2. Continue Watching (Screenshot 5)
          if (historyItems.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Continue Watching',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 205,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: historyItems.length,
                separatorBuilder: (c, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final item = historyItems[idx];
                  return SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster Artwork Card with Centered Play Button
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerScreen(
                                  mediaId: item.id,
                                  mediaTitle: item.title,
                                  mediaType: item.mediaType,
                                  season: item.season,
                                  episode: item.episode,
                                  posterPath: item.posterPath,
                                  backdropPath: item.backdropPath,
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: ApiService.getImageUrl(item.posterPath ?? item.backdropPath, size: 'w300'),
                                    fit: BoxFit.cover,
                                    errorWidget: (c, u, e) => Container(color: Colors.grey[900]),
                                  ),
                                  // Dark translucent scrim
                                  Container(color: Colors.black.withValues(alpha: 0.3)),
                                  // Centered circular play button
                                  Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white70, width: 1.5),
                                      ),
                                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                    ),
                                  ),
                                  // Red progress bar at bottom
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: LinearProgressIndicator(
                                      value: item.progress.clamp(0.05, 1.0),
                                      backgroundColor: Colors.white24,
                                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
                                      minHeight: 3.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Bottom row under card: (i) info + (:) options (Screenshot 5)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                DetailModal.show(
                                  context,
                                  MediaItem(
                                    id: item.id,
                                    title: item.title,
                                    posterPath: item.posterPath,
                                    backdropPath: item.backdropPath,
                                    overview: '',
                                    voteAverage: 8.0,
                                    releaseDate: '',
                                    mediaType: item.mediaType,
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                historyProvider.removeProgress(item.id);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 3. Shows & Movies You Have Liked (Screenshot 5)
          if (likedItems.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Shows & Movies You have Liked',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 215,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: likedItems.length,
                separatorBuilder: (c, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final item = likedItems[idx];
                  return SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => DetailModal.show(context, item),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: CachedNetworkImage(
                                imageUrl: ApiService.getImageUrl(item.posterPath, size: 'w300'),
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Container(color: Colors.grey[900]),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Share pill button (Screenshot 5)
                        GestureDetector(
                          onTap: () {
                            SharePlus.instance.share(
                              ShareParams(
                                text: 'Check out "${item.title}" on Voidflix!\nhttps://voidflix.org/${item.mediaType}/${item.id}',
                                subject: 'Watch ${item.title} on Voidflix',
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E26),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_outlined, color: Colors.white70, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Share',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 4. My List (Screenshot 5)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My List',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WatchlistScreen()),
                    );
                  },
                  child: const Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (watchlistItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No titles added to your list yet.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 175,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: watchlistItems.length,
                separatorBuilder: (c, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final item = watchlistItems[idx];
                  return GestureDetector(
                    onTap: () => DetailModal.show(context, item),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: CachedNetworkImage(
                          imageUrl: ApiService.getImageUrl(item.posterPath, size: 'w300'),
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => Container(color: Colors.grey[900]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

typedef MyNetflixScreen = MyVoidflixScreen;
