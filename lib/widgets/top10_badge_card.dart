import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import '../screens/detail_screen.dart';

class Top10BadgeCard extends StatelessWidget {
  final int rank;
  final MediaItem item;

  const Top10BadgeCard({
    super.key,
    required this.rank,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final posterUrl = ApiConstants.getImageUrl(item.posterPath, size: 'w500');

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailScreen(mediaId: item.id, mediaType: item.mediaType),
          ),
        );
      },
      child: Container(
        width: 175,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            // Big stylized rank number outline/fill
            Positioned(
              left: 0,
              bottom: -15,
              child: Text(
                '$rank',
                style: GoogleFonts.bebasNeue(
                  fontSize: 110,
                  fontWeight: FontWeight.w900,
                  color: Colors.transparent,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: 1,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 4,
              bottom: -15,
              child: Text(
                '$rank',
                style: GoogleFonts.bebasNeue(
                  fontSize: 110,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = const Color(0xFF6A6A80),
                ),
              ),
            ),

            // Poster card positioned to the right of the rank number
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: AppTheme.surfaceVariant),
                        errorWidget: (context, url, error) => Container(
                          color: AppTheme.surfaceVariant,
                          child: Center(
                            child: Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      )
                    : Container(color: AppTheme.surfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
