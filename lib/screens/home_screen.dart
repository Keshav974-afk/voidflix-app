import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import '../widgets/top10_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategoryFilter = 'All'; // 'All', 'TV Shows', 'Movies'

  void _showCategoriesPicker(BuildContext context, MediaProvider mediaProvider) {
    final categories = [
      {'name': 'All', 'type': 'all', 'id': 0},
      {'name': 'Action & Adventure', 'type': 'movie', 'id': 28},
      {'name': 'Anime & Animation', 'type': 'tv', 'id': 16},
      {'name': 'Comedy Hits', 'type': 'movie', 'id': 35},
      {'name': 'Critically Acclaimed', 'type': 'movie', 'id': 18},
      {'name': 'Documentaries', 'type': 'movie', 'id': 99},
      {'name': 'Horror & Paranormal', 'type': 'movie', 'id': 27},
      {'name': 'K-Drama & Asian Series', 'type': 'tv', 'id': 10759},
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
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        if (mediaProvider.isLoadingHome && mediaProvider.trending.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryRed),
          );
        }

        if (mediaProvider.error != null && mediaProvider.trending.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: AppTheme.primaryRed, size: 48),
                const SizedBox(height: 16),
                const Text('Failed to load content', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => mediaProvider.fetchHomeData(),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppTheme.primaryRed,
          backgroundColor: AppTheme.surfaceVariant,
          onRefresh: () => mediaProvider.fetchHomeData(),
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
                        onTap: () => _showCategoriesPicker(context, mediaProvider),
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

                // 2. Hero Banner (Spotlight)
                if (mediaProvider.trending.isNotEmpty && _selectedCategoryFilter == 'All')
                  HeroBanner(items: mediaProvider.trending)
                else if (mediaProvider.trendingTV.isNotEmpty && _selectedCategoryFilter == 'TV Shows')
                  HeroBanner(items: mediaProvider.trendingTV)
                else if (mediaProvider.popularMovies.isNotEmpty && _selectedCategoryFilter == 'Movies')
                  HeroBanner(items: mediaProvider.popularMovies),

                const SizedBox(height: 6),

                // 3. Continue Watching (isolated per active profile!)
                const ContinueWatchingRow(),

                // 4. Content Sections based on category filter
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

                if (_selectedCategoryFilter == 'All' || _selectedCategoryFilter == 'Movies') ...[
                  Top10Row(
                    title: 'Top 10 Movies Today',
                    items: mediaProvider.popularMovies,
                    forceType: 'movie',
                  ),

                  MediaRow(
                    title: 'Blockbuster Action & Adventure',
                    items: mediaProvider.actionMovies.isNotEmpty
                        ? mediaProvider.actionMovies
                        : mediaProvider.popularMovies,
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
}
