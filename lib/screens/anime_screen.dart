import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../widgets/media_card.dart';
import '../widgets/media_row.dart';

class AnimeScreen extends StatelessWidget {
  const AnimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        final anime = mediaProvider.anime;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: AppTheme.primaryRed, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'ANIME CENTRAL',
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
                      'Shonen, Isekai, Dark Fantasy, and classic Japanese animation streaming in full HD.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Trending Anime Row
              MediaRow(
                title: 'Trending Anime Series',
                items: anime,
              ),

              // Shonen & Action Spotlight
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'Explore All Anime',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
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
                    itemCount: anime.length,
                    itemBuilder: (context, index) {
                      return MediaCard(item: anime[index], forceType: 'tv');
                    },
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
