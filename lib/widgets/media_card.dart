import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import 'detail_modal.dart';

class MediaCard extends StatelessWidget {
  final MediaItem item;
  final String? forceType;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const MediaCard({
    super.key,
    required this.item,
    this.forceType,
    this.width,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveType = forceType ?? item.mediaType;
    final effectiveItem = MediaItem(
      id: item.id,
      title: item.title,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      overview: item.overview,
      voteAverage: item.voteAverage,
      releaseDate: item.releaseDate,
      mediaType: effectiveType,
      genreIds: item.genreIds,
    );

    final posterUrl = ApiConstants.getImageUrl(item.posterPath, size: 'w500');
    final match = item.voteAverage > 0
        ? (item.voteAverage * 10).round().clamp(75, 99)
        : null;

    Widget cardContent = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: posterUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: const Color(0xFF222222)),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF222222),
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text(
                    item.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF222222),
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),

          // Bottom gradient overlay with title & match %
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (match != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      '$match% Match',
                      style: const TextStyle(
                        color: AppTheme.matchGreen,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else {
          DetailModal.show(context, effectiveItem);
        }
      },
      child: cardContent,
    );
  }
}
