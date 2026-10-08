import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../providers/notification_provider.dart';
import '../screens/detail_screen.dart';

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProvider, child) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active, color: AppTheme.primaryRed, size: 22),
                        const SizedBox(width: 10),
                        const Text(
                          'New Updates & Releases',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => notifProvider.markAllAsRead(),
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border),

              // Notifications List
              if (notifProvider.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppTheme.primaryRed),
                )
              else if (notifProvider.notifications.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'No new updates right now',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: notifProvider.notifications.length,
                    separatorBuilder: (c, i) => const Divider(color: AppTheme.border),
                    itemBuilder: (ctx, idx) {
                      final item = notifProvider.notifications[idx];
                      final media = item.mediaItem;
                      final posterUrl = media != null
                          ? ApiConstants.getImageUrl(media.posterPath, size: 'w200')
                          : '';

                      return InkWell(
                        onTap: () {
                          if (media != null) {
                            Navigator.pop(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DetailScreen(
                                  mediaId: media.id,
                                  mediaType: media.mediaType,
                                ),
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Poster or Icon
                              if (posterUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(
                                    imageUrl: posterUrl,
                                    width: 50,
                                    height: 75,
                                    fit: BoxFit.cover,
                                    placeholder: (c, u) => Container(color: AppTheme.cardColor),
                                  ),
                                )
                              else
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.movie, color: AppTheme.primaryRed),
                                ),
                              const SizedBox(width: 14),

                              // Text info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (!item.isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: AppTheme.primaryRed,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.message,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
