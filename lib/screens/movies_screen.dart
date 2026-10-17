import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/tv_mode_service.dart';
import '../models/media_item.dart';
import '../widgets/media_card.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  final ApiService _apiService = ApiService();
  List<MediaItem> _movies = [];
  List<Map<String, dynamic>> _genres = [];
  int? _selectedGenreId;
  String _selectedSort = 'popularity.desc';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final genres = await _apiService.getGenres('movie');
      final movies = await _apiService.getPopularMovies();
      if (mounted) {
        setState(() {
          _genres = genres;
          _movies = movies;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _filterByGenre(int? genreId) async {
    setState(() {
      _selectedGenreId = genreId;
      _isLoading = true;
    });
    try {
      List<MediaItem> items;
      if (genreId == null) {
        items = _selectedSort == 'popularity.desc'
            ? await _apiService.getPopularMovies()
            : await _apiService.getTopRatedMovies();
      } else {
        items = await _apiService.discoverByGenre('movie', genreId);
      }
      if (mounted) {
        setState(() {
          _movies = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setSort(String sort) async {
    setState(() {
      _selectedSort = sort;
      _isLoading = true;
    });
    try {
      final items = sort == 'popularity.desc'
          ? await _apiService.getPopularMovies()
          : await _apiService.getTopRatedMovies();
      if (mounted) setState(() { _movies = items; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final isTv = TvModeService().isTvMode;

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: isTv ? _buildTvLayout(context, canPop) : _buildMobileLayout(context, canPop),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TV LAYOUT — D-pad navigable genre chips + large grid
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTvLayout(BuildContext context, bool canPop) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
            child: Row(
              children: [
                if (canPop) ...[
                  TvBackButton(onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 20),
                ],
                const Icon(Icons.movie_outlined, color: AppTheme.primaryRed, size: 32),
                const SizedBox(width: 10),
                Text('MOVIES & FILMS',
                    style: GoogleFonts.bebasNeue(fontSize: 38, letterSpacing: 2, color: Colors.white)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Genre chips row (D-pad focusable)
          if (_genres.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                children: [
                  _TvGenreChip(
                    label: 'All',
                    isSelected: _selectedGenreId == null,
                    onPressed: () => _filterByGenre(null),
                  ),
                  ..._genres.map((g) => _TvGenreChip(
                        label: g['name'] as String,
                        isSelected: _selectedGenreId == g['id'],
                        onPressed: () => _filterByGenre(_selectedGenreId == g['id'] ? null : g['id'] as int),
                      )),
                ],
              ),
            ),

          // Sort row
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 14),
            child: Row(
              children: [
                const Text('Sort: ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                _TvSortButton(
                  label: 'Most Popular',
                  isSelected: _selectedSort == 'popularity.desc',
                  onPressed: () => _setSort('popularity.desc'),
                ),
                const SizedBox(width: 10),
                _TvSortButton(
                  label: 'Highest Rated',
                  isSelected: _selectedSort == 'vote_average.desc',
                  onPressed: () => _setSort('vote_average.desc'),
                ),
              ],
            ),
          ),

          // Grid
          Expanded(child: _buildGrid(isTv: true)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MOBILE LAYOUT (original behavior)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMobileLayout(BuildContext context, bool canPop) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canPop) ...[
                      const TvBackButton(),
                      const SizedBox(width: 12),
                    ],
                    Text('MOVIES & FILMS',
                        style: GoogleFonts.bebasNeue(fontSize: 34, letterSpacing: 1.5, color: Colors.white)),
                  ],
                ),
                PopupMenuButton<String>(
                  color: const Color(0xFF222222),
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Sort', style: TextStyle(color: Colors.white, fontSize: 12)),
                      SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                    ]),
                  ),
                  onSelected: (val) {
                    setState(() => _selectedSort = val);
                    _filterByGenre(_selectedGenreId);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'popularity.desc', child: Text('Most Popular')),
                    const PopupMenuItem(value: 'vote_average.desc', child: Text('Highest Rated')),
                  ],
                ),
              ],
            ),
          ),
          if (_genres.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _MobileGenreChip(label: 'All', isSelected: _selectedGenreId == null, onTap: () => _filterByGenre(null)),
                  ..._genres.map((g) => _MobileGenreChip(
                        label: g['name'] as String,
                        isSelected: _selectedGenreId == g['id'],
                        onTap: () => _filterByGenre(_selectedGenreId == g['id'] ? null : g['id'] as int),
                      )),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _buildGrid(isTv: false),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildGrid({required bool isTv}) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryRed)),
      );
    }
    if (_movies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: Text('No movies found', style: TextStyle(color: Colors.white70))),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // TV: larger cards (around 200px wide), mobile: smaller (130px)
        final targetWidth = isTv ? 200.0 : 130.0;
        final count = (constraints.maxWidth / targetWidth).floor().clamp(isTv ? 4 : 3, isTv ? 8 : 8);
        final grid = GridView.builder(
          shrinkWrap: !isTv,
          physics: isTv ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: isTv ? 24 : 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            childAspectRatio: 0.65,
            crossAxisSpacing: isTv ? 14 : 10,
            mainAxisSpacing: isTv ? 16 : 12,
          ),
          itemCount: _movies.length,
          itemBuilder: (context, index) => MediaCard(item: _movies[index], forceType: 'movie'),
        );
        return grid;
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TV Genre Chip (D-Pad focusable)
// ═══════════════════════════════════════════════════════════════

class _TvGenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _TvGenreChip({required this.label, required this.isSelected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TvFocusable(
        scaleFactor: 1.06,
        glowColor: AppTheme.primaryRed,
        borderRadius: BorderRadius.circular(28),
        onPressed: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryRed : const Color(0xFF1E1E28),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: isSelected ? AppTheme.primaryRed : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TV Sort Button
// ═══════════════════════════════════════════════════════════════

class _TvSortButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _TvSortButton({required this.label, required this.isSelected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scaleFactor: 1.05,
      glowColor: AppTheme.primaryRed,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryRed.withValues(alpha: 0.25) : const Color(0xFF1E1E28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.primaryRed : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Mobile Genre Chip (touch-only)
// ═══════════════════════════════════════════════════════════════

class _MobileGenreChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MobileGenreChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryRed : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryRed : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
