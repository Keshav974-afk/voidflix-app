import 'package:flutter/material.dart';
import '../core/constants/theme_constants.dart';
import '../widgets/brand_header.dart';
import '../widgets/floating_bottom_bar.dart';
import 'home_screen.dart';
import 'movies_screen.dart';
import 'series_screen.dart';
import 'new_popular_screen.dart';
import 'anime_screen.dart';
import 'drama_screen.dart';
import 'live_tv_screen.dart';
import 'kids_screen.dart';
import 'clips_screen.dart';
import 'search_screen.dart';
import 'my_netflix_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _activeCategoryIndex = 0; // 0: Home, 1: Series, 2: Films, 3: New & Hot, etc.
  int _bottomTabIndex = 0; // 0: Home, 1: Clips, 2: Search, 3: My Voidflix

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
      appBar: _bottomTabIndex == 0
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
          : null,
      body: Stack(
        children: [
          // Screen body content
          Positioned.fill(
            child: bodyContent,
          ),

          // Netflix Floating Pill Bottom Navigation Bar (Screenshots 1, 2, 5)
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
}
