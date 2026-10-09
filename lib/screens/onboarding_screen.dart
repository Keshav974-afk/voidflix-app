import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';
import '../services/avatar_service.dart';
import 'choose_icon_screen.dart';
import 'main_navigation_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController(text: 'Explorer');
  int _currentPage = 0;
  final int _selectedColorIndex = 0;
  bool _isKids = false;

  static const List<Map<String, String>> _netflixPfpOptions = [
    {
      'name': 'Scarlet Chilleez',
      'url': 'https://occ-0-4873-3647.1.nflxso.net/dnm/api/v6/SO2HoVCx33X8phZh2pZZmQ4QgNY/AAAABTk6nphithdqaDreuMsv-yBIzn5xmqqPyz35rHfxkU78C5oD_iRonk_v4jEoZq0U5XFq2c8Qn3phI_uchLj9PKfzFWHgA_QaHw.png?r=201',
    },
    {
      'name': 'Sunny Chilleez',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABaB4hP-03hFOdIwXeYrc_Fb0P-QukEb4sV2BnOlJKVG1dpjJpL7aUOu4VFZenH1zr20DMYE6e8Fa6E7L9BnCvKlDzZEd25S_Ew.png?r=7c7',
    },
    {
      'name': 'Robin Chilleez',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTzykXqE0IgG15a8RLZ7okU8HrL3PU7kuNVL91w9HjwJXRswlPVKSVvVdYUSoea9F1CONTUIZyRzxpgZFd0XC94v-svyKCQpXA.png?r=b39',
    },
    {
      'name': 'Dusty Chilleez',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABfV378_nLCLJYYUS14ujtntA1bLSp4VseVCuahmhQGGoWVOwxuuqGAmICG3H5L-24Fvh8Ezkj6Fik4F9jMGbFitqsfnFrDVh6Q.png?r=6a6',
    },
    {
      'name': 'Dalí Mask',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABQPQcU0ckecAwbr6vEDlu2l5UawW6M82K7Sgx2dgpj9XIUW9sSJosAXvp2l_1hTdCxCEs9uFwyfYXgW-BrN-qDBNtTND3rmrlw.png?r=d0a',
    },
    {
      'name': 'The Professor',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYqQWXH98Pzf8msDpV2poLCKqSG4BOt4NoHMH-R6s0HYdbbXbUelr9AjwvYRiLT6p9bNQQNeIICa3d-Hsgyr663l-9aQaR1VTg.png?r=b38',
    },
    {
      'name': 'Tokyo',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABZIN5ALWTmxTEQzWlyqBhHzRBeBtVN-FpWudf6fgrghnio_-XZIbS3jdQ0abnzMFN1VwaKHm8j4Wj3G7iw-_s2VOuzI0rmTfig.png?r=852',
    },
    {
      'name': 'Berlin',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABXJL5OiMgZqLIwU3q4Xs8tsbDieQ4SyZ59Rpo1PCa3128dbRl5hIISzxENmDsYaBOy9y_Xvu9H5hPcL1uDNzuuYGGc1XMauFXg.png?r=cf8',
    },
    {
      'name': 'Eleven',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTXzu7xECGCa9z4eCqIeE0swz7mk86sF7IGahya6fYok4wqRGpm2oO_uMKwL6zNYhI37ljISGDe5iF__eGTncUToQxQ-atNbDA.png?r=1bb',
    },
    {
      'name': 'Dustin',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYlk619kRF7q9TiQTwALJJRQhiwjuO7dIUZIQignWt6UaFXYyvNrUVB-0Cb_0oRxfyQUbteWQ9SPtmTJJFA2zhV5oGzoJDSVog.png?r=f60',
    },
    {
      'name': 'Eddie',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABT80pSdtOL8qzdrRtJISys90D3h5NbTpPmaR472mHDPiku5h2D4HDG6j1vl-A4h0_Ycb-4LXlbhKn9wqhQc0rrmypevjsiqHRQ.png?r=c31',
    },
    {
      'name': 'Front Man',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYi8u2Nz9dp3EF_xcUQoW4TbnDi672S6usNUHhola5qHBSVEhNnIG8FadHiWs_L985TvUX7ST9m7CijuBJqeoO5oHirnkPkNYw.png?r=66c',
    },
    {
      'name': 'Young-hee Doll',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABWVoYzlSivjXDh16yJtaZ2BJ11T4Tnjuu2ODGqzGHaMvGliRQgaQrroMgVMDfXtlp9QKPYSKIWHIGjU83kcCpksI43rFWcus8g.png?r=83b',
    },
    {
      'name': 'Wednesday',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABS_fCAimFcSuIgnyvchWA3eNUjEsCsciKhhXfklGV3idvRbG7qu7YwPOCIyNrZNjkteloppY2M-9rXnuvUYXPqTIXh5GB9Ri_Q.png?r=02d',
    },
    {
      'name': 'Luffy',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABc-963K_PIXK-o0mRr2QiuMS8-Q8HQZWqaRGwtx3mrzM-p23gjyOD-QRxjXtQWgxM2yVp0eKnTKRIW-8J43NWL0xzlEDsoxqOQ.png?r=0a4',
    },
    {
      'name': 'Jinx',
      'url': 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABaSX2NqfYXqDB_Z33yOHnpIiTcBqMDAEzIl4lYXzhlFB16oLyY4P0Vy0IdAZgSH926Z7vwuXhWa3U2ZeutsSPpEYfX2LyyGtOg.png?r=87b',
    },
  ];

  late String _selectedAvatarUrl;
  static const int _totalPages = 4;
  List<NetflixAvatar> _availableAvatars = List.from(AvatarService.defaultFeatured);

  @override
  void initState() {
    super.initState();
    _selectedAvatarUrl = _netflixPfpOptions.first['url']!;
    AvatarService().loadAvatars().then((_) {
      if (mounted && AvatarService().allAvatars.isNotEmpty) {
        setState(() {
          _availableAvatars = AvatarService().allAvatars;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openTelegram(String username) async {
    final tgUri = Uri.parse('tg://resolve?domain=$username');
    final webUri = Uri.parse('https://t.me/$username');
    bool launched = false;
    try {
      launched = await launchUrl(tgUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  Future<void> _finish({bool skipped = false}) async {
    // 1. Permanently record completion in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voidflix_global_onboarding_completed', true);

    if (!mounted) return;
    final profileProv = context.read<ProfileProvider>();
    final mediaProv = context.read<MediaProvider>();

    final finalName = _nameController.text.trim().isEmpty ? 'Explorer' : _nameController.text.trim();

    final profile = await profileProv.completeInitialOnboarding(
      name: finalName,
      avatar: _selectedAvatarUrl,
      colorIndex: _selectedColorIndex,
      isKids: _isKids,
      preferredLanguages: ['en', 'hi'],
      preferredGenres: [28, 878],
      favoriteActors: [],
      favoriteTitles: [],
    );

    // Refresh personalized feed
    mediaProv.fetchPersonalizedForProfile(profile, force: true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Ambient background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1B0709),
                    Color(0xFF09090E),
                    Colors.black,
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Main content safe area
          SafeArea(
            child: Column(
              children: [
                // Top Netflix Brand Header & Skip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Brand Logo
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'VOID',
                              style: GoogleFonts.bebasNeue(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryRed,
                                letterSpacing: 2,
                              ),
                            ),
                            TextSpan(
                              text: 'FLIX',
                              style: GoogleFonts.bebasNeue(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Skip Action
                      TextButton(
                        onPressed: () => _finish(skipped: true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        child: const Text('SKIP'),
                      ),
                    ],
                  ),
                ),

                // PageView content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    children: [
                      _buildWelcomeSlide(),
                      _buildTelegramSlide(),
                      _buildDownloadsSlide(),
                      _buildProfileSetupSlide(),
                    ],
                  ),
                ),

                // Bottom Navigation (Indicators + CTA button)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page Indicator Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_totalPages, (i) {
                          final isActive = i == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isActive ? 24 : 6,
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.primaryRed : Colors.white24,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),

                      // Netflix Red CTA Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryRed,
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor: AppTheme.primaryRed.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _nextPage,
                          child: Text(
                            _currentPage == _totalPages - 1 ? 'START WATCHING' : 'CONTINUE',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Subtle secondary hint
                      if (_currentPage < _totalPages - 1)
                        GestureDetector(
                          onTap: () => _finish(skipped: true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Skip directly to home',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Slide 1: Unlimited streaming
  Widget _buildWelcomeSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Icon(
                Icons.movie_filter_rounded,
                size: 58,
                color: AppTheme.primaryRed,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Unlimited movies,\nTV shows, and more',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Watch anywhere. Stream blockbuster movies, trending series, anime, and live TV channels in full HD with zero subscriptions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Slide 2: Telegram Community (Requested by user)
  Widget _buildTelegramSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Telegram Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0088CC).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF0088CC).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.send_rounded, color: Color(0xFF29B6F6), size: 14),
                SizedBox(width: 6),
                Text(
                  'OFFICIAL COMMUNITY',
                  style: TextStyle(
                    color: Color(0xFF29B6F6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Text(
            'Join our Telegram\nto stay up to date',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Get instant mirror links, release alerts, direct title requests, and stay updated if domains change.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          // Telegram Action Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF262638)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0088CC),
                      ),
                      child: const Center(
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Voidflix Official Channel',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            't.me/VoidFlixOrg',
                            style: TextStyle(
                              color: Color(0xFF29B6F6),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0088CC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _openTelegram('VoidFlixOrg'),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'Join Telegram Channel (@VoidFlixOrg)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _openTelegram('Voidflixchat'),
                    icon: const Icon(Icons.forum_outlined, size: 16, color: Color(0xFF29B6F6)),
                    label: const Text(
                      'Join Discussion Chat (@Voidflixchat)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Slide 3: Downloads & Offline Playback
  Widget _buildDownloadsSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Icon(
                Icons.file_download_outlined,
                size: 58,
                color: AppTheme.primaryRed,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Download and watch\noffline anytime',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Save your favorite movies and shows to watch on the go. High-speed HLS and direct downloads with resume support.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Slide 4: Real Netflix Profile Creation (No childish emojis!)
  Widget _buildProfileSetupSlide() {
    final gradient = ProfileProvider.avatarGradients[
      _selectedColorIndex % ProfileProvider.avatarGradients.length
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Who\'s watching?',
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create your profile with the classic Netflix avatar.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Netflix Official Avatar Live Preview
          GestureDetector(
            onTap: () async {
              final fakeProfile = UserProfile(
                id: 'temp',
                name: _nameController.text.trim().isEmpty ? 'Explorer' : _nameController.text.trim(),
                avatar: _selectedAvatarUrl,
              );
              final res = await Navigator.push<AvatarItem>(
                context,
                MaterialPageRoute(builder: (_) => ChooseIconScreen(profile: fakeProfile)),
              );
              if (res != null && res.imageUrl != null) {
                setState(() => _selectedAvatarUrl = res.imageUrl!);
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primaryRed, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryRed.withValues(alpha: 0.5),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: CachedNetworkImage(
                      imageUrl: _selectedAvatarUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(color: const Color(0xFF1A1A24)),
                      errorWidget: (c, u, e) => ProfileAvatarTile(
                        name: _nameController.text,
                        gradientColors: gradient,
                        size: 96,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, size: 13, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Header for Avatar Picker + More Icons Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'OFFICIAL NETFLIX ICONS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final fakeProfile = UserProfile(
                    id: 'temp',
                    name: _nameController.text,
                    avatar: _selectedAvatarUrl,
                  );
                  final res = await Navigator.push<AvatarItem>(
                    context,
                    MaterialPageRoute(builder: (_) => ChooseIconScreen(profile: fakeProfile)),
                  );
                  if (res != null && res.imageUrl != null) {
                    setState(() => _selectedAvatarUrl = res.imageUrl!);
                  }
                },
                child: const Text(
                  'See all >',
                  style: TextStyle(
                    color: AppTheme.primaryRed,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Horizontal list of official Netflix avatars (expanded with all extracted avatars)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _availableAvatars.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, idx) {
                final opt = _availableAvatars[idx];
                final isSelected = _selectedAvatarUrl == opt.url;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatarUrl = opt.url),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.white24,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.35),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: opt.url,
                        fit: BoxFit.cover,
                        memCacheWidth: 150,
                        memCacheHeight: 150,
                        placeholder: (c, u) => Container(color: const Color(0xFF1E1E24)),
                        errorWidget: (c, u, e) => Container(
                          color: const Color(0xFF1E1E24),
                          child: const Icon(Icons.person, color: Colors.white38),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Profile Name input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF161622),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2C2C3D)),
            ),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Profile name (e.g. Explorer)',
                hintStyle: TextStyle(color: Colors.white30),
                icon: Icon(Icons.person_outline, color: Colors.white54),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),

          // Kids profile switch
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161622),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2C2C3D)),
            ),
            child: SwitchListTile(
              activeThumbColor: AppTheme.primaryRed,
              activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.3),
              title: const Text(
                'Kids Profile',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Only display family-friendly movies & shows',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: _isKids,
              onChanged: (val) => setState(() => _isKids = val),
            ),
          ),
        ],
      ),
    );
  }
}
