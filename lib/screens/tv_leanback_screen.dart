import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import '../models/media_item.dart';
import '../providers/history_provider.dart';
import '../providers/media_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/tv_focusable.dart';
import 'detail_screen.dart';
import 'live_tv_screen.dart';
import 'movies_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';
import 'watchlist_screen.dart';

class TvLeanbackScreen extends StatefulWidget {
  const TvLeanbackScreen({super.key});

  @override
  State<TvLeanbackScreen> createState() => _TvLeanbackScreenState();
}

class _TvLeanbackScreenState extends State<TvLeanbackScreen> {
  int _activeNavIndex = 1; // 0: Search, 1: Home, 2: Movies, 3: Series, 4: Live TV, 5: My List, 6: Settings, 7: Mobile UI
  bool _isNavRailFocused = false;

  MediaItem? _focusedItem;
  final ScrollController _mainScrollController = ScrollController();

  static const Map<int, String> _genreMap = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
    10759: 'Action & Adventure',
    10762: 'Kids',
    10765: 'Sci-Fi & Fantasy',
  };

  @override
  void initState() {
    super.initState();
    // Enforce landscape orientation for Android TV
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final media = context.read<MediaProvider>();
      if (media.trending.isEmpty) {
        media.fetchHomeData();
      }
    });
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  void _onNavItemSelected(int index) {
    setState(() => _activeNavIndex = index);
    switch (index) {
      case 0:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
        break;
      case 1:
        if (_mainScrollController.hasClients) {
          _mainScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
        break;
      case 2:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoviesScreen()));
        break;
      case 3:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeriesScreen()));
        break;
      case 4:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveTvScreen()));
        break;
      case 5:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WatchlistScreen()));
        break;
      case 6:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 7:
        // Switch back to Mobile/Tablet UI
        TvModeService().setTvMode(false);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  void _playMedia(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.id,
          mediaTitle: item.title,
          mediaType: item.mediaType,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
        ),
      ),
    );
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          mediaId: item.id,
          mediaType: item.mediaType,
        ),
      ),
    );
  }

  String _formatGenres(List<int> genreIds) {
    if (genreIds.isEmpty) return 'Trending';
    return genreIds
        .take(3)
        .map((id) => _genreMap[id] ?? '')
        .where((name) => name.isNotEmpty)
        .join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final mediaProvider = context.watch<MediaProvider>();
    final historyProvider = context.watch<HistoryProvider>();

    final displayHeroItem = _focusedItem ?? mediaProvider.heroItem;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // ═══════════════════════════════════════════════════════════
          // 1. LEFT EXPANDABLE NAVIGATION RAIL (TV 10-Foot Style)
          // ═══════════════════════════════════════════════════════════
          _buildNavigationRail(),

          // ═══════════════════════════════════════════════════════════
          // 2. MAIN 10-FOOT VIEWPORT (Dynamic Hero + Rows)
          // ═══════════════════════════════════════════════════════════
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Top Dynamic Backdrop (Transitions smoothly with D-pad item focus)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: _buildDynamicHeroBackdrop(displayHeroItem),
                ),

                // Main Scrolling Content Layer
                ListView(
                  controller: _mainScrollController,
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    // Top Billboard Details (Title, Badges, Synopsis, Action Buttons)
                    _buildHeroBillboardDetails(displayHeroItem),

                    const SizedBox(height: 16),

                    // Content Carousels
                    if (historyProvider.items.isNotEmpty)
                      _buildContinueWatchingRow(historyProvider),

                    if (mediaProvider.trending.isNotEmpty)
                      _buildMediaRow('TRENDING ON VOIDFLIX', mediaProvider.trending),

                    if (mediaProvider.popularMovies.isNotEmpty)
                      _buildMediaRow('TOP MOVIES', mediaProvider.popularMovies),

                    if (mediaProvider.popularTV.isNotEmpty)
                      _buildMediaRow('POPULAR TV SERIES', mediaProvider.popularTV),

                    if (mediaProvider.actionMovies.isNotEmpty)
                      _buildMediaRow('ACTION & THRILLERS', mediaProvider.actionMovies),

                    if (mediaProvider.topRatedMovies.isNotEmpty)
                      _buildMediaRow('CRITICALLY ACCLAIMED CLASSICS', mediaProvider.topRatedMovies),

                    if (mediaProvider.anime.isNotEmpty)
                      _buildMediaRow('ANIME & ANIMATION', mediaProvider.anime),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LEFT NAVIGATION RAIL
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavigationRail() {
    final isExpanded = _isNavRailFocused;
    final railWidth = isExpanded ? 210.0 : 68.0;

    final navItems = [
      {'icon': Icons.search_rounded, 'label': 'Search'},
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.movie_outlined, 'label': 'Movies'},
      {'icon': Icons.tv_rounded, 'label': 'Series'},
      {'icon': Icons.live_tv_rounded, 'label': 'Live TV'},
      {'icon': Icons.bookmark_border_rounded, 'label': 'My List'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
      {'icon': Icons.stay_current_portrait_rounded, 'label': 'Mobile UI'},
    ];

    return Focus(
      onFocusChange: (focused) {
        setState(() => _isNavRailFocused = focused);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: railWidth,
        decoration: BoxDecoration(
          color: isExpanded ? const Color(0xFF0C0C14) : Colors.black.withValues(alpha: 0.85),
          border: const Border(right: BorderSide(color: Color(0xFF1C1C28), width: 1)),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ]
              : null,
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 12, 20),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryRed,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'V',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      const SizedBox(width: 10),
                      const Text(
                        'VOIDFLIX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Divider(color: Color(0xFF1E1E2C), height: 1),
              const SizedBox(height: 8),

              // Navigation Links
              Expanded(
                child: ListView.builder(
                  itemCount: navItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = navItems[idx];
                    final isCurrentActive = _activeNavIndex == idx;

                    return TvFocusable(
                      scaleFactor: 1.02,
                      glowColor: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(10),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      onPressed: () => _onNavItemSelected(idx),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isCurrentActive
                              ? AppTheme.primaryRed.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isCurrentActive
                              ? Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.4), width: 1)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              color: isCurrentActive ? AppTheme.primaryRed : Colors.white70,
                              size: 22,
                            ),
                            if (isExpanded) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    color: isCurrentActive ? Colors.white : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: isCurrentActive ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // TV Mode indicator bottom badge
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00D2FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '10-FOOT LEANBACK',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DYNAMIC HERO BACKDROP
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDynamicHeroBackdrop(MediaItem? item) {
    final backdropUrl = item?.backdropPath != null
        ? ApiConstants.getOriginalImageUrl(item!.backdropPath)
        : (item?.posterPath != null ? ApiConstants.getOriginalImageUrl(item!.posterPath) : '');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdropUrl.isNotEmpty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: CachedNetworkImage(
              key: ValueKey(backdropUrl),
              imageUrl: backdropUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, __) => Container(color: Colors.black),
              errorWidget: (_, __, ___) => Container(color: Colors.black),
            ),
          )
        else
          Container(color: const Color(0xFF0D0D14)),

        // Gradient Left-to-Right (Shields text)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 0.45, 0.85, 1.0],
              colors: [
                Colors.black,
                Color(0xCC000000),
                Colors.transparent,
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Gradient Bottom-to-Top (Smooth fade into the carousels)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              stops: [0.0, 0.45, 1.0],
              colors: [
                Colors.black,
                Color(0xDD000000),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HERO BILLBOARD DETAILS & ACTION BUTTONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildHeroBillboardDetails(MediaItem? item) {
    if (item == null) {
      return const SizedBox(height: 240);
    }

    final year = item.releaseDate != null && item.releaseDate!.length >= 4
        ? item.releaseDate!.substring(0, 4)
        : '';
    final rating = item.voteAverage > 0 ? item.voteAverage.toStringAsFixed(1) : '7.9';
    final genres = _formatGenres(item.genreIds);

    return Container(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo or Title
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Text(
              item.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 4)),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

          // Badges Row
          Row(
            children: [
              // Match %
              const Text(
                '98% Match',
                style: TextStyle(
                  color: Color(0xFF46D369),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),

              // Year
              if (year.isNotEmpty) ...[
                Text(
                  year,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
              ],

              // Rating Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 14),
                    const SizedBox(width: 3),
                    Text(
                      rating,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // 4K Ultra HD badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Text(
                  '4K ULTRA HD',
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),

              // Genres
              Text(
                genres,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Overview Synopsis
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              item.overview.isNotEmpty
                  ? item.overview
                  : 'A Voidflix exclusive presentation. Experience breathtaking cinematography in stunning Ultra HD with spatial audio.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.45,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Action Buttons: Play, Add to Watchlist, Details
          Row(
            children: [
              // 1. Play Button
              TvFocusable(
                autofocus: true,
                scaleFactor: 1.06,
                glowColor: Colors.white,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _playMedia(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                      SizedBox(width: 8),
                      Text(
                        'Play',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // 2. Watchlist Button
              Consumer<WatchlistProvider>(
                builder: (context, watchlist, _) {
                  final inList = watchlist.isInWatchlist(item.id);
                  return TvFocusable(
                    scaleFactor: 1.06,
                    glowColor: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: () => watchlist.toggleWatchlist(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            inList ? Icons.check_rounded : Icons.add_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            inList ? 'In My List' : 'My List',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),

              // 3. Details Button
              TvFocusable(
                scaleFactor: 1.06,
                glowColor: Colors.white70,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _openDetail(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTENT CAROUSEL ROW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMediaRow(String categoryTitle, List<MediaItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 10),
          child: Text(
            categoryTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 215,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            itemCount: items.length,
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final posterUrl = ApiConstants.getImageUrl(item.posterPath, size: 'w342');

              return TvFocusable(
                scaleFactor: 1.10,
                glowColor: AppTheme.primaryRed,
                borderRadius: BorderRadius.circular(8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                onFocusChange: (focused) {
                  if (focused && mounted) {
                    setState(() => _focusedItem = item);
                  }
                },
                onPressed: () => _openDetail(item),
                child: SizedBox(
                  width: 130,
                  height: 195,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (posterUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF161622),
                              alignment: Alignment.center,
                              child: Text(
                                item.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: const Color(0xFF161622),
                            alignment: Alignment.center,
                            child: Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTINUE WATCHING ROW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildContinueWatchingRow(HistoryProvider history) {
    final items = history.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(40, 16, 40, 10),
          child: Text(
            'CONTINUE WATCHING',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            itemCount: items.length,
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final progress = item.progress.clamp(0.0, 1.0);

              final mediaItem = MediaItem(
                id: item.id,
                title: item.title,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                overview: 'Continue from where you left off (Episode ${item.episode}).',
                voteAverage: 8.5,
                mediaType: item.mediaType,
              );

              return TvFocusable(
                scaleFactor: 1.10,
                glowColor: AppTheme.primaryRed,
                borderRadius: BorderRadius.circular(8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                onFocusChange: (focused) {
                  if (focused && mounted) {
                    setState(() => _focusedItem = mediaItem);
                  }
                },
                onPressed: () {
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
                child: SizedBox(
                  width: 220,
                  height: 165,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.posterPath != null && item.posterPath!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: ApiConstants.getImageUrl(item.posterPath, size: 'w500'),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF161622)),
                          )
                        else
                          Container(color: const Color(0xFF161622)),

                        // Center Play Circle
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                          ),
                        ),

                        // Title Banner at Bottom
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.black87,
                            child: Text(
                              item.title,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // Red Netflix Progress Bar at bottom
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 4,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
