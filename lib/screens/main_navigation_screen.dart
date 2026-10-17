import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/constants/theme_constants.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/tv_mode_service.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/admin_modals.dart';
import '../widgets/brand_header.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_switcher_sheet.dart';
import 'anime_screen.dart';
import 'clips_screen.dart';
import 'downloads_screen.dart';
import 'drama_screen.dart';
import 'home_screen.dart';
import 'kids_screen.dart';
import 'live_tv_screen.dart';
import 'movies_screen.dart';
import 'my_netflix_screen.dart';
import 'new_popular_screen.dart';
import 'search_screen.dart';
import 'series_screen.dart';
import 'tv_leanback_screen.dart';
import 'update_required_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _activeCategoryIndex = 0; // 0: Home, 1: Series, 2: Films, 3: New & Hot, etc.
  int _bottomTabIndex = 0; // 0: Home, 1: Clips, 2: Search, 3: My Voidflix

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (RemoteConfigService.isUpdateAvailable) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UpdateRequiredScreen()),
        );
      } else {
        AdminModals.checkAndShowModals(context);
      }
    });
  }

  final List<Widget> _categoryScreens = const [
    HomeScreen(),
    SeriesScreen(),
    MoviesScreen(),
    NewPopularScreen(),
    AnimeScreen(),
    DramaScreen(),
    LiveTvScreen(),
    KidsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tvMode = context.watch<TvModeService>();
    if (tvMode.isTvMode) {
      return const TvLeanbackScreen();
    }

    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS || MediaQuery.of(context).size.width >= 850);

    Widget bodyContent;
    if (_bottomTabIndex == 1) {
      bodyContent = const ClipsScreen();
    } else if (_bottomTabIndex == 2) {
      bodyContent = const SearchScreen();
    } else if (_bottomTabIndex == 3) {
      bodyContent = const MyVoidflixScreen();
    } else {
      bodyContent = _categoryScreens[_activeCategoryIndex.clamp(0, _categoryScreens.length - 1)];
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: isDesktop
          ? _buildDesktopTopBar(context)
          : (_bottomTabIndex == 0
              ? BrandHeader(
                  activeCategoryIndex: _activeCategoryIndex,
                  onCategorySelected: (idx) {
                    setState(() {
                      _activeCategoryIndex = idx;
                      _bottomTabIndex = 0;
                    });
                  },
                  onSearchTap: () {
                    setState(() => _bottomTabIndex = 2);
                  },
                )
              : null),
      body: Stack(
        children: [
          // Screen body content
          Positioned.fill(
            child: bodyContent,
          ),

          // Mobile Floating Pill Bottom Bar (Only on phones/tablets; hidden on PC desktop)
          if (!isDesktop)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: FloatingBottomBar(
                currentIndex: _bottomTabIndex,
                onTap: (idx) {
                  setState(() => _bottomTabIndex = idx);
                },
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildDesktopTopBar(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final notifProvider = context.watch<NotificationProvider>();
    final activeProfile = profileProvider.activeProfile;
    final unreadCount = notifProvider.unreadCount;

    final navLinks = [
      {'label': 'Home', 'cat': 0, 'tab': 0},
      {'label': 'Series', 'cat': 1, 'tab': 0},
      {'label': 'Films', 'cat': 2, 'tab': 0},
      {'label': 'New & Popular', 'cat': 3, 'tab': 0},
      {'label': 'Anime', 'cat': 4, 'tab': 0},
      {'label': 'Drama', 'cat': 5, 'tab': 0},
      {'label': 'Live TV', 'cat': 6, 'tab': 0},
      {'label': 'Clips', 'cat': 0, 'tab': 1},
      {'label': 'Search', 'cat': 0, 'tab': 2},
      {'label': 'My List', 'cat': 0, 'tab': 3},
    ];

    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.96),
          border: const Border(bottom: BorderSide(color: Color(0xFF1E1E2C), width: 1)),
        ),
        child: Row(
          children: [
            // Voidflix Logo
            GestureDetector(
              onTap: () {
                setState(() {
                  _activeCategoryIndex = 0;
                  _bottomTabIndex = 0;
                });
              },
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'VOID',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryRed,
                        letterSpacing: 2.0,
                      ),
                    ),
                    TextSpan(
                      text: 'FLIX',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 28),

            // Horizontal Desktop Navigation Tabs
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: navLinks.map((link) {
                    final isSelected = (_bottomTabIndex == 0 &&
                            link['tab'] == 0 &&
                            _activeCategoryIndex == link['cat']) ||
                        (_bottomTabIndex != 0 && _bottomTabIndex == link['tab']);
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          _activeCategoryIndex = link['cat'] as int;
                          _bottomTabIndex = link['tab'] as int;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          link['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // TV Mode 10-Foot Button
            InkWell(
              onTap: () => TvModeService().setTvMode(true),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00D2FF).withValues(alpha: 0.5), width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tv_rounded, color: Color(0xFF00D2FF), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'TV Mode',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Downloads Button
            IconButton(
              icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 22),
              tooltip: 'Downloads',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
              },
            ),

            // Notifications
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                  tooltip: 'Notifications',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          const FractionallySizedBox(heightFactor: 0.75, child: NotificationsSheet()),
                    );
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: AppTheme.primaryRed, shape: BoxShape.circle),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),

            // Profile Avatar
            GestureDetector(
              onTap: () => ProfileSwitcherSheet.show(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ProfileAvatarTile.fromProfile(profile: activeProfile, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
