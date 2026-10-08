import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/media_item.dart';
import 'media_card.dart';

class Top10Row extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final String? forceType;

  const Top10Row({
    super.key,
    required this.title,
    required this.items,
    this.forceType,
  });

  @override
  Widget build(BuildContext context) {
    final top = items.take(10).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 185,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: top.length,
            itemBuilder: (context, index) {
              final rank = index + 1;
              final item = top[index];

              return Container(
                width: 175,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomLeft,
                  children: [
                    // Giant Outlined Rank Number behind poster
                    Positioned(
                      left: -2,
                      bottom: -18,
                      child: Text(
                        '$rank',
                        style: GoogleFonts.bebasNeue(
                          fontSize: 125,
                          fontWeight: FontWeight.w900,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 3.5
                            ..color = const Color(0xFF5E5E6E),
                        ),
                      ),
                    ),

                    // Poster card positioned to the right of the numeral
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: MediaCard(
                        item: item,
                        forceType: forceType,
                        width: 115,
                        height: 180,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
