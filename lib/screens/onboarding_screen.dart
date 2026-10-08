import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import 'main_navigation_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  final TextEditingController _nameController = TextEditingController(text: 'Explorer');
  final TextEditingController _customInterestController = TextEditingController();

  int _selectedColorIndex = 0;
  String _selectedAvatar = '🍿';

  final Set<String> _selectedLanguages = {'hi', 'en'};
  final Set<int> _selectedGenres = {878, 28};
  final Set<String> _selectedActors = {'Christopher Nolan', 'Shah Rukh Khan'};
  final List<String> _customFavorites = [];

  bool _isSynthesizing = false;
  int _synthesisProgress = 0;
  Timer? _synthesisTimer;

  // Language options
  final List<Map<String, dynamic>> _languages = [
    {
      'code': 'hi',
      'label': 'Hindi & Bollywood',
      'badge': '🇮🇳',
      'subtitle': 'Hindi blockbusters, romance & OTT thrillers',
    },
    {
      'code': 'en',
      'label': 'English & Hollywood',
      'badge': '🇺🇸',
      'subtitle': 'Global blockbusters, franchises & series',
    },
    {
      'code': 'ja',
      'label': 'Anime & Japanese',
      'badge': '🇯🇵',
      'subtitle': 'Top anime series, shonen & Ghibli masterworks',
    },
    {
      'code': 'ko',
      'label': 'K-Drama & Korean',
      'badge': '🇰🇷',
      'subtitle': 'Korean romance, revenge & high-stakes dramas',
    },
    {
      'code': 'te',
      'label': 'South Indian Cinema',
      'badge': '🇮🇳',
      'subtitle': 'Tollywood & Kollywood action spectacles',
    },
    {
      'code': 'es',
      'label': 'Spanish & International',
      'badge': '🇪🇸',
      'subtitle': 'High-tension crime thrillers & European gems',
    },
  ];

  // Genre options
  final List<Map<String, dynamic>> _genres = [
    {'id': 878, 'name': 'Sci-Fi & Cyberpunk', 'icon': Icons.rocket_launch, 'desc': 'Interstellar, Dune, Matrix'},
    {'id': 28, 'name': 'High-Octane Action', 'icon': Icons.local_fire_department, 'desc': 'John Wick, Fast & Furious'},
    {'id': 16, 'name': 'Anime & Animation', 'icon': Icons.auto_awesome, 'desc': 'Attack on Titan, Jujutsu Kaisen'},
    {'id': 53, 'name': 'Edge-of-Seat Thrillers', 'icon': Icons.visibility, 'desc': 'Dark, Se7en, Gone Girl'},
    {'id': 35, 'name': 'Laugh-Out Comedies', 'icon': Icons.sentiment_very_satisfied, 'desc': 'Sitcoms, standup & comfort watches'},
    {'id': 27, 'name': 'Dark Horror & Spooky', 'icon': Icons.nights_stay, 'desc': 'Conjuring, Hereditary, Insidious'},
    {'id': 10749, 'name': 'Romance & Drama', 'icon': Icons.favorite, 'desc': 'Love stories, emotional chemistry'},
    {'id': 14, 'name': 'Mythic Fantasy & Lore', 'icon': Icons.shield, 'desc': 'Lord of the Rings, Game of Thrones'},
    {'id': 80, 'name': 'Gritty Crime & Mafia', 'icon': Icons.fingerprint, 'desc': 'Godfather, Peaky Blinders'},
    {'id': 99, 'name': 'Documentaries', 'icon': Icons.public, 'desc': 'True crime, cosmos & untold stories'},
  ];

  // Actor / Idol options
  final List<String> _popularIdols = [
    'Shah Rukh Khan',
    'Christopher Nolan',
    'Robert Downey Jr.',
    'Leonardo DiCaprio',
    'Cillian Murphy',
    'Tom Cruise',
    'Ryan Gosling',
    'Prabhas',
    'Salman Khan',
    'Zendaya',
    'Allu Arjun',
    'Hrithik Roshan',
    'Keanu Reeves',
    'Quentin Tarantino',
    'Christian Bale',
    'Deepika Padukone',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _customInterestController.dispose();
    _synthesisTimer?.cancel();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _startSynthesis();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _startSynthesis() {
    setState(() {
      _isSynthesizing = true;
      _synthesisProgress = 0;
    });

    _synthesisTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_synthesisProgress < 100) {
        setState(() => _synthesisProgress += 10);
      } else {
        timer.cancel();
        _finishOnboarding();
      }
    });
  }

  Future<void> _finishOnboarding() async {
    final profileProvider = context.read<ProfileProvider>();
    final mediaProvider = context.read<MediaProvider>();

    final finalName = _nameController.text.trim().isEmpty ? 'Cinema Explorer' : _nameController.text.trim();

    final profile = await profileProvider.completeInitialOnboarding(
      name: finalName,
      avatar: _selectedAvatar,
      colorIndex: _selectedColorIndex,
      preferredLanguages: _selectedLanguages.toList(),
      preferredGenres: _selectedGenres.toList(),
      favoriteActors: _selectedActors.toList(),
      favoriteTitles: _customFavorites,
    );

    // Trigger personalized feed fetch
    if (mounted) {
      mediaProvider.fetchPersonalizedForProfile(profile, force: true);

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  void _addCustomItem() {
    final text = _customInterestController.text.trim();
    if (text.isNotEmpty && !_customFavorites.contains(text)) {
      setState(() {
        _customFavorites.add(text);
        _customInterestController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSynthesizing) {
      return _buildSynthesisView();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Voidflix branding & progress bar
            _buildTopBar(),

            // Interactive Steps Body
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildCurrentStepView(),
              ),
            ),

            // Bottom Navigation & Continue Button
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'VOIDFLIX',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 20,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Step ${_currentStep + 1} of 4',
                    style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (_currentStep > 0)
                TextButton(
                  onPressed: _startSynthesis,
                  child: const Text('Skip Setup', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Step Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 4.0,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep1NameAndAvatar();
      case 1:
        return _buildStep2Languages();
      case 2:
        return _buildStep3Genres();
      case 3:
      default:
        return _buildStep4ActorsAndTitles();
    }
  }

  // STEP 1: Name & Avatar Selection
  Widget _buildStep1NameAndAvatar() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryRed.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.movie_creation_rounded, color: AppTheme.primaryRed, size: 40),
          ),
          const SizedBox(height: 18),
          Text(
            'Who is Entering the Void?',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Welcome to Voidflix! Tell us your name so we can personalize your cinematic feed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 28),

          // Active Avatar Preview
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: ProfileProvider.avatarGradients[_selectedColorIndex],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: ProfileProvider.avatarGradients[_selectedColorIndex].first.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _selectedAvatar,
                style: const TextStyle(fontSize: 44),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Name Input
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF191924),
              hintText: 'Enter your name...',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Choose Avatar Icon
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pick Your Avatar',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ProfileProvider.avatarIcons.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, idx) {
                final icon = ProfileProvider.avatarIcons[idx];
                final isSelected = icon == _selectedAvatar;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = icon),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryRed.withValues(alpha: 0.25) : const Color(0xFF191924),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryRed : Colors.white12,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Choose Color Theme
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pick Theme Accent',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(ProfileProvider.avatarGradients.length, (idx) {
              final isSelected = idx == _selectedColorIndex;
              final grad = ProfileProvider.avatarGradients[idx];
              return GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = idx),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: grad),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // STEP 2: Language & Industry Preferences
  Widget _buildStep2Languages() {
    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What Film Worlds Do You Watch?',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select your preferred cinema industries. We will feature these prominently in your feed.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ..._languages.map((lang) {
            final code = lang['code'] as String;
            final isSelected = _selectedLanguages.contains(code);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    if (_selectedLanguages.length > 1) {
                      _selectedLanguages.remove(code);
                    }
                  } else {
                    _selectedLanguages.add(code);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E1724) : const Color(0xFF15151E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryRed : Colors.white12,
                    width: isSelected ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(lang['badge'] as String, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lang['label'] as String,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lang['subtitle'] as String,
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? AppTheme.primaryRed : Colors.white24,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // STEP 3: Genres Selection
  Widget _buildStep3Genres() {
    return SingleChildScrollView(
      key: const ValueKey(2),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What Vibes Give You Chills?',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose your favorite genres to build your personalized homepage rows:',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _genres.map((g) {
              final id = g['id'] as int;
              final isSelected = _selectedGenres.contains(id);
              final icon = g['icon'] as IconData;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      if (_selectedGenres.length > 1) {
                        _selectedGenres.remove(id);
                      }
                    } else {
                      _selectedGenres.add(id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryRed : const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryRed : Colors.white12,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryRed.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        g['name'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check, color: Colors.white, size: 14),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // STEP 4: Actors, Directors, & Favorite Movies
  Widget _buildStep4ActorsAndTitles() {
    return SingleChildScrollView(
      key: const ValueKey(3),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who Are Your Cinema Idols?',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select actors or directors whose work you never miss, or add your favorite movies:',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 18),

          // Idols Selection Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularIdols.map((idol) {
              final isSelected = _selectedActors.contains(idol);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedActors.remove(idol);
                    } else {
                      _selectedActors.add(idol);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF261016) : const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryRed : Colors.white12,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                        color: isSelected ? AppTheme.primaryRed : Colors.white38,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        idol,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Add custom favorite titles or actors
          Text(
            'Add Any Favorite Movie, Show, or Star',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customInterestController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Inception, Breaking Bad, Jawan...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF191924),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF2E2E3E)),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomItem(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _addCustomItem,
                child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          if (_customFavorites.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customFavorites.map((title) {
                return Chip(
                  backgroundColor: AppTheme.surfaceVariant,
                  label: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white54),
                  onDeleted: () {
                    setState(() => _customFavorites.remove(title));
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // BOTTOM NAVIGATION BAR
  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F16),
        border: Border(top: BorderSide(color: Color(0xFF20202E))),
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _prevStep,
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 4,
                shadowColor: AppTheme.primaryRed.withValues(alpha: 0.5),
              ),
              onPressed: _nextStep,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentStep == 3 ? 'Launch Voidflix' : 'Next Step',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _currentStep == 3 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SYNTHESIS / PERSONALIZATION ANIMATION VIEW
  Widget _buildSynthesisView() {
    String statusText = 'Calibrating frequency for ${_nameController.text}...';
    if (_synthesisProgress > 30) {
      statusText = 'Assembling ${_selectedLanguages.join(', ').toUpperCase()} cinema pipelines...';
    }
    if (_synthesisProgress > 65) {
      statusText = 'Synthesizing recommendations for ${_selectedActors.take(2).join(', ')}...';
    }
    if (_synthesisProgress > 90) {
      statusText = 'Voidflix is ready!';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryRed.withValues(alpha: 0.15),
                  border: Border.all(color: AppTheme.primaryRed, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryRed.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryRed,
                    strokeWidth: 3,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'BUILDING YOUR VOIDFLIX',
                style: GoogleFonts.bebasNeue(
                  fontSize: 28,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: _synthesisProgress / 100.0,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
