import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../widgets/media_row.dart';
import '../widgets/top10_row.dart';

class NewPopularScreen extends StatelessWidget {
  const NewPopularScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department, color: AppTheme.primaryRed, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'NEW & POPULAR',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 34,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'What everyone\'s watching right now — fresh releases, trending titles, and coming soon.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Trending This Week
              MediaRow(
                title: 'Trending This Week',
                items: mediaProvider.trending,
              ),

              // Top 10 Movies Today
              Top10Row(
                title: 'Top 10 Movies Today',
                items: mediaProvider.popularMovies,
                forceType: 'movie',
              ),

              // Top 10 TV Shows Today
              Top10Row(
                title: 'Top 10 TV Shows Today',
                items: mediaProvider.popularTV,
                forceType: 'tv',
              ),

              // Critically Acclaimed
              MediaRow(
                title: 'Critically Acclaimed Movies',
                items: mediaProvider.topRatedMovies,
              ),

              // Binge-Worthy Series
              MediaRow(
                title: 'Binge-Worthy Series',
                items: mediaProvider.topRatedTV,
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
