import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import '../models/media_detail.dart';
import '../providers/history_provider.dart';
import '../providers/watchlist_provider.dart';
import '../screens/player_screen.dart';
import 'media_card.dart';

class DetailModal extends StatefulWidget {
  final MediaItem item;

  const DetailModal({super.key, required this.item});

  static Future<void> show(BuildContext context, MediaItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetailModal(item: item),
    );
  }

  @override
  State<DetailModal> createState() => _DetailModalState();
}

class _DetailModalState extends State<DetailModal> {
  final ApiService _apiService = ApiService();
  MediaDetail? _detail;
  bool _isLoading = true;
  int _selectedSeason = 1;
  List<TvEpisode> _episodes = [];
  bool _isLoadingEpisodes = false;
  int _selectedTab = 0; // 0: Episodes (if TV), 1: More Like This
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await _apiService.getDetails(widget.item.mediaType, widget.item.id);
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });

        if (widget.item.mediaType == 'tv' && detail.seasons.isNotEmpty) {
          _selectedSeason = detail.seasons.first.seasonNumber;
          _loadSeasonEpisodes(_selectedSeason);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSeasonEpisodes(int seasonNumber) async {
    setState(() => _isLoadingEpisodes = true);
    try {
      final episodes = await _apiService.getSeasonEpisodes(widget.item.id, seasonNumber);
      if (mounted) {
        setState(() {
          _episodes = episodes;
          _isLoadingEpisodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  void _playMedia({int season = 1, int episode = 1}) {
    Navigator.of(context).pop(); // Dismiss modal
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: widget.item.id,
          mediaTitle: widget.item.title,
          mediaType: widget.item.mediaType,
          season: season,
          episode: episode,
          posterPath: widget.item.posterPath,
          backdropPath: widget.item.backdropPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = context.watch<WatchlistProvider>();
    final historyProvider = context.watch<HistoryProvider>();
    final inList = watchlistProvider.isInWatchlist(widget.item.id);
    final savedProgress = historyProvider.getProgress(widget.item.id);

    final backdropUrl = ApiConstants.getImageUrl(
      widget.item.backdropPath ?? widget.item.posterPath,
      size: 'original',
    );

    final matchPercentage = widget.item.voteAverage > 0
        ? (widget.item.voteAverage * 10).round().clamp(75, 99)
        : 95;

    final isTv = widget.item.mediaType == 'tv';

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Drag handle indicator
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (_isLoading)
            const LinearProgressIndicator(
              color: AppTheme.primaryRed,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // Top Backdrop / Trailer Section
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      // Backdrop Image
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: backdropUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: backdropUrl,
                                fit: BoxFit.cover,
                                placeholder: (c, u) => Container(color: const Color(0xFF222222)),
                                errorWidget: (c, u, e) => Container(color: const Color(0xFF222222)),
                              )
                            : Container(color: const Color(0xFF222222)),
                      ),

                      // Gradient fade at bottom
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.6, 1.0],
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.3),
                                const Color(0xFF181818),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Close button top right
                      Positioned(
                        top: 10,
                        right: 12,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.7),
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content body
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          widget.item.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Metadata Row (Match %, Year, Maturity, Duration, HD, CC)
                        Row(
                          children: [
                            Text(
                              '$matchPercentage% Match',
                              style: const TextStyle(
                                color: AppTheme.matchGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (widget.item.year.isNotEmpty) ...[
                              Text(
                                widget.item.year,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                isTv ? 'TV-MA' : 'PG-13',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_detail?.runtime != null && _detail!.runtime! > 0) ...[
                              Text(
                                '${_detail!.runtime}m',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'HD',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38),
                                borderRadius: BorderRadius.circular(2),
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
                        const SizedBox(height: 14),

                        // Big Play / Resume button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final s = savedProgress?.season ?? (isTv ? _selectedSeason : 1);
                              final e = savedProgress?.episode ?? 1;
                              _playMedia(season: s, episode: e);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow, color: Colors.black, size: 26),
                            label: Text(
                              savedProgress != null
                                  ? (isTv
                                      ? 'Resume S${savedProgress.season} : E${savedProgress.episode}'
                                      : 'Resume')
                                  : 'Play',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Action buttons row: [My List] [Rate] [Share]
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActionButton(
                              icon: inList ? Icons.check : Icons.add,
                              label: 'My List',
                              isActive: inList,
                              onTap: () => watchlistProvider.toggleWatchlist(widget.item),
                            ),
                            _buildActionButton(
                              icon: _isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                              label: 'Rate',
                              isActive: _isLiked,
                              onTap: () => setState(() => _isLiked = !_isLiked),
                            ),
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              isActive: false,
                              onTap: () {
                                SharePlus.instance.share(
                                  ShareParams(
                                    text: 'Check out "${widget.item.title}" on Voidflix!\nhttps://voidflix.org/${widget.item.mediaType}/${widget.item.id}',
                                    subject: 'Watch ${widget.item.title} on Voidflix',
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Storyline Overview
                        Text(
                          widget.item.overview.isNotEmpty
                              ? widget.item.overview
                              : (_detail?.overview ?? 'No overview available.'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Genres
                        if (_detail?.genres != null && _detail!.genres.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Genres: ${_detail!.genres.join(", ")}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),

                        const Divider(color: Color(0xFF2A2A2A)),
                      ],
                    ),
                  ),
                ),

                // TV Shows: Episodes / More Like This Tabs
                if (isTv) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildTabButton(
                            title: 'Episodes',
                            isSelected: _selectedTab == 0,
                            onTap: () => setState(() => _selectedTab = 0),
                          ),
                          const SizedBox(width: 16),
                          _buildTabButton(
                            title: 'More Like This',
                            isSelected: _selectedTab == 1,
                            onTap: () => setState(() => _selectedTab = 1),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_selectedTab == 0) ...[
                    // Season Picker Dropdown
                    if (_detail?.seasons != null && _detail!.seasons.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF242424),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButton<int>(
                                  value: _selectedSeason,
                                  dropdownColor: const Color(0xFF242424),
                                  underline: const SizedBox.shrink(),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                  items: _detail!.seasons.map((s) {
                                    return DropdownMenuItem<int>(
                                      value: s.seasonNumber,
                                      child: Text(
                                        s.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedSeason = val);
                                      _loadSeasonEpisodes(val);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Episodes List
                    if (_isLoadingEpisodes)
                      const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(color: AppTheme.primaryRed),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final ep = _episodes[index];
                            final stillUrl = ApiConstants.getImageUrl(ep.stillPath, size: 'w300');

                            return InkWell(
                              onTap: () => _playMedia(
                                season: _selectedSeason,
                                episode: ep.episodeNumber,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFF222222))),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Episode Still Thumbnail
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        width: 105,
                                        height: 65,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (stillUrl.isNotEmpty)
                                              CachedNetworkImage(
                                                imageUrl: stillUrl,
                                                fit: BoxFit.cover,
                                              )
                                            else
                                              Container(color: const Color(0xFF2E2E2E)),
                                            Center(
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.black.withValues(alpha: 0.6),
                                                ),
                                                child: const Icon(
                                                  Icons.play_arrow,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Episode Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${ep.episodeNumber}. ${ep.name}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              if (ep.runtime > 0)
                                                Text(
                                                  '${ep.runtime}m',
                                                  style: const TextStyle(
                                                    color: AppTheme.textMuted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            ep.overview.isNotEmpty
                                                ? ep.overview
                                                : 'Episode ${ep.episodeNumber}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 11,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _episodes.length,
                        ),
                      ),
                  ] else ...[
                    // Recommendations Grid
                    _buildRecommendationsSliver(),
                  ],
                ] else ...[
                  // Movies: More Like This
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Text(
                        'More Like This',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  _buildRecommendationsSliver(),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: isActive ? AppTheme.primaryRed : Colors.white,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppTheme.primaryRed : AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primaryRed : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMuted,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationsSliver() {
    final recs = _detail?.recommendations ?? [];
    if (recs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No recommendations found', style: TextStyle(color: Colors.white54)),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return MediaCard(
              item: recs[index],
              forceType: widget.item.mediaType,
            );
          },
          childCount: recs.length,
        ),
      ),
    );
  }
}
