import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../providers/notification_provider.dart';
import '../screens/detail_screen.dart';

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProvider, child) {
        final notifications = notifProvider.notifications;
        final unreadCount = notifProvider.unreadCount;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F14),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // Drag handle
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryRed, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryRed,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          if (unreadCount > 0)
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => notifProvider.markAllAsRead(),
                              child: const Text(
                                'Mark read',
                                style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (notifications.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: Colors.white54,
                              ),
                              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                              label: const Text(
                                'Clear all',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              onPressed: () => notifProvider.clearAllNotifications(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Notifications List or Loading / Empty States
                if (notifProvider.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(color: AppTheme.primaryRed, strokeWidth: 2.5),
                  )
                else if (notifications.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.notifications_off_outlined, color: Colors.white38, size: 28),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'All Caught Up',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'No new updates or alerts right now.\nOld notifications were cleared.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: notifications.length,
                      separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 12),
                      itemBuilder: (ctx, idx) {
                        final item = notifications[idx];
                        final media = item.mediaItem;
                        final posterUrl = media != null
                            ? ApiConstants.getImageUrl(media.posterPath, size: 'w200')
                            : (item.imageUrl ?? '');

                        return Dismissible(
                          key: Key(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                SizedBox(width: 6),
                                Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
                              ],
                            ),
                          ),
                          onDismissed: (_) {
                            notifProvider.deleteNotification(item.id);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: item.isRead ? Colors.transparent : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail / Icon
                                if (posterUrl.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: posterUrl,
                                      width: 48,
                                      height: 70,
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(color: const Color(0xFF1E1E28)),
                                      errorWidget: (c, u, e) => Container(
                                        width: 48,
                                        height: 70,
                                        color: const Color(0xFF1E1E28),
                                        child: const Icon(Icons.movie_rounded, color: AppTheme.primaryRed, size: 22),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: item.isAdminBroadcast
                                          ? AppTheme.primaryRed.withValues(alpha: 0.15)
                                          : const Color(0xFF1E1E28),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      item.isAdminBroadcast ? Icons.campaign_rounded : Icons.notifications_rounded,
                                      color: AppTheme.primaryRed,
                                      size: 22,
                                    ),
                                  ),
                                const SizedBox(width: 12),

                                // Main text content
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
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
                                      } else if (item.deepLink != null && item.deepLink!.isNotEmpty) {
                                        Navigator.pop(context);
                                        final link = item.deepLink!;
                                        if (link.startsWith('http')) {
                                          launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
                                        } else if (link.contains('/watch/')) {
                                          final parts = link.split('/');
                                          final typeIndex = parts.indexOf('watch') + 1;
                                          if (typeIndex < parts.length - 1) {
                                            final type = parts[typeIndex];
                                            final id = int.tryParse(parts[typeIndex + 1]) ?? 0;
                                            if (id > 0) {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => DetailScreen(mediaId: id, mediaType: type),
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      }
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            if (item.isAdminBroadcast)
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 2),
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryRed,
                                                  borderRadius: BorderRadius.circular(3),
                                                ),
                                                child: const Text(
                                                  'ANNOUNCEMENT',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              _formatRelativeTime(item.timestamp),
                                              style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.title,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            ),
                                            if (!item.isRead) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: AppTheme.primaryRed,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.message,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                            height: 1.3,
                                          ),
                                        ),
                                        if (item.deepLink != null && item.deepLink!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Tap to open: ${item.deepLink}',
                                              style: const TextStyle(
                                                color: AppTheme.primaryRed,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Direct 1-tap delete button
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 16),
                                  tooltip: 'Delete notification',
                                  padding: const EdgeInsets.only(left: 6),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    notifProvider.deleteNotification(item.id);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
