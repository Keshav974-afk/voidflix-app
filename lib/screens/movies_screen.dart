import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import '../widgets/media_card.dart';

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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Sort
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MOVIES & FILMS',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 34,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Sort', style: TextStyle(color: Colors.white, fontSize: 12)),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                      ],
                    ),
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

          // Genre Chips Horizontal List
          if (_genres.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  GestureDetector(
                    onTap: () => _filterByGenre(null),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedGenreId == null ? AppTheme.primaryRed : const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedGenreId == null ? AppTheme.primaryRed : Colors.white24,
                        ),
                      ),
                      child: Text(
                        'All',
                        style: TextStyle(
                          color: _selectedGenreId == null ? Colors.white : Colors.white70,
                          fontWeight: _selectedGenreId == null ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  ..._genres.map((g) {
                    final isSel = _selectedGenreId == g['id'];
                    return GestureDetector(
                      onTap: () => _filterByGenre(isSel ? null : g['id']),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? AppTheme.primaryRed : const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSel ? AppTheme.primaryRed : Colors.white24,
                          ),
                        ),
                        child: Text(
                          g['name'],
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // Movie Grid
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryRed),
              ),
            )
          else if (_movies.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text('No movies found', style: TextStyle(color: Colors.white70)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final count = (constraints.maxWidth / 130).floor().clamp(3, 8);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _movies.length,
                  itemBuilder: (context, index) {
                    return MediaCard(item: _movies[index], forceType: 'movie');
                  },
                );
              },
            ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }
}
