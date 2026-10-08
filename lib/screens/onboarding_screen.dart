import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';
import 'main_navigation_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final TextEditingController _nameController = TextEditingController(text: 'Explorer');
  final TextEditingController _actorSearchController = TextEditingController();

  int _selectedColorIndex = 0;

  // Selected sets
  final Set<int> _selectedGenres = {};
  final List<Map<String, dynamic>> _selectedActors = [];
  final Set<String> _selectedLanguages = {};

  // Actors state from TMDB
  List<Map<String, dynamic>> _popularActors = [];
  List<Map<String, dynamic>> _searchedActors = [];
  bool _isLoadingActors = false;
  Timer? _searchDebounce;

  static const List<String> _stepTitles = [
    'Profile',
    'Genres',
    'Actors',
    'Languages',
  ];

  // Exact 16 GENRE_CHOICES from the Voidflix web version
  static const List<Map<String, dynamic>> _genreChoices = [
    {'id': 28, 'name': 'Action', 'emoji': '💥'},
    {'id': 35, 'name': 'Comedy', 'emoji': '😂'},
    {'id': 18, 'name': 'Drama', 'emoji': '🎭'},
    {'id': 27, 'name': 'Horror', 'emoji': '👻'},
    {'id': 878, 'name': 'Sci-Fi', 'emoji': '🚀'},
    {'id': 10749, 'name': 'Romance', 'emoji': '💕'},
    {'id': 53, 'name': 'Thriller', 'emoji': '🔪'},
    {'id': 16, 'name': 'Animation', 'emoji': '🎨'},
    {'id': 14, 'name': 'Fantasy', 'emoji': '🐉'},
    {'id': 80, 'name': 'Crime', 'emoji': '🕵️'},
    {'id': 12, 'name': 'Adventure', 'emoji': '🗺️'},
    {'id': 99, 'name': 'Documentary', 'emoji': '🎥'},
    {'id': 10751, 'name': 'Family', 'emoji': '👨‍👩‍👧'},
    {'id': 9648, 'name': 'Mystery', 'emoji': '🔍'},
    {'id': 36, 'name': 'History', 'emoji': '🏛️'},
    {'id': 10752, 'name': 'War', 'emoji': '⚔️'},
  ];

  // Exact 10 LANGUAGE_CHOICES from the Voidflix web version
  static const List<Map<String, dynamic>> _languageChoices = [
    {'code': 'en', 'label': 'Hollywood', 'flag': '🇺🇸'},
    {'code': 'hi', 'label': 'Bollywood', 'flag': '🇮🇳'},
    {'code': 'ko', 'label': 'Korean', 'flag': '🇰🇷'},
    {'code': 'ja', 'label': 'Japanese / Anime', 'flag': '🇯🇵'},
    {'code': 'es', 'label': 'Spanish', 'flag': '🇪🇸'},
    {'code': 'fr', 'label': 'French', 'flag': '🇫🇷'},
    {'code': 'tr', 'label': 'Turkish', 'flag': '🇹🇷'},
    {'code': 'ta', 'label': 'Tamil', 'flag': '🎬'},
    {'code': 'te', 'label': 'Telugu', 'flag': '🎞️'},
    {'code': 'zh', 'label': 'Chinese', 'flag': '🇨🇳'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPopularActors();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _actorSearchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPopularActors() async {
    setState(() => _isLoadingActors = true);
    try {
      final list = await ApiService().getPopularPeople();
      if (mounted) {
        setState(() {
          _popularActors = list;
          _isLoadingActors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingActors = false);
    }
  }

  void _onActorSearchChanged(String val) {
    _searchDebounce?.cancel();
    final query = val.trim();
    if (query.length < 2) {
      setState(() => _searchedActors = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ApiService().searchPeople(query);
      if (mounted) {
        setState(() => _searchedActors = results);
      }
    });
  }

  void _toggleGenre(int id) {
    setState(() {
      if (_selectedGenres.contains(id)) {
        _selectedGenres.remove(id);
      } else {
        _selectedGenres.add(id);
      }
    });
  }

  void _toggleLanguage(String code) {
    setState(() {
      if (_selectedLanguages.contains(code)) {
        _selectedLanguages.remove(code);
      } else {
        _selectedLanguages.add(code);
      }
    });
  }

  void _toggleActor(Map<String, dynamic> actor) {
    final id = actor['id'] as int;
    final name = actor['name'] as String? ?? 'Actor';
    final profilePath = actor['profile_path'] as String?;

    setState(() {
      final exists = _selectedActors.any((a) => a['id'] == id);
      if (exists) {
        _selectedActors.removeWhere((a) => a['id'] == id);
      } else {
        if (_selectedActors.length < 8) {
          _selectedActors.add({
            'id': id,
            'name': name,
            'profile_path': profilePath,
          });
        }
      }
    });
  }

  Future<void> _finish({bool skipped = false}) async {
    // 1. Immediately and permanently mark global onboarding as completed in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voidflix_global_onboarding_completed', true);

    if (!mounted) return;
    final profileProv = context.read<ProfileProvider>();
    final mediaProv = context.read<MediaProvider>();

    final finalName = _nameController.text.trim().isEmpty ? 'Explorer' : _nameController.text.trim();

    final profile = await profileProv.completeInitialOnboarding(
      name: finalName,
      avatar: '😊',
      colorIndex: _selectedColorIndex,
      preferredLanguages: skipped ? ['en', 'hi'] : _selectedLanguages.toList(),
      preferredGenres: skipped ? [28, 878] : _selectedGenres.toList(),
      favoriteActors: skipped ? [] : _selectedActors.map((a) => a['name'] as String).toList(),
      favoriteTitles: [],
    );

    // Refresh personalized rails
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

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepTitles.length - 1;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.90),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: const BoxConstraints(maxWidth: 640),
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF282836)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Exact 1:1 match of OnboardingModal.tsx)
                _buildModalHeader(),

                // Scrollable Content Body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: _buildStepContent(),
                  ),
                ),

                // Footer (Exact 1:1 match of OnboardingModal.tsx)
                _buildModalFooter(isLast),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF282836))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: AppTheme.primaryRed, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          "Let's personalize Voidflix",
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Answer a few quick questions and we'll build recommendation rows just for you.",
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                tooltip: 'Skip for now',
                onPressed: () => _finish(skipped: true),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Step Progress Pills (Matches web animated step pills)
          Row(
            children: [
              for (int i = 0; i < _stepTitles.length; i++) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  width: i == _step ? 32 : 16,
                  decoration: BoxDecoration(
                    color: i == _step
                        ? AppTheme.primaryRed
                        : i < _step
                            ? AppTheme.primaryRed.withValues(alpha: 0.5)
                            : const Color(0xFF282836),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                if (i < _stepTitles.length - 1) const SizedBox(width: 6),
              ],
              const SizedBox(width: 12),
              Text(
                'Step ${_step + 1} of ${_stepTitles.length} · ${_stepTitles[_step]}',
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStepProfile();
      case 1:
        return _buildStepGenres();
      case 2:
        return _buildStepActors();
      case 3:
      default:
        return _buildStepLanguages();
    }
  }

  // STEP 1: Profile Name & Netflix Classic Smiley Face Avatar
  Widget _buildStepProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Who is watching?",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          "Pick your profile avatar color and enter your name.",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Large Netflix Smiley Preview
        Center(
          child: ProfileAvatarTile(
            name: _nameController.text,
            gradientColors: ProfileProvider.avatarGradients[_selectedColorIndex],
            size: 96,
          ),
        ),
        const SizedBox(height: 20),

        // Color Swatches (Featuring the classic Netflix Smiley Face)
        Center(
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: List.generate(ProfileProvider.avatarGradients.length, (idx) {
              final isSel = idx == _selectedColorIndex;
              final grad = ProfileProvider.avatarGradients[idx];
              return GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = idx),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: grad),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: ProfileAvatarTile(
                      name: '',
                      gradientColors: grad,
                      size: 40,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),

        // Name TextField
        const Text(
          "Profile Name",
          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF191924),
            hintText: 'e.g. Alex, Movie Lover...',
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF282836)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF282836)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryRed, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // STEP 2: Genres (Exact clone of OnboardingModal.tsx Step 0)
  Widget _buildStepGenres() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Which genres do you love?",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          "Pick as many as you like.",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // 2-column grid of all 16 GENRE_CHOICES from the site
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _genreChoices.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final g = _genreChoices[index];
            final id = g['id'] as int;
            final isSelected = _selectedGenres.contains(id);

            return GestureDetector(
              onTap: () => _toggleGenre(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryRed.withValues(alpha: 0.15) : const Color(0xFF161620),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryRed : const Color(0xFF282836),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(g['emoji'] as String, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g['name'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check, color: AppTheme.primaryRed, size: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // STEP 3: Actors (Exact clone of OnboardingModal.tsx Step 1 with TMDB Search & Popular list)
  Widget _buildStepActors() {
    final displayList = _searchedActors.isNotEmpty ? _searchedActors : _popularActors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Who are your favorite actors?",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          "Pick up to 8 — we'll surface their movies for you.",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 14),

        // Actor Search Input (Matches web search box)
        TextField(
          controller: _actorSearchController,
          onChanged: _onActorSearchChanged,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search any actor…',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
            suffixIcon: _actorSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                    onPressed: () {
                      _actorSearchController.clear();
                      setState(() => _searchedActors = []);
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF191924),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF282836)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF282836)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryRed, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Selected Actors Tags Row
        if (_selectedActors.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedActors.map((a) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primaryRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a['name'] as String,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _toggleActor(a),
                      child: const Icon(Icons.close, color: Colors.white70, size: 14),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],

        // Circular Photos Grid (Exact match of OnboardingModal.tsx)
        if (_isLoadingActors && displayList.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(color: AppTheme.primaryRed),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length > 18 ? 18 : displayList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final actor = displayList[index];
              final id = actor['id'] as int;
              final name = actor['name'] as String? ?? 'Actor';
              final profilePath = actor['profile_path'] as String?;
              final isSelected = _selectedActors.any((a) => a['id'] == id);

              return GestureDetector(
                onTap: () => _toggleActor(actor),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? AppTheme.primaryRed : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: ClipOval(
                              child: profilePath != null
                                  ? CachedNetworkImage(
                                      imageUrl: ApiService.getImageUrl(profilePath, size: 'w200'),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorWidget: (_, _, _) => Container(
                                        color: const Color(0xFF1F1F2B),
                                        child: Center(
                                          child: Text(
                                            name.isNotEmpty ? name[0] : '?',
                                            style: const TextStyle(color: Colors.white54, fontSize: 20),
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF1F1F2B),
                                      child: Center(
                                        child: Text(
                                          name.isNotEmpty ? name[0] : '?',
                                          style: const TextStyle(color: Colors.white54, fontSize: 20),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          if (isSelected)
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryRed.withValues(alpha: 0.45),
                              ),
                              child: const Center(
                                child: Icon(Icons.check, color: Colors.white, size: 28),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // STEP 4: Languages / Industries (Exact clone of OnboardingModal.tsx Step 2)
  Widget _buildStepLanguages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "What do you like watching?",
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          "Pick the industries and languages you enjoy.",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // 2-column grid of all 10 LANGUAGE_CHOICES from the site
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _languageChoices.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final l = _languageChoices[index];
            final code = l['code'] as String;
            final isSelected = _selectedLanguages.contains(code);

            return GestureDetector(
              onTap: () => _toggleLanguage(code),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryRed.withValues(alpha: 0.15) : const Color(0xFF161620),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryRed : const Color(0xFF282836),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(l['flag'] as String, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l['label'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check, color: AppTheme.primaryRed, size: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Footer (Matches web OnboardingModal.tsx footer exactly)
  Widget _buildModalFooter(bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF282836))),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => _finish(skipped: true),
            child: const Text('Skip for now', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const Spacer(),
          if (_step > 0) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF282836)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Back'),
              onPressed: () => setState(() => _step--),
            ),
            const SizedBox(width: 10),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: Icon(isLast ? Icons.check : Icons.chevron_right, size: 18),
            label: Text(
              isLast ? 'Build my recommendations' : 'Next',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              if (isLast) {
                _finish();
              } else {
                setState(() => _step++);
              }
            },
          ),
        ],
      ),
    );
  }
}
