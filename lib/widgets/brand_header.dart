import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import 'notifications_sheet.dart';
import 'profile_avatar.dart';
import 'profile_switcher_sheet.dart';

class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  final int activeCategoryIndex;
  final Function(int) onCategorySelected;
  final VoidCallback? onSearchTap;

  const BrandHeader({
    super.key,
    required this.activeCategoryIndex,
    required this.onCategorySelected,
    this.onSearchTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(102);

  void _openNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.75,
        child: NotificationsSheet(),
      ),
    );
  }

  void _openDownloads(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(Icons.file_download_outlined, color: AppTheme.primaryRed, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Smart Downloads',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Downloaded movies and episodes are stored offline for instant playback anywhere.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoriesSheet(BuildContext context) {
    final allCategories = [
      {'name': 'All Categories', 'index': 0},
      {'name': 'TV Shows', 'index': 1},
      {'name': 'Movies', 'index': 2},
      {'name': 'New & Hot', 'index': 3},
      {'name': 'Anime', 'index': 4},
      {'name': 'Drama', 'index': 5},
      {'name': 'Action & Adventure', 'index': 2},
      {'name': 'Comedies', 'index': 2},
      {'name': 'Sci-Fi & Fantasy', 'index': 2},
      {'name': 'Horror', 'index': 2},
      {'name': 'Documentaries', 'index': 1},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withValues(alpha: 0.94),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Categories',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: allCategories.length,
                itemBuilder: (context, index) {
                  final cat = allCategories[index];
                  final isSel = activeCategoryIndex == cat['index'];
                  return ListTile(
                    title: Center(
                      child: Text(
                        cat['name'] as String,
                        style: TextStyle(
                          color: isSel ? AppTheme.primaryRed : Colors.white,
                          fontSize: 16,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onCategorySelected(cat['index'] as int);
                    },
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showGamesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(Icons.sports_esports, color: AppTheme.primaryRed, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Voidflix Games',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Explore exclusive mobile games and interactive stories included with your Voidflix membership. No ads, no extra fees.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Explore Games', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final notifProvider = context.watch<NotificationProvider>();
    final activeProfile = profileProvider.activeProfile;
    final unreadCount = notifProvider.unreadCount;

    // Category chips matching Netflix mobile (Screenshot 2)
    final chipData = [
      {'label': 'Shows', 'target': 1},
      {'label': 'Movies', 'target': 2},
      {'label': 'Games', 'target': -3},
      {'label': 'New & Hot', 'target': 3},
      {'label': 'Anime', 'target': 4},
      {'label': 'Categories', 'target': -1},
    ];

    String categoryTitle = 'Home';
    if (activeCategoryIndex == 1) categoryTitle = 'Shows';
    if (activeCategoryIndex == 2) categoryTitle = 'Movies';
    if (activeCategoryIndex == 3) categoryTitle = 'New & Hot';
    if (activeCategoryIndex == 4) categoryTitle = 'Anime';
    if (activeCategoryIndex == 5) categoryTitle = 'Drama';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.95),
            Colors.black.withValues(alpha: 0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Logo + Active Title | Download + Bell + Profile (Screenshot 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  // Red VOID Logo + "Home" / Active Category Title
                  GestureDetector(
                    onTap: () => onCategorySelected(0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'VOID',
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryRed,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              TextSpan(
                                text: 'FLIX',
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (activeCategoryIndex > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            categoryTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Download icon (Screenshot 2)
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 23),
                    tooltip: 'Downloads',
                    onPressed: () => _openDownloads(context),
                  ),

                  // Notifications Bell with Badge (Screenshot 2)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 23),
                        tooltip: 'Notifications',
                        onPressed: () => _openNotifications(context),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryRed,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$unreadCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Profile Avatar (Screenshot 2 / Tap opens ProfileSwitcherSheet Screenshot 3)
                  GestureDetector(
                    onTap: () => ProfileSwitcherSheet.show(context),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ProfileAvatarTile.fromProfile(
                          profile: activeProfile,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal category chips (Shows, Movies, Games, New & Hot, Anime, Categories ▾)
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: chipData.length,
                itemBuilder: (context, index) {
                  final chip = chipData[index];
                  final label = chip['label'] as String;
                  final target = chip['target'] as int;
                  final isCategories = target == -1;
                  final isGames = target == -3;
                  final isSel = activeCategoryIndex == target;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (isCategories) {
                          _showCategoriesSheet(context);
                        } else if (isGames) {
                          _showGamesSheet(context);
                        } else {
                          // Toggle: if already selected, go back to Home (0)
                          if (isSel) {
                            onCategorySelected(0);
                          } else {
                            onCategorySelected(target);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.white : Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isSel ? '$label ✕' : label,
                                style: TextStyle(
                                  color: isSel ? Colors.black : Colors.white.withValues(alpha: 0.9),
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                              if (isCategories) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
