import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import '../models/media_item.dart';
import '../providers/media_provider.dart';
import '../widgets/media_row.dart';
import '../widgets/top10_row.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

class NewPopularScreen extends StatefulWidget {
  const NewPopularScreen({super.key});

  @override
  State<NewPopularScreen> createState() => _NewPopularScreenState();
}

class _NewPopularScreenState extends State<NewPopularScreen> {
  MediaItem? _focusedHeroItem;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final isTv = TvModeService().isTvMode;

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Consumer<MediaProvider>(
        builder: (context, mediaProvider, child) {
          if (isTv) {
            return _buildTvLayout(context, mediaProvider, canPop);
          }
          return _buildMobileLayout(context, mediaProvider, canPop);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TV LEANBACK LAYOUT — Hero banner + horizontal carousels
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTvLayout(BuildContext context, MediaProvider mediaProvider, bool canPop) {
    final heroItem = _focusedHeroItem ?? (mediaProvider.trending.isNotEmpty ? mediaProvider.trending.first : null);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hero backdrop
          if (heroItem != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.6,
              child: _buildHeroBackdrop(heroItem),
            ),

          // Scrollable content
          ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              // Header bar
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                child: Row(
                  children: [
                    if (canPop) ...[
                      TvBackButton(onPressed: () => Navigator.of(context).pop()),
                      const SizedBox(width: 20),
                    ],
                    const Icon(Icons.local_fire_department_rounded, color: AppTheme.primaryRed, size: 32),
                    const SizedBox(width: 10),
                    Text(
                      'NEW & POPULAR',
                      style: GoogleFonts.bebasNeue(fontSize: 38, letterSpacing: 2, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // Hero info overlay
              if (heroItem != null) _buildTvHeroInfo(heroItem),

              const SizedBox(height: 8),

              // Trending row
              if (mediaProvider.trending.isNotEmpty)
                _buildTvRow('TRENDING THIS WEEK', mediaProvider.trending, isLandscape: true),

              // Top 10 Movies
              if (mediaProvider.popularMovies.isNotEmpty)
                _buildTvTop10Row('TOP 10 MOVIES TODAY', mediaProvider.popularMovies, 'movie'),

              // Top 10 TV
              if (mediaProvider.popularTV.isNotEmpty)
                _buildTvTop10Row('TOP 10 TV SHOWS TODAY', mediaProvider.popularTV, 'tv'),

              // Critically Acclaimed
              if (mediaProvider.topRatedMovies.isNotEmpty)
                _buildTvRow('CRITICALLY ACCLAIMED MOVIES', mediaProvider.topRatedMovies),

              // Binge-worthy
              if (mediaProvider.topRatedTV.isNotEmpty)
                _buildTvRow('BINGE-WORTHY SERIES', mediaProvider.topRatedTV),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBackdrop(MediaItem item) {
    final url = item.backdropPath != null
        ? ApiConstants.getOriginalImageUrl(item.backdropPath)
        : (item.posterPath != null ? ApiConstants.getOriginalImageUrl(item.posterPath) : '');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url.isNotEmpty)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: CachedNetworkImage(
              key: ValueKey(url),
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.black),
              errorWidget: (_, __, ___) => Container(color: Colors.black),
            ),
          )
        else
          Container(color: const Color(0xFF0D0D14)),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.black, Color(0xAA000000), Colors.transparent],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black, Colors.transparent],
              stops: [0.0, 0.7],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTvHeroInfo(MediaItem item) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              shadows: [Shadow(color: Colors.black, blurRadius: 12)],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          if (item.overview.isNotEmpty)
            Text(
              item.overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              TvFocusable(
                autofocus: true,
                scaleFactor: 1.06,
                glowColor: Colors.white,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      mediaId: item.id,
                      mediaTitle: item.title,
                      mediaType: item.mediaType,
                      posterPath: item.posterPath,
                      backdropPath: item.backdropPath,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: const Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                      SizedBox(width: 8),
                      Text('Play', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              TvFocusable(
                scaleFactor: 1.06,
                glowColor: Colors.white70,
                borderRadius: BorderRadius.circular(8),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(mediaId: item.id, mediaType: item.mediaType),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('More Info', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

  Widget _buildTvRow(String title, List<MediaItem> items, {bool isLandscape = false}) {
    final rowHeight = isLandscape ? 195.0 : 255.0;
    final cardWidth = isLandscape ? 290.0 : 155.0;
    final cardHeight = isLandscape ? 165.0 : 230.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 12),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 28),
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
                  if (focused && mounted) setState(() => _focusedHeroItem = item);
                },
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DetailScreen(mediaId: item.id, mediaType: item.mediaType)),
                ),
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
                          Container(color: const Color(0xFF161622)),
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
                                colors: [Colors.black.withValues(alpha: 0.92), Colors.transparent],
                              ),
                            ),
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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

  Widget _buildTvTop10Row(String title, List<MediaItem> items, String forceType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: const Text('10',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            itemCount: items.take(10).length,
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final imageUrl = ApiConstants.getImageUrl(item.posterPath, size: 'w342');

              return TvFocusable(
                scaleFactor: 1.08,
                glowColor: AppTheme.primaryRed,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                onFocusChange: (focused) {
                  if (focused && mounted) setState(() => _focusedHeroItem = item);
                },
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DetailScreen(mediaId: item.id, mediaType: forceType)),
                ),
                child: SizedBox(
                  width: 145,
                  height: 185,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Rank number (large, slightly outside card)
                      Positioned(
                        left: -8,
                        bottom: 0,
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withValues(alpha: 0.15),
                            height: 1,
                          ),
                        ),
                      ),
                      // Card image
                      Positioned(
                        left: 28,
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: const Color(0xFF161622)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF161622),
                              alignment: Alignment.center,
                              child: Text(item.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
                            ),
                          ),
                        ),
                      ),
                    ],
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
  // MOBILE LAYOUT (unchanged from original)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMobileLayout(BuildContext context, MediaProvider mediaProvider, bool canPop) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (canPop) ...[
                      const TvBackButton(),
                      const SizedBox(width: 12),
                    ],
                    const Icon(Icons.local_fire_department, color: AppTheme.primaryRed, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      'NEW & POPULAR',
                      style: GoogleFonts.bebasNeue(fontSize: 34, letterSpacing: 1.5, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  "What everyone's watching right now — fresh releases, trending titles, and coming soon.",
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          MediaRow(title: 'Trending This Week', items: mediaProvider.trending),
          Top10Row(title: 'Top 10 Movies Today', items: mediaProvider.popularMovies, forceType: 'movie'),
          Top10Row(title: 'Top 10 TV Shows Today', items: mediaProvider.popularTV, forceType: 'tv'),
          MediaRow(title: 'Critically Acclaimed Movies', items: mediaProvider.topRatedMovies),
          MediaRow(title: 'Binge-Worthy Series', items: mediaProvider.topRatedTV),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
