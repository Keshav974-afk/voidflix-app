import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import '../core/services/voidcast_service.dart';
import '../widgets/tv_cast_dialog.dart';
import '../models/media_item.dart';
import '../providers/history_provider.dart';
import '../providers/media_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/tv_focusable.dart';
import 'detail_screen.dart';
import 'live_tv_screen.dart';
import 'movies_screen.dart';
import 'new_popular_screen.dart';
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
  int _activeNavIndex = 1;
  bool _isNavRailFocused = false;

  MediaItem? _focusedItem;
  final ScrollController _mainScrollController = ScrollController();

  // Explicit FocusNodes for the nav-rail items so we can arrow-key between them
  final List<FocusNode> _navFocusNodes = List.generate(10, (_) => FocusNode());
  StreamSubscription? _voidCastSub;

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
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final media = context.read<MediaProvider>();
      if (media.trending.isEmpty) {
        media.fetchHomeData();
      }
    });

    // Initialize VoidCast TV Receiver
    VoidCastService().startHosting(deviceName: 'Voidflix Android TV');
    _voidCastSub = VoidCastService().onCommand.listen((cmd) {
      final action = cmd['action'] as String? ?? '';
      final payload = cmd['payload'] as Map<String, dynamic>? ?? {};

      if (action == 'play') {
        final tmdbId = int.tryParse(payload['tmdbId']?.toString() ?? '') ?? 0;
        if (tmdbId > 0 && mounted) {
          final title = payload['title']?.toString() ?? 'Movie';
          final type = payload['type']?.toString() ?? 'movie';
          final poster = payload['poster']?.toString();
          final season = int.tryParse(payload['season']?.toString() ?? '1') ?? 1;
          final episode = int.tryParse(payload['episode']?.toString() ?? '1') ?? 1;

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                mediaId: tmdbId,
                mediaTitle: title,
                mediaType: type,
                season: season,
                episode: episode,
                posterPath: poster,
              ),
            ),
          );
        }
      } else if (action == 'search') {
        final q = payload['query']?.toString() ?? '';
        if (q.isNotEmpty && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
        }
      } else if (action == 'key') {
        final k = payload['key']?.toString() ?? '';
        if (k == 'back' && mounted) {
          Navigator.of(context).maybePop();
        } else if (k == 'home' && mounted) {
          _onNavItemSelected(1);
        }
      }
    });
  }

  @override
  void dispose() {
    _voidCastSub?.cancel();
    for (final node in _navFocusNodes) {
      node.dispose();
    }
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
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewPopularScreen()));
        break;
      case 3:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeriesScreen()));
        break;
      case 4:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoviesScreen()));
        break;
      case 5:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WatchlistScreen()));
        break;
      case 6:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveTvScreen()));
        break;
      case 7:
        TvCastDialog.show(context);
        break;
      case 8:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 9:
        TvModeService().setTvMode(false);
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
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
          // 1. LEFT NAVIGATION RAIL (TV D-Pad Up/Down fixed)
          // ═══════════════════════════════════════════════════════════
          _buildNavigationRail(),

          // ═══════════════════════════════════════════════════════════
          // 2. MAIN 10-FOOT VIEWPORT
          // ═══════════════════════════════════════════════════════════
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Top Dynamic Backdrop
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
                    _buildHeroBillboardDetails(displayHeroItem),

                    const SizedBox(height: 16),

                    if (historyProvider.items.isNotEmpty)
                      _buildContinueWatchingRow(historyProvider),

                    if (mediaProvider.trending.isNotEmpty)
                      _buildMediaRow('POPULAR ON VOIDFLIX', mediaProvider.trending, isLandscape: true),

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
  // LEFT NAVIGATION RAIL — D-pad Up/Down fixed with explicit FocusNodes
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavigationRail() {
    final isExpanded = _isNavRailFocused;
    final railWidth = isExpanded ? 220.0 : 72.0;

    final navItems = [
      {'icon': Icons.search_rounded, 'label': 'Search'},
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.local_fire_department_rounded, 'label': 'New & Popular'},
      {'icon': Icons.tv_rounded, 'label': 'Series'},
      {'icon': Icons.movie_outlined, 'label': 'Movies'},
      {'icon': Icons.add_rounded, 'label': 'My List'},
      {'icon': Icons.sports_cricket_rounded, 'label': 'Sports & Live TV'},
      {'icon': Icons.cast_connected_rounded, 'label': 'Link Phone'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
      {
        'icon': Icons.desktop_windows_rounded,
        'label': (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
            ? 'Desktop UI'
            : 'Mobile UI',
      },
    ];

    // Key handler: intercept up/down arrows and move focus within our list
    KeyEventResult handleNavKey(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      final currentIdx = _navFocusNodes.indexOf(node);
      if (currentIdx < 0) return KeyEventResult.ignored;

      if (key == LogicalKeyboardKey.arrowDown) {
        final next = (currentIdx + 1).clamp(0, navItems.length - 1);
        if (next != currentIdx) {
          _navFocusNodes[next].requestFocus();
          return KeyEventResult.handled;
        }
      } else if (key == LogicalKeyboardKey.arrowUp) {
        final prev = (currentIdx - 1).clamp(0, navItems.length - 1);
        if (prev != currentIdx) {
          _navFocusNodes[prev].requestFocus();
          return KeyEventResult.handled;
        }
      } else if (key == LogicalKeyboardKey.arrowRight) {
        // Move focus to the main content area
        FocusScope.of(context).focusInDirection(TraversalDirection.right);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Focus(
      onFocusChange: (focused) {
        setState(() => _isNavRailFocused = focused);
      },
      skipTraversal: true,
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
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryRed,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'V',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
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

              // Navigation Links — explicit FocusNodes + up/down key handler
              Expanded(
                child: ListView.builder(
                  itemCount: navItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = navItems[idx];
                    final isCurrentActive = _activeNavIndex == idx;

                    return Focus(
                      focusNode: _navFocusNodes[idx],
                      onKeyEvent: handleNavKey,
                      onFocusChange: (hasFocus) {
                        if (hasFocus) setState(() => _isNavRailFocused = true);
                      },
                      child: Builder(
                        builder: (ctx2) {
                          final isFocused = Focus.of(ctx2).hasFocus;
                          return GestureDetector(
                            onTap: () => _onNavItemSelected(idx),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                              decoration: BoxDecoration(
                                color: isFocused
                                    ? AppTheme.primaryRed.withValues(alpha: 0.25)
                                    : isCurrentActive
                                        ? AppTheme.primaryRed.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isFocused
                                    ? Border.all(color: AppTheme.primaryRed, width: 2)
                                    : isCurrentActive
                                        ? Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.4), width: 1)
                                        : Border.all(color: Colors.transparent, width: 2),
                                boxShadow: isFocused
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.primaryRed.withValues(alpha: 0.4),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    color: isFocused || isCurrentActive ? AppTheme.primaryRed : Colors.white70,
                                    size: 24,
                                  ),
                                  if (isExpanded) ...[
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        item['label'] as String,
                                        style: TextStyle(
                                          color: isFocused || isCurrentActive ? Colors.white : Colors.white70,
                                          fontSize: 15,
                                          fontWeight: isFocused || isCurrentActive ? FontWeight.bold : FontWeight.w500,
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
                    );
                  },
                ),
              ),

              // TV Mode indicator
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

        // Left shield gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 0.45, 0.85, 1.0],
              colors: [Colors.black, Color(0xCC000000), Colors.transparent, Colors.transparent],
            ),
          ),
        ),

        // Bottom fade gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              stops: [0.0, 0.45, 1.0],
              colors: [Colors.black, Color(0xDD000000), Colors.transparent],
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
          // V SERIES / V FILM badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'V',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (item.mediaType == 'tv' ? 'SERIES' : 'FILM'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Text(
              item.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: [Shadow(color: Colors.black, blurRadius: 16, offset: Offset(0, 4))],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

          // Badges Row
          Row(
            children: [
              const Text('98% Match',
                  style: TextStyle(color: Color(0xFF46D369), fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 12),
              if (year.isNotEmpty) ...[
                Text(year, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
              ],
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
                    Text(rating, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Text('4K ULTRA HD',
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Text(genres, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),

          // Overview
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
                shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Action Buttons: Play, More Info, Add to Watchlist
          Row(
            children: [
              // Play
              TvFocusable(
                autofocus: true,
                scaleFactor: 1.06,
                glowColor: Colors.white,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _playMedia(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                      SizedBox(width: 8),
                      Text('Play',
                          style: TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // More Info
              TvFocusable(
                scaleFactor: 1.06,
                glowColor: Colors.white70,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => _openDetail(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text('More Info',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Watchlist
              Consumer<WatchlistProvider>(
                builder: (context, watchlist, _) {
                  final inList = watchlist.isInWatchlist(item.id);
                  return TvFocusable(
                    scaleFactor: 1.06,
                    glowColor: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: () => watchlist.toggleWatchlist(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Icon(inList ? Icons.check_rounded : Icons.add_rounded, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(inList ? 'In My List' : 'My List',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTENT CAROUSEL ROW — Larger TV-optimised cards
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMediaRow(String categoryTitle, List<MediaItem> items, {bool isLandscape = false}) {
    // Bigger cards for 10-foot TV viewing
    final rowHeight = isLandscape ? 195.0 : 255.0;
    final cardWidth = isLandscape ? 290.0 : 155.0;
    final cardHeight = isLandscape ? 165.0 : 230.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 12),
          child: Text(
            categoryTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            itemCount: items.length,
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final imageUrl = isLandscape
                  ? ApiConstants.getImageUrl(item.backdropPath ?? item.posterPath, size: 'w780')
                  : ApiConstants.getImageUrl(item.posterPath, size: 'w342');

              return TvFocusable(
                scaleFactor: 1.08,
                glowColor: AppTheme.primaryRed,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                onFocusChange: (focused) {
                  if (focused && mounted) {
                    setState(() => _focusedItem = item);
                  }
                },
                onPressed: () => _openDetail(item),
                child: SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF161622),
                              alignment: Alignment.center,
                              child: Text(item.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ),
                          )
                        else
                          Container(
                            color: const Color(0xFF161622),
                            alignment: Alignment.center,
                            child: Text(item.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ),

                        // Bottom title bar for landscape cards
                        if (isLandscape)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.92),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Bottom title for portrait cards
                        if (!isLandscape)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.9),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
          padding: EdgeInsets.fromLTRB(40, 16, 40, 12),
          child: Text(
            'CONTINUE WATCHING',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 210,
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
                scaleFactor: 1.08,
                glowColor: AppTheme.primaryRed,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
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
                  width: 260,
                  height: 185,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.backdropPath != null && item.backdropPath!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: ApiConstants.getImageUrl(item.backdropPath, size: 'w500'),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF161622)),
                          )
                        else if (item.posterPath != null && item.posterPath!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: ApiConstants.getImageUrl(item.posterPath, size: 'w500'),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF161622)),
                          )
                        else
                          Container(color: const Color(0xFF161622)),

                        // Dark overlay for readability
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                            ),
                          ),
                        ),

                        // Center Play Circle
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                          ),
                        ),

                        // Title at bottom
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 8,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // Red progress bar at very bottom
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
