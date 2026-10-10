import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../models/downloaded_item.dart';
import '../providers/download_provider.dart';
import '../providers/history_provider.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import '../widgets/top10_row.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategoryFilter = 'All'; // 'All', 'TV Shows', 'Movies'
  bool _isOffline = false;
  String? _lastProfileId;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      final hasNet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && _isOffline != !hasNet) {
        setState(() => _isOffline = !hasNet);
      }
    } catch (_) {
      if (mounted && !_isOffline) {
        setState(() => _isOffline = true);
      }
    }
  }

  void _playOffline(DownloadedItem item) {
    if (item.localFilePath.isEmpty) return;
    final cleanTitle = DownloadsScreen.sanitizeTitle(item.title);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.mediaId,
          mediaTitle: cleanTitle,
          mediaType: item.mediaType,
          season: item.season,
          episode: item.episode,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          localFilePath: item.localFilePath,
          localSubtitlePath: item.localSubtitlePath,
        ),
      ),
    );
  }

  void _showCategoriesPicker(BuildContext context, MediaProvider mediaProvider, {bool isKids = false}) {
    final categories = isKids
        ? [
            {'name': 'All Kids Content', 'type': 'all', 'id': 0},
            {'name': 'Animated Movies', 'type': 'movie', 'id': 16},
            {'name': 'Cartoons & Kids TV', 'type': 'tv', 'id': 10762},
            {'name': 'Family Movie Classics', 'type': 'movie', 'id': 10751},
            {'name': 'Laughs & Joyful Fun', 'type': 'movie', 'id': 35},
          ]
        : [
            {'name': 'All', 'type': 'all', 'id': 0},
            {'name': 'Action & Adventure', 'type': 'movie', 'id': 28},
            {'name': 'Anime & Animation', 'type': 'tv', 'id': 16},
            {'name': 'Comedy Hits', 'type': 'movie', 'id': 35},
            {'name': 'Crime & Mystery', 'type': 'tv', 'id': 80},
            {'name': 'Critically Acclaimed', 'type': 'movie', 'id': 18},
            {'name': 'Documentaries', 'type': 'movie', 'id': 99},
            {'name': 'Horror & Paranormal', 'type': 'movie', 'id': 27},
            {'name': 'K-Drama & Asian Series', 'type': 'tv', 'id': 10759},
            {'name': 'Romance & Heartfelt', 'type': 'movie', 'id': 10749},
            {'name': 'Sci-Fi & Fantasy', 'type': 'movie', 'id': 878},
            {'name': 'Thrillers & Mystery', 'type': 'movie', 'id': 53},
            {'name': 'Family & Kids', 'type': 'movie', 'id': 10751},
          ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Categories & Genres',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),
                const Divider(color: AppTheme.border),
                Expanded(
                  child: ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (c, idx) {
                      final item = categories[idx];
                      final name = item['name'] as String;
                      final type = item['type'] as String;
                      final id = item['id'] as int;

                      return ListTile(
                        title: Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (id != 0) {
                            mediaProvider.fetchByGenre(type, id);
                          }
                          setState(() {
                            if (name == 'All') {
                              _selectedCategoryFilter = 'All';
                            } else if (type == 'tv') {
                              _selectedCategoryFilter = 'TV Shows';
                            } else {
                              _selectedCategoryFilter = 'Movies';
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadProvider = context.watch<DownloadProvider>();
    final completedDownloads = downloadProvider.completedItems;
    final profileProv = context.watch<ProfileProvider>();
    final activeProfile = profileProv.activeProfile;
    final isKids = activeProfile.isKids;

    if (_lastProfileId != activeProfile.id) {
      _lastProfileId = activeProfile.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final historyProv = context.read<HistoryProvider>();
          final watchedIds = historyProv.history.map((h) => h.id).toList();
          final latest = historyProv.history.isNotEmpty ? historyProv.history.first : null;

          final mediaProv = context.read<MediaProvider>();
          mediaProv.fetchHomeData(profile: activeProfile);
          mediaProv.fetchPersonalizedForProfile(
            activeProfile,
            watchedIds: watchedIds,
            latestWatchedId: latest?.id,
            latestWatchedTitle: latest?.title,
            latestWatchedType: latest?.mediaType,
          );
        }
      });
    }

    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        final isOffline = _isOffline || (mediaProvider.error != null && mediaProvider.trending.isEmpty);

        if (mediaProvider.isLoadingHome && mediaProvider.trending.isEmpty && !isOffline) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryRed),
          );
        }

        if (isOffline && mediaProvider.trending.isEmpty) {
          return _buildOfflineView(context, completedDownloads, mediaProvider);
        }

        return RefreshIndicator(
          color: AppTheme.primaryRed,
          backgroundColor: AppTheme.surfaceVariant,
          onRefresh: () async {
            _checkConnectivity();
            final historyProv = context.read<HistoryProvider>();
            final watchedIds = historyProv.history.map((h) => h.id).toList();
            final latest = historyProv.history.isNotEmpty ? historyProv.history.first : null;

            await Future.wait([
              mediaProvider.fetchHomeData(profile: activeProfile),
              mediaProvider.fetchPersonalizedForProfile(
                activeProfile,
                watchedIds: watchedIds,
                latestWatchedId: latest?.id,
                latestWatchedTitle: latest?.title,
                latestWatchedType: latest?.mediaType,
                force: true,
              ),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Netflix Top Category Pills Row
                Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      _buildFilterChip('All'),
                      const SizedBox(width: 8),
                      _buildFilterChip('TV Shows'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Movies'),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _showCategoriesPicker(context, mediaProvider, isKids: isKids),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Categories',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Offline Notice Banner if cached feed is active but network disconnected
                if (_isOffline && completedDownloads.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Offline Mode",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                "${completedDownloads.length} downloaded title${completedDownloads.length > 1 ? 's' : ''} available to play",
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: const Text(
                            'Downloads',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (isKids) ...[
                  // ==========================================
                  // KIDS PROFILE: 100% G/PG SAFE RAILS
                  // ==========================================
                  if (mediaProvider.kidsAnimated.isNotEmpty)
                    HeroBanner(items: mediaProvider.kidsAnimated)
                  else if (mediaProvider.trending.isNotEmpty)
                    HeroBanner(items: mediaProvider.trending),

                  const SizedBox(height: 6),

                  const ContinueWatchingRow(),

                  if (mediaProvider.kidsAnimated.isNotEmpty)
                    Top10Row(
                      title: 'Top 10 Kids Movies Today',
                      items: mediaProvider.kidsAnimated,
                      forceType: 'movie',
                    ),

                  if (mediaProvider.kidsCartoons.isNotEmpty)
                    MediaRow(
                      title: 'Cartoons & Fun TV Series',
                      items: mediaProvider.kidsCartoons,
                      forceType: 'tv',
                    ),

                  if (mediaProvider.kidsFamily.isNotEmpty)
                    MediaRow(
                      title: 'Family Movie Night',
                      items: mediaProvider.kidsFamily,
                      forceType: 'movie',
                    ),

                  if (mediaProvider.comedyMovies.isNotEmpty)
                    MediaRow(
                      title: 'Laughs & Joyful Adventures',
                      items: mediaProvider.comedyMovies,
                      forceType: 'movie',
                    ),

                  if (mediaProvider.anime.isNotEmpty)
                    MediaRow(
                      title: 'Kids Anime & Animation Favorites',
                      items: mediaProvider.anime,
                      forceType: 'tv',
                    ),
                ] else ...[
                  // ==========================================
                  // STANDARD PROFILE: FULL RAILS & RECOMMENDATIONS
                  // ==========================================
                  if (mediaProvider.trending.isNotEmpty && _selectedCategoryFilter == 'All')
                    HeroBanner(items: mediaProvider.trending)
                  else if (mediaProvider.trendingTV.isNotEmpty && _selectedCategoryFilter == 'TV Shows')
                    HeroBanner(items: mediaProvider.trendingTV)
                  else if (mediaProvider.popularMovies.isNotEmpty && _selectedCategoryFilter == 'Movies')
                    HeroBanner(items: mediaProvider.popularMovies),

                  const SizedBox(height: 6),

                  // Continue Watching (isolated per active profile!)
                  const ContinueWatchingRow(),

                  // Personalized Recommendations Curated For Active Profile
                  if (mediaProvider.personalizedSections.isNotEmpty) ...[
                    for (final sec in mediaProvider.personalizedSections)
                      if (_selectedCategoryFilter == 'All' ||
                          (_selectedCategoryFilter == 'TV Shows' && sec.forceType == 'tv') ||
                          (_selectedCategoryFilter == 'Movies' && sec.forceType == 'movie'))
                        MediaRow(
                          title: sec.title,
                          items: sec.items,
                          forceType: sec.forceType,
                        ),
                  ],

                  // "Because You Watched" Row
                  if (mediaProvider.becauseYouWatched.isNotEmpty && (_selectedCategoryFilter == 'All' || _selectedCategoryFilter == 'Movies'))
                    MediaRow(
                      title: 'Because You Watched ${mediaProvider.becauseYouWatchedTitle}',
                      items: mediaProvider.becauseYouWatched,
                    ),

                  // TV Shows Category Sections
                  if (_selectedCategoryFilter == 'All' || _selectedCategoryFilter == 'TV Shows') ...[
                    if (_selectedCategoryFilter == 'All')
                      MediaRow(
                        title: 'Trending Now',
                        items: mediaProvider.trending.skip(1).toList(),
                      ),

                    Top10Row(
                      title: 'Top 10 TV Shows Today',
                      items: mediaProvider.popularTV,
                      forceType: 'tv',
                    ),

                    MediaRow(
                      title: 'Binge-Worthy TV Series',
                      items: mediaProvider.trendingTV,
                      forceType: 'tv',
                    ),

                    MediaRow(
                      title: 'Popular Shows on Voidflix',
                      items: mediaProvider.popularTV,
                      forceType: 'tv',
                    ),

                    if (mediaProvider.crimeTV.isNotEmpty)
                      MediaRow(
                        title: 'Crime & Investigative TV Series',
                        items: mediaProvider.crimeTV,
                        forceType: 'tv',
                      ),

                    MediaRow(
                      title: 'Japanese Anime Spotlight',
                      items: mediaProvider.anime,
                      forceType: 'tv',
                    ),

                    MediaRow(
                      title: 'Spotlight K-Dramas & Asian Series',
                      items: mediaProvider.asianDrama,
                      forceType: 'tv',
                    ),

                    MediaRow(
                      title: 'Highest Rated TV Masterpieces',
                      items: mediaProvider.topRatedTV,
                      forceType: 'tv',
                    ),
                  ],

                  // Movies Category Sections
                  if (_selectedCategoryFilter == 'All' || _selectedCategoryFilter == 'Movies') ...[
                    Top10Row(
                      title: 'Top 10 Movies Today',
                      items: mediaProvider.popularMovies,
                      forceType: 'movie',
                    ),

                    if (mediaProvider.nowPlayingMovies.isNotEmpty)
                      MediaRow(
                        title: 'Now Playing in Theaters',
                        items: mediaProvider.nowPlayingMovies,
                        forceType: 'movie',
                      ),

                    MediaRow(
                      title: 'Blockbuster Action & Adventure',
                      items: mediaProvider.actionMovies.isNotEmpty
                          ? mediaProvider.actionMovies
                          : mediaProvider.popularMovies,
                      forceType: 'movie',
                    ),

                    if (mediaProvider.romanceMovies.isNotEmpty)
                      MediaRow(
                        title: 'Romance & Heartfelt Stories',
                        items: mediaProvider.romanceMovies,
                        forceType: 'movie',
                      ),

                    MediaRow(
                      title: 'Laugh-Out-Loud Comedies',
                      items: mediaProvider.comedyMovies,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Sci-Fi & Fantasy Epics',
                      items: mediaProvider.sciFiMovies,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Chilling Horror & Paranormal',
                      items: mediaProvider.horrorMovies,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Edge-of-Your-Seat Thrillers',
                      items: mediaProvider.thrillerMovies,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Critically Acclaimed Movies',
                      items: mediaProvider.topRatedMovies,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Fascinating Documentaries',
                      items: mediaProvider.documentaries,
                      forceType: 'movie',
                    ),

                    MediaRow(
                      title: 'Coming Soon to Voidflix',
                      items: mediaProvider.upcomingMovies,
                      forceType: 'movie',
                    ),
                  ],
                ],

                const SizedBox(height: 96),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedCategoryFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCategoryFilter = label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineView(BuildContext context, List<DownloadedItem> downloads, MediaProvider mediaProvider) {
    if (downloads.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text(
            'Voidflix',
            style: TextStyle(
              color: AppTheme.primaryRed,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 1.5,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Mature Netflix-style Offline Hero Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFF282830),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Offline Mode",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "You can watch any of your downloaded titles without internet",
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: ElevatedButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              child: const Text(
                                'Manage Downloads',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 38,
                          child: OutlinedButton(
                            onPressed: () {
                              _checkConnectivity();
                              mediaProvider.fetchHomeData();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('Retry', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Available Offline',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${downloads.length} title${downloads.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...downloads.map((item) {
                final cleanTitle = DownloadsScreen.sanitizeTitle(item.title);
                final isTv = item.mediaType == 'tv';
                final episodeInfo = isTv
                    ? 'S${item.season}E${item.episode}${item.episodeTitle != null ? ' • ${item.episodeTitle}' : ''}'
                    : (item.quality.isNotEmpty ? '${item.quality} • Movie' : 'Movie');
                final hasThumb = item.localThumbnailPath != null && File(item.localThumbnailPath!).existsSync();
                final sizeMb = item.fileSizeBytes > 0
                    ? '${(item.fileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141418),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _playOffline(item),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          // 16:9 Thumbnail preview matching Downloads screen
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 104,
                              height: 58,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (hasThumb)
                                    Image.file(File(item.localThumbnailPath!), fit: BoxFit.cover)
                                  else if (item.posterPath != null)
                                    Image.network(
                                      'https://image.tmdb.org/t/p/w300${item.posterPath}',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF222228),
                                        child: const Icon(Icons.movie, color: Colors.white24),
                                      ),
                                    )
                                  else
                                    Container(
                                      color: const Color(0xFF222228),
                                      child: const Icon(Icons.movie, color: Colors.white24),
                                    ),
                                  // Translucent Play Icon Overlay
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    child: Center(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white38, width: 1.2),
                                        ),
                                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Title & Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cleanTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  episodeInfo,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (sizeMb.isNotEmpty)
                                      Text(
                                        sizeMb,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    if (sizeMb.isNotEmpty && item.localSubtitlePath != null)
                                      const Text('  •  ', style: TextStyle(color: Colors.white24, fontSize: 10)),
                                    if (item.localSubtitlePath != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(2),
                                          border: Border.all(color: Colors.white30, width: 0.8),
                                        ),
                                        child: const Text(
                                          'CC',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.play_circle_outline, color: Colors.white70, size: 28),
                            onPressed: () => _playOffline(item),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    _checkConnectivity();
                    mediaProvider.fetchHomeData();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white54, size: 16),
                  label: const Text('Tap to check internet connection', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Voidflix',
          style: TextStyle(
            color: AppTheme.primaryRed,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            CustomPaint(
              size: const Size(180, 180),
              painter: _OfflineNoConnectionBadgePainter(),
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "You're Offline",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Connect to the internet to stream, or watch titles you have downloaded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 34),
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
                  _checkConnectivity();
                  mediaProvider.fetchHomeData();
                },
                child: const Text(
                  'Check Connection',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 210,
              height: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                ),
                child: const Text(
                  'Go to Downloads',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const Spacer(flex: 4),
          ],
        ),
      ),
    );
  }
}

/// Circular Badge for Offline State (Matching _NetflixDownloadBadgePainter design language)
class _OfflineNoConnectionBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Dark charcoal circle background (exact match to Netflix badge)
    final circlePaint = Paint()
      ..color = const Color(0xFF424248)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, circlePaint);

    // 2. Dark inner glyph paint
    final glyphPaint = Paint()
      ..color = const Color(0xFF141416)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF141416)
      ..style = PaintingStyle.fill;

    // Base point of wifi waves
    final waveCenter = Offset(center.dx, center.dy + 22);

    // Center origin dot
    canvas.drawCircle(waveCenter, 4.5, dotPaint);

    // Inner wave arc
    final innerRect = Rect.fromCircle(center: waveCenter, radius: 26);
    canvas.drawArc(innerRect, -3.14159 * 0.75, 3.14159 * 0.5, false, glyphPaint);

    // Outer wave arc
    final outerRect = Rect.fromCircle(center: waveCenter, radius: 48);
    canvas.drawArc(outerRect, -3.14159 * 0.75, 3.14159 * 0.5, false, glyphPaint);

    // Diagonal clean slash bar
    final slashPaint = Paint()
      ..color = const Color(0xFF141416)
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(center.dx - 32, center.dy - 30),
      Offset(center.dx + 32, center.dy + 34),
      slashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
