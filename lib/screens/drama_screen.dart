import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../widgets/media_card.dart';
import '../widgets/media_row.dart';

class DramaScreen extends StatelessWidget {
  const DramaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        final drama = mediaProvider.asianDrama;

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
                        const Icon(Icons.favorite, color: AppTheme.primaryRed, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'K-DRAMA & ASIAN SERIES',
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
                      'Captivating Korean romances, thrilling historical sagas, and top trending Asian dramas.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // Trending K-Drama Row
              MediaRow(
                title: 'Spotlight K-Dramas',
                items: drama,
              ),

              // Grid of all Dramas
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'Explore All Dramas',
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
                    itemCount: drama.length,
                    itemBuilder: (context, index) {
                      return MediaCard(item: drama[index], forceType: 'tv');
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
