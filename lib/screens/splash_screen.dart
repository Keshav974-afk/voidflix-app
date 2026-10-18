import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/app_analytics_service.dart';
import '../core/services/tv_mode_service.dart';
import 'onboarding_screen.dart';
import 'profile_gate_screen.dart';
import 'update_required_screen.dart';

/// Iconic Netflix-Style Splash Screen for VOIDFLIX.
///
/// Features a pure pitch-black cinematic backdrop with atmospheric crimson
/// ambient backlighting and the iconic bold red VOIDFLIX wordmark.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  Timer? _timer;
  Timer? _hapticTimer1;
  Timer? _hapticTimer2;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // Smooth cinematic opacity fade-in
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 15,
      ),
    ]).animate(_animController);

    // Subtle majestic zoom (from 0.94 to 1.04)
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart),
    );

    // Ambient crimson backlight glow
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.85).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_animController);

    _animController.forward();

    // Iconic Netflix Ta-Dum tactile haptics
    _hapticTimer1 = Timer(const Duration(milliseconds: 250), () {
      HapticFeedback.mediumImpact();
    });
    _hapticTimer2 = Timer(const Duration(milliseconds: 650), () {
      HapticFeedback.heavyImpact();
    });

    // Proceed to next screen after animation completes (2350ms)
    _timer = Timer(const Duration(milliseconds: 2350), () {
      _proceedNext();
    });
  }

  Future<void> _proceedNext() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _cancelTimers();

    // 1. Report device heartbeat & register user in Voidflix Mission Control
    unawaited(AppAnalyticsService.sendPing());

    // 2. Fetch live remote configuration from Voidflix edge database
    await RemoteConfigService.fetchConfig();

    // 3. Strict Version Gating: If current app version is older, require update
    if (RemoteConfigService.isUpdateAvailable) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const UpdateRequiredScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final bool alreadyDone = prefs.getBool('voidflix_global_onboarding_completed') ?? false;
    final String? profilesList = prefs.getString('voidflix_profiles_list');
    final bool hasProfiles = profilesList != null && profilesList.isNotEmpty && profilesList != '[]';

    Widget target;
    if (!alreadyDone && !hasProfiles) {
      target = const OnboardingScreen();
    } else {
      target = const ProfileGateScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => target,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _cancelTimers() {
    _timer?.cancel();
    _hapticTimer1?.cancel();
    _hapticTimer2?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvModeService().isTvMode;
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive font size for authentic Netflix typography
    final double fontSize = isTv
        ? 74.0
        : (screenWidth > 800 ? 68.0 : (screenWidth > 500 ? 56.0 : 44.0));

    final double letterSpacing = isTv
        ? 6.5
        : (screenWidth > 800 ? 6.0 : (screenWidth > 500 ? 5.0 : 3.8));

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _proceedNext,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final glowVal = _glowAnimation.value;
            final fadeVal = _fadeAnimation.value;
            final scaleVal = _scaleAnimation.value;

            return Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // 1. Pure Pitch-Black Backdrop
                const ColoredBox(color: Colors.black),

                // 2. Cinematic Atmospheric Crimson Ambient Backlight Aura (matching real TV ambient room lighting)
                if (glowVal > 0.01)
                  Center(
                    child: Container(
                      width: screenWidth * 0.95,
                      height: screenWidth * 0.95,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFE50914).withValues(alpha: 0.28 * glowVal),
                            const Color(0xFF8B0000).withValues(alpha: 0.12 * glowVal),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),

                // 3. Iconic Center Red VOIDFLIX Wordmark
                Center(
                  child: Opacity(
                    opacity: fadeVal.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scaleVal,
                      child: Text(
                        'VOIDFLIX',
                        style: GoogleFonts.bebasNeue(
                          fontSize: fontSize,
                          letterSpacing: letterSpacing,
                          color: const Color(0xFFE50914),
                          shadows: [
                            // Vibrant red luminescence
                            Shadow(
                              color: const Color(0xFFE50914).withValues(alpha: 0.75 * glowVal),
                              blurRadius: 32,
                            ),
                            // Deep black backdrop drop-shadow for rich 3D contrast
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.95),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
