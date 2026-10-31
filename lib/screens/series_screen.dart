import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/tv_mode_service.dart';
import '../models/media_item.dart';
import '../providers/media_provider.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_card.dart';
import '../widgets/media_row.dart';
import '../widgets/top10_row.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  // Curated category rows state
  List<MediaItem> _comedySeries = [];
  List<MediaItem> _actionSeries = [];
  List<MediaItem> _dramaSeries = [];
  List<MediaItem> _scifiSeries = [];

  // Never-ending infinite scroll browse state
  final List<MediaItem> _browseItems = [];
  final Set<int> _seenIds = {};
  int _currentPage = 1;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  int? _selectedGenreId;
  String _selectedSort = 'popularity.desc';

  static const List<Map<String, dynamic>> _genres = [
    {'name': 'All', 'id': null},
    {'name': 'Action & Adventure', 'id': 10759},
    {'name': 'Animation', 'id': 16},
    {'name': 'Comedy', 'id': 35},
    {'name': 'Crime', 'id': 80},
    {'name': 'Documentary', 'id': 99},
    {'name': 'Drama', 'id': 18},
    {'name': 'Family', 'id': 10751},
    {'name': 'Mystery', 'id': 9648},
    {'name': 'Sci-Fi & Fantasy', 'id': 10765},
  ];

  static const List<Map<String, String>> _sortOptions = [
    {'label': 'Popularity', 'value': 'popularity.desc'},
    {'label': 'Highest Rated', 'value': 'vote_average.desc'},
    {'label': 'Newest', 'value': 'first_air_date.desc'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCuratedRows();
    _fetchBrowsePage(reset: true);

    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;
        if (currentScroll >= maxScroll - 600 && !_isLoadingMore && !_isLoadingInitial && _hasMore) {
          _fetchBrowsePage(reset: false);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCuratedRows() async {
    try {
      final futures = await Future.wait([
        _apiService.discoverMedia('tv', genreId: 35),
        _apiService.discoverMedia('tv', genreId: 10759),
        _apiService.discoverMedia('tv', genreId: 18),
        _apiService.discoverMedia('tv', genreId: 10765),
      ]);
      if (mounted) {
        setState(() {
          _comedySeries = futures[0];
          _actionSeries = futures[1];
          _dramaSeries = futures[2];
          _scifiSeries = futures[3];
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchBrowsePage({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoadingInitial = true;
        _currentPage = 1;
        _hasMore = true;
        _browseItems.clear();
        _seenIds.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final targetPage = reset ? 1 : _currentPage + 1;
      final results = await _apiService.discoverMedia(
        'tv',
        genreId: _selectedGenreId,
        sort: _selectedSort,
        page: targetPage,
      );

      if (mounted) {
        setState(() {
          _currentPage = targetPage;
          if (results.isEmpty) {
            _hasMore = false;
          } else {
            for (final item in results) {
              if (_seenIds.add(item.id)) {
                _browseItems.add(item);
              }
            }
          }
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onGenreSelected(int? genreId) {
    if (_selectedGenreId == genreId) return;
    setState(() => _selectedGenreId = genreId);
    _fetchBrowsePage(reset: true);
  }

  void _onSortSelected(String sort) {
    if (_selectedSort == sort) return;
    setState(() => _selectedSort = sort);
    _fetchBrowsePage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final isTv = TvModeService().isTvMode;
    final mediaProvider = context.watch<MediaProvider>();

    // Top spotlight items for HeroBanner
    final spotlightItems = mediaProvider.trendingTV.isNotEmpty
        ? mediaProvider.trendingTV
        : (mediaProvider.popularTV.isNotEmpty ? mediaProvider.popularTV : _browseItems);

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: RefreshIndicator(
          color: AppTheme.primaryRed,
          backgroundColor: const Color(0xFF16161E),
          onRefresh: () async {
            await Future.wait([
              mediaProvider.fetchHomeData(),
              _loadCuratedRows(),
              _fetchBrowsePage(reset: true),
            ]);
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Hero Spotlight Banner
                if (spotlightItems.isNotEmpty)
                  HeroBanner(items: spotlightItems)
                else
                  const SizedBox(height: 60),

                const SizedBox(height: 10),

                // Curated Category Rows (Home-like Experience)
                if (mediaProvider.popularTV.isNotEmpty)
                  Top10Row(
                    title: 'Top 10 TV Shows Today',
                    items: mediaProvider.popularTV,
                    forceType: 'tv',
                  ),

                if (mediaProvider.trendingTV.isNotEmpty)
                  MediaRow(
                    title: 'Trending Series',
                    items: mediaProvider.trendingTV,
                    forceType: 'tv',
                  ),

                if (mediaProvider.topRatedTV.isNotEmpty)
                  MediaRow(
                    title: 'Critically Acclaimed Series',
                    items: mediaProvider.topRatedTV,
                    forceType: 'tv',
                  ),

                if (mediaProvider.crimeTV.isNotEmpty)
                  MediaRow(
                    title: 'Crime & Mystery Series',
                    items: mediaProvider.crimeTV,
                    forceType: 'tv',
                  ),

                if (_scifiSeries.isNotEmpty)
                  MediaRow(
                    title: 'Sci-Fi & Fantasy Series',
                    items: _scifiSeries,
                    forceType: 'tv',
                  ),

                if (_comedySeries.isNotEmpty)
                  MediaRow(
                    title: 'Comedy Series',
                    items: _comedySeries,
                    forceType: 'tv',
                  ),

                if (_actionSeries.isNotEmpty)
                  MediaRow(
                    title: 'Action & Adventure',
                    items: _actionSeries,
                    forceType: 'tv',
                  ),

                if (_dramaSeries.isNotEmpty)
                  MediaRow(
                    title: 'Gripping Dramas',
                    items: _dramaSeries,
                    forceType: 'tv',
                  ),

                const SizedBox(height: 24),

                // ═══════════════════════════════════════════════════════════
                // NEVER-ENDING / INFINITE SCROLL BROWSE SECTION
                // ═══════════════════════════════════════════════════════════
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BROWSE ALL TV SERIES',
                            style: GoogleFonts.bebasNeue(
                              fontSize: isTv ? 32 : 24,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'Never-ending catalog with real-time infinite scroll',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      // Sort Dropdown Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E28),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSort,
                            dropdownColor: const Color(0xFF1E1E28),
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            onChanged: (val) {
                              if (val != null) _onSortSelected(val);
                            },
                            items: _sortOptions.map((opt) {
                              return DropdownMenuItem<String>(
                                value: opt['value'],
                                child: Text(opt['label']!),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Genre Filter Chips
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _genres.length,
                    itemBuilder: (context, index) {
                      final g = _genres[index];
                      final isSelected = _selectedGenreId == g['id'];
                      final chip = Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryRed : const Color(0xFF1A1A24),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryRed : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            g['name'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      );

                      if (isTv) {
                        return TvFocusable(
                          onPressed: () => _onGenreSelected(g['id'] as int?),
                          borderRadius: BorderRadius.circular(20),
                          child: chip,
                        );
                      }
                      return GestureDetector(
                        onTap: () => _onGenreSelected(g['id'] as int?),
                        child: chip,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Never-Ending Grid Content
                if (_isLoadingInitial)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primaryRed)),
                  )
                else if (_browseItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No TV series found', style: TextStyle(color: Colors.white60))),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final targetWidth = isTv ? 190.0 : 115.0;
                      final count = (constraints.maxWidth / targetWidth).floor().clamp(3, 8);

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: isTv ? 12 : 8,
                          mainAxisSpacing: isTv ? 14 : 10,
                        ),
                        itemCount: _browseItems.length,
                        itemBuilder: (context, index) {
                          return MediaCard(item: _browseItems[index], forceType: 'tv');
                        },
                      );
                    },
                  ),

                // Bottom Infinite Scroll Spinner or End Notice
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: _isLoadingMore
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryRed),
                          )
                        : (!_hasMore && _browseItems.isNotEmpty
                            ? const Text(
                                'You have reached the end of the catalogue',
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              )
                            : const SizedBox.shrink()),
                  ),
                ),

                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
