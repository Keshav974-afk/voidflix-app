import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/remote_config_service.dart';

class AdminModals {
  static bool _hasCheckedThisSession = false;

  /// Checks for App Updates & Popup Banners from Mission Control on app launch
  static Future<void> checkAndShowModals(BuildContext context) async {
    if (_hasCheckedThisSession || !context.mounted) return;
    _hasCheckedThisSession = true;

    // Fetch latest config from Cloudflare
    await RemoteConfigService.fetchConfig();
    if (!context.mounted) return;

    // 1. Maintenance Mode Check
    if (RemoteConfigService.maintenanceMode) {
      _showMaintenanceDialog(context);
      return;
    }

    // 2. App Update Check
    if (RemoteConfigService.isUpdateAvailable) {
      _showUpdateDialog(context);
      return;
    }

    // 3. Promotional Popup Banner Check
    final banner = RemoteConfigService.activePopupBanner;
    if (banner != null) {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final dismissedKey = 'voidflix_banner_dismissed_${banner.id}_$today';
      final isDismissed = prefs.getBool(dismissedKey) ?? false;

      if (!isDismissed && context.mounted) {
        _showPopupBannerDialog(context, banner, dismissedKey);
      }
    }
  }

  static void _showMaintenanceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.build_circle, color: AppTheme.primaryRed, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Scheduled Maintenance',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  RemoteConfigService.maintenanceMessage ??
                      'Voidflix streaming servers are currently undergoing routine maintenance. Please check back shortly.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showUpdateDialog(BuildContext context) {
    final update = RemoteConfigService.cachedUpdate!;
    final isForced = update.forceUpdate;

    showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (ctx) => PopScope(
        canPop: !isForced,
        child: Dialog(
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW VERSION',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'v${update.version}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  update.title.isNotEmpty ? update.title : 'Voidflix v${update.version} Available',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "What's New:",
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (update.releaseNotes.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: update.releaseNotes
                            .map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ', style: TextStyle(color: AppTheme.primaryRed, fontSize: 13)),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Performance improvements, new streaming servers, and bug fixes.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (!isForced)
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Later', style: TextStyle(color: AppTheme.textSecondary)),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final apkUrl = RemoteConfigService.resolvedApkUrl;
                          launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showPopupBannerDialog(BuildContext context, RemotePromoBanner banner, String dismissedKey) {
    showDialog(
      context: context,
      barrierDismissible: banner.dismissible,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 24, spreadRadius: 4),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Backdrop Image with Close button
                Stack(
                  children: [
                    if (banner.backdropUrl != null || banner.imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: banner.backdropUrl ?? banner.imageUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Container(height: 180, color: Colors.black54),
                        errorWidget: (c, u, e) => Container(
                          height: 120,
                          color: const Color(0xFF221115),
                          alignment: Alignment.center,
                          child: const Icon(Icons.movie_filter, color: AppTheme.primaryRed, size: 48),
                        ),
                      )
                    else
                      Container(
                        height: 120,
                        color: const Color(0xFF221115),
                        alignment: Alignment.center,
                        child: const Icon(Icons.movie_filter, color: AppTheme.primaryRed, size: 48),
                      ),
                    // Gradient overlay
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent, Color(0xFF14141E)],
                          ),
                        ),
                      ),
                    ),
                    // Close button
                    if (banner.dismissible)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () {
                            SharedPreferences.getInstance().then((p) => p.setBool(dismissedKey, true));
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                    // Badge
                    Positioned(
                      bottom: 12,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          banner.badge.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quality & Rating Chips
                      if (banner.qualityBadge != null || banner.rating != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              if (banner.rating != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white38),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    banner.rating!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                                  ),
                                ),
                              if (banner.qualityBadge != null)
                                Text(
                                  banner.qualityBadge!,
                                  style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                        ),

                      Text(
                        banner.title,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        banner.subtitle,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 18),

                      // CTA Actions
                      Row(
                        children: [
                          if (banner.dismissible)
                            Expanded(
                              child: TextButton(
                                onPressed: () {
                                  SharedPreferences.getInstance().then((p) => p.setBool(dismissedKey, true));
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Maybe Later', style: TextStyle(color: AppTheme.textSecondary)),
                              ),
                            ),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryRed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                SharedPreferences.getInstance().then((p) => p.setBool(dismissedKey, true));
                                Navigator.pop(ctx);
                                final url = banner.actionUrl;
                                if (url.startsWith('http')) {
                                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                } else if (url.contains('.apk')) {
                                  launchUrl(Uri.parse('https://voidflix.org$url'), mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Text(
                                banner.actionText,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
