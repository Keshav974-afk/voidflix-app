import 'package:flutter/material.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import 'media_card.dart';

class MediaRow extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final String? forceType;
  final VoidCallback? onSeeAll;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.forceType,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: const Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryRed,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return MediaCard(
                item: items[index],
                forceType: forceType,
                width: 130,
                height: 195,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
