import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import '../providers/watchlist_provider.dart';
import '../screens/player_screen.dart';
import 'detail_modal.dart';

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

  @override
  void initState() {
    super.initState();
    _startTimer();
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
      final backdropUrl = ApiConstants.getImageUrl(item.backdropPath, size: 'original');

      return SizedBox(
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
                  Text(
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
                  const SizedBox(height: 10),

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
                      ElevatedButton.icon(
                        onPressed: () => _playItem(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, color: Colors.black, size: 24),
                        label: const Text(
                          'Play',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => DetailModal.show(context, item),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: const Icon(Icons.info_outline, size: 20),
                        label: const Text(
                          'More Info',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
      );
    }

    // Mobile Hero Layout (Exact Netflix mobile poster card with genres and pill buttons)
    final posterUrl = ApiConstants.getImageUrl(item.posterPath ?? item.backdropPath, size: 'w780');

    return Padding(
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
                      // Title Overlay
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
                            child: ElevatedButton.icon(
                              onPressed: () => _playItem(item),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow, color: Colors.black, size: 22),
                              label: Text(
                                item.mediaType == 'movie' ? 'Play Movie' : 'Play',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // My List button (frosted glass)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => watchlist.toggleWatchlist(item),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.25),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: Icon(
                                inList ? Icons.check : Icons.add,
                                color: inList ? AppTheme.primaryRed : Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                inList ? 'Added' : 'My List',
                                style: TextStyle(
                                  color: inList ? AppTheme.primaryRed : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Info icon button
                          GestureDetector(
                            onTap: () => DetailModal.show(context, item),
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
