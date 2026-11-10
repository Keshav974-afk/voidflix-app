import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import '../providers/history_provider.dart';
import '../providers/watchlist_provider.dart';
import '../screens/player_screen.dart';
import 'detail_modal.dart';
import 'tv_focusable.dart';

// Minimal TMDB genre-id to name map
const Map<int, String> kGenreNames = {
  28: "Action",
  12: "Adventure",
  16: "Animation",
  35: "Comedy",
  80: "Crime",
  99: "Documentary",
  18: "Drama",
  10751: "Family",
  14: "Fantasy",
  36: "History",
  27: "Horror",
  10402: "Music",
  9648: "Mystery",
  10749: "Romance",
  878: "Sci-Fi",
  53: "Thriller",
  10752: "War",
  37: "Western",
  10759: "Action & Adventure",
  10762: "Kids",
  10765: "Sci-Fi & Fantasy",
};

class HeroBanner extends StatefulWidget {
  final List<MediaItem> items;

  const HeroBanner({super.key, required this.items});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _currentIndex = 0;
  Timer? _timer;
  final ApiService _apiService = ApiService();
  static final Map<int, String?> _globalLogoCache = {};

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadLogos();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _loadLogos();
    }
  }

  void _loadLogos() {
    for (final item in widget.items.take(5)) {
      if (_globalLogoCache.containsKey(item.id)) continue;
      _apiService.getDetails(item.mediaType, item.id).then((detail) {
        _globalLogoCache[item.id] = detail.logoPath;
        if (mounted) {
          setState(() {});
        }
      }).catchError((_) {
        _globalLogoCache[item.id] = null;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 7), (timer) {
        if (mounted) {
          setState(() {
            final max = widget.items.length.clamp(1, 5);
            _currentIndex = (_currentIndex + 1) % max;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<String> _getGenreNames(MediaItem item) {
    return item.genreIds
        .map((id) => kGenreNames[id])
        .whereType<String>()
        .take(3)
        .toList();
  }

  void _playItem(MediaItem item) {
    final saved = context.read<HistoryProvider>().getProgress(item.id);
    final posSec = (saved != null && saved.positionSeconds > 0)
        ? saved.positionSeconds.toDouble()
        : (saved != null && saved.progress > 0 && saved.durationSeconds > 0
            ? (saved.progress * saved.durationSeconds).toDouble()
            : null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.id,
          mediaTitle: item.title,
          mediaType: item.mediaType,
          season: saved?.season ?? 1,
          episode: saved?.episode ?? 1,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          startPositionSeconds: posSec,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.items.take(5).toList();
    if (list.isEmpty) {
      return Container(
        height: 380,
        color: const Color(0xFF181818),
      );
    }

    final item = list[_currentIndex.clamp(0, list.length - 1)];
    final genres = _getGenreNames(item);
    final isWide = MediaQuery.of(context).size.width >= 768;

    final watchlist = context.watch<WatchlistProvider>();
    final inList = watchlist.isInWatchlist(item.id);

    if (isWide) {
      // Desktop / Tablet Hero Layout (80vh full bleed backdrop)
      final backdropUrl = ApiConstants.getImageUrl(item.backdropPath, size: 'w1280');

      return RepaintBoundary(
        child: SizedBox(
          height: 520,
          width: double.infinity,
          child: Stack(
            children: [
              // Backdrop Image with Animated Crossfade
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  child: backdropUrl.isNotEmpty
                      ? CachedNetworkImage(
                          key: ValueKey(item.id),
                          imageUrl: backdropUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 1280,
                          memCacheHeight: 720,
                          filterQuality: FilterQuality.low,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (c, u) => Container(color: AppTheme.cardColor),
                          errorWidget: (c, u, e) => Container(color: AppTheme.cardColor),
                        )
                    : Container(color: AppTheme.cardColor),
              ),
            ),

            // Left and bottom gradient vignette
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppTheme.background.withValues(alpha: 0.95),
                      AppTheme.background.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.6, 1.0],
                    colors: [
                      Colors.transparent,
                      AppTheme.background.withValues(alpha: 0.5),
                      AppTheme.background,
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Positioned(
              left: 36,
              bottom: 40,
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stylized Logo (where available) with Plain Text Fallback
                  if (_globalLogoCache[item.id] != null && _globalLogoCache[item.id]!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: CachedNetworkImage(
                        imageUrl: ApiConstants.getImageUrl(_globalLogoCache[item.id], size: 'w500'),
                        height: 75,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        placeholder: (c, u) => Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.bebasNeue(
                            fontSize: 54,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            height: 1.0,
                          ),
                        ),
                        errorWidget: (c, u, e) => Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.bebasNeue(
                            fontSize: 54,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            height: 1.0,
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.bebasNeue(
                          fontSize: 54,
                          color: Colors.white,
                          letterSpacing: 1.5,
                          height: 1.0,
                        ),
                      ),
                    ),

                  // Rating, Year, Type
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.primaryRed, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        item.voteAverage.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        item.year,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white38),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          item.mediaType.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    item.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      TvFocusable(
                        borderRadius: BorderRadius.circular(6),
                        glowColor: Colors.white,
                        onPressed: () => _playItem(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow, color: Colors.black, size: 24),
                              SizedBox(width: 6),
                              Text(
                                'Play',
                                style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TvFocusable(
                        borderRadius: BorderRadius.circular(6),
                        glowColor: Colors.white,
                        onPressed: () => DetailModal.show(context, item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'More Info',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Carousel dots bottom right
            Positioned(
              right: 36,
              bottom: 40,
              child: _buildIndicatorDots(list),
            ),
          ],
        ),
      ),
      );
    }

    // Mobile Hero Layout (Exact Netflix mobile poster card with genres and pill buttons)
    final posterUrl = ApiConstants.getImageUrl(item.posterPath ?? item.backdropPath, size: 'w780');

    return RepaintBoundary(
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          Container(
            height: 450,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 0.8,
              ),
              color: AppTheme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Animated poster crossfade
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          key: ValueKey(item.id),
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 780,
                          memCacheHeight: 900,
                          filterQuality: FilterQuality.low,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (c, u) => Container(color: const Color(0xFF222222)),
                          errorWidget: (c, u, e) => Container(color: const Color(0xFF222222)),
                        )
                      : Container(color: const Color(0xFF222222)),
                ),

                // Bottom vignette gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.25),
                          Colors.black.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom Content
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Stylized Logo (where available) with Plain Text Fallback
                      if (_globalLogoCache[item.id] != null && _globalLogoCache[item.id]!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CachedNetworkImage(
                            imageUrl: ApiConstants.getImageUrl(_globalLogoCache[item.id], size: 'w500'),
                            height: 55,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            placeholder: (c, u) => Text(
                              item.displayTitle,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            errorWidget: (c, u, e) => Text(
                              item.displayTitle,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            item.displayTitle,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Genre tags with red bullet separators
                      if (genres.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < genres.length; i++) ...[
                                if (i > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      '•',
                                      style: TextStyle(
                                        color: AppTheme.primaryRed,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Text(
                                  genres[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      // Two pill buttons: [Play Movie] and [My List]
                      Row(
                        children: [
                          // Play button
                          Expanded(
                            child: TvFocusable(
                              borderRadius: BorderRadius.circular(6),
                              glowColor: Colors.white,
                              onPressed: () => _playItem(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.play_arrow, color: Colors.black, size: 22),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.mediaType == 'movie' ? 'Play Movie' : 'Play',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // My List button (frosted glass)
                          Expanded(
                            child: TvFocusable(
                              borderRadius: BorderRadius.circular(6),
                              glowColor: Colors.white,
                              onPressed: () => watchlist.toggleWatchlist(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      inList ? Icons.check : Icons.add,
                                      color: inList ? AppTheme.primaryRed : Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      inList ? 'Added' : 'My List',
                                      style: TextStyle(
                                        color: inList ? AppTheme.primaryRed : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Info icon button
                          TvFocusable(
                            borderRadius: BorderRadius.circular(6),
                            glowColor: Colors.white,
                            onPressed: () => DetailModal.show(context, item),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Indicator dots
          const SizedBox(height: 8),
          _buildIndicatorDots(list),
        ],
      ),
    ),
    );
  }

  Widget _buildIndicatorDots(List<MediaItem> list) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int idx = 0; idx < list.length; idx++)
          GestureDetector(
            onTap: () => setState(() => _currentIndex = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              width: idx == _currentIndex ? 24 : 10,
              decoration: BoxDecoration(
                color: idx == _currentIndex
                    ? AppTheme.primaryRed
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
