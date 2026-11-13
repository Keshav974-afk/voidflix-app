import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/constants/theme_constants.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/tv_mode_service.dart';
import '../core/services/voidcast_service.dart';
import '../models/media_item.dart';
import '../providers/media_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/admin_modals.dart';
import '../widgets/brand_header.dart';
import '../widgets/detail_modal.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_switcher_sheet.dart';
import '../widgets/voidcast_remote_sheet.dart';
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
import 'watchlist_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _activeCategoryIndex = 0; // 0: Home, 1: Series, 2: Films, 3: New & Hot, etc.
  int _bottomTabIndex = 0; // 0: Home, 1: Clips, 2: Search, 3: My Voidflix

  final TextEditingController _desktopSearchController = TextEditingController();
  final FocusNode _desktopSearchFocusNode = FocusNode();
  bool _isSearchFocused = false;
  String _currentSearchQuery = '';

  // Lazy instantiate screens only on first visit to keep startup fast,
  // while retaining state & scroll positions in memory for instant tab switching!
  final Set<int> _loadedBottomTabs = {0};
  final Set<int> _loadedCategoryTabs = {0};

  @override
  void initState() {
    super.initState();
    _desktopSearchFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isSearchFocused = _desktopSearchFocusNode.hasFocus;
        });
      }
    });
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

  @override
  void dispose() {
    _desktopSearchController.dispose();
    _desktopSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvMode = context.watch<TvModeService>();
    if (tvMode.isTvMode) {
      return const TvLeanbackScreen();
    }

    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS || MediaQuery.of(context).size.width >= 850);

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
                      _loadedCategoryTabs.add(idx);
                      _bottomTabIndex = 0;
                    });
                  },
                  onSearchTap: () {
                    setState(() {
                      _bottomTabIndex = 2;
                      _loadedBottomTabs.add(2);
                    });
                  },
                )
              : null),
      body: Stack(
        children: [
          // Instant-switching lazy preserved screen stack
          Positioned.fill(
            child: IndexedStack(
              index: _bottomTabIndex,
              children: [
                // Tab 0: Categories stack
                IndexedStack(
                  index: _activeCategoryIndex.clamp(0, 8),
                  children: [
                    const HomeScreen(),
                    _loadedCategoryTabs.contains(1) ? const SeriesScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(2) ? const MoviesScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(3) ? const NewPopularScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(4) ? const AnimeScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(5) ? const DramaScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(6) ? const LiveTvScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(7) ? const KidsScreen() : const SizedBox.shrink(),
                    _loadedCategoryTabs.contains(8) ? const WatchlistScreen() : const SizedBox.shrink(),
                  ],
                ),
                // Tab 1: Clips
                _loadedBottomTabs.contains(1) ? ClipsScreen(isActive: _bottomTabIndex == 1) : const SizedBox.shrink(),
                // Tab 2: Search
                _loadedBottomTabs.contains(2) ? SearchScreen(initialQuery: _currentSearchQuery) : const SizedBox.shrink(),
                // Tab 3: My Voidflix
                _loadedBottomTabs.contains(3) ? const MyVoidflixScreen() : const SizedBox.shrink(),
              ],
            ),
          ),

          // Mobile Floating Pill Bottom Bar (Only on phones/tablets; hidden on PC desktop)
          if (!isDesktop)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: RepaintBoundary(
                child: FloatingBottomBar(
                  currentIndex: _bottomTabIndex,
                  onTap: (idx) {
                    setState(() {
                      if (idx == 0) {
                        _activeCategoryIndex = 0;
                      }
                      _bottomTabIndex = idx;
                      _loadedBottomTabs.add(idx);
                      _loadedCategoryTabs.add(0);
                    });
                  },
                ),
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
      {'label': 'New & Popular', 'cat': 3, 'tab': 0},
      {'label': 'Movies', 'cat': 2, 'tab': 0},
      {'label': 'Series', 'cat': 1, 'tab': 0},
      {'label': 'Anime', 'cat': 4, 'tab': 0},
      {'label': 'Drama', 'cat': 5, 'tab': 0},
      {'label': 'Live TV', 'cat': 6, 'tab': 0},
      {'label': 'Sports', 'cat': 6, 'tab': 0},
      {'label': 'Kids', 'cat': 7, 'tab': 0},
      {'label': 'My List', 'cat': 8, 'tab': 0},
    ];

    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C10).withValues(alpha: 0.94),
          border: const Border(bottom: BorderSide(color: Color(0xFF1E1E2C), width: 1)),
        ),
        child: Row(
          children: [
            // Voidflix Red Wordmark
            GestureDetector(
              onTap: () {
                setState(() {
                  _activeCategoryIndex = 0;
                  _bottomTabIndex = 0;
                  _desktopSearchController.clear();
                  _currentSearchQuery = '';
                });
              },
              child: Text(
                'VOIDFLIX',
                style: GoogleFonts.bebasNeue(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryRed,
                  letterSpacing: 2.2,
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Horizontal Desktop Navigation Tabs (Netflix pill style)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: navLinks.map((link) {
                    final isSelected = (_bottomTabIndex == 0 &&
                        _activeCategoryIndex == link['cat']);
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            final cat = link['cat'] as int;
                            final tab = link['tab'] as int;
                            _activeCategoryIndex = cat;
                            _bottomTabIndex = tab;
                            _loadedCategoryTabs.add(cat);
                            _loadedBottomTabs.add(tab);
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: EdgeInsets.symmetric(
                            horizontal: isSelected ? 14 : 11,
                            vertical: 6.5,
                          ),
                          decoration: isSelected
                              ? BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.80),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                )
                              : null,
                          child: Text(
                            link['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Desktop Search Capsule
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: _isSearchFocused || _desktopSearchController.text.isNotEmpty ? 240 : 180,
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isSearchFocused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: Colors.white60),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _desktopSearchController,
                      focusNode: _desktopSearchFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Titles, people, genres',
                        hintStyle: TextStyle(color: Colors.white54, fontSize: 12.5),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (text) {
                        setState(() {
                          _currentSearchQuery = text;
                        });
                        if (text.trim().isNotEmpty && _bottomTabIndex != 2) {
                          setState(() {
                            _bottomTabIndex = 2;
                            _loadedBottomTabs.add(2);
                          });
                        }
                      },
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty) {
                          setState(() {
                            _currentSearchQuery = text.trim();
                            _bottomTabIndex = 2;
                            _loadedBottomTabs.add(2);
                          });
                        }
                      },
                    ),
                  ),
                  if (_desktopSearchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _desktopSearchController.clear();
                        setState(() {
                          _currentSearchQuery = '';
                        });
                      },
                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white60),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Surprise Me (Shuffle)
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 20),
              tooltip: 'Surprise Me',
              onPressed: () {
                final mediaProv = context.read<MediaProvider>();
                final items = mediaProv.trending;
                if (items.isNotEmpty) {
                  final list = List<MediaItem>.from(items)..shuffle();
                  DetailModal.show(context, list.first);
                }
              },
            ),

            // VoidCast
            IconButton(
              icon: const Icon(Icons.cast_rounded, color: Colors.white, size: 20),
              tooltip: 'VoidCast',
              onPressed: () => VoidCastRemoteSheet.show(context),
            ),

            // Downloads Button
            IconButton(
              icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 21),
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
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 21),
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
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white30, width: 1.5),
                  ),
                  child: ProfileAvatarTile.fromProfile(profile: activeProfile, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
