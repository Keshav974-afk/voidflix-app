import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
import 'onboarding_screen.dart';
import 'profile_gate_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _letterSpacingAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // Initial dramatic scale up
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.65, end: 1.08).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 20,
      ),
    ]).animate(_controller);

    // Fade in and out
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
    ]).animate(_controller);

    // Ambient crimson glow pulse
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.2).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);

    // Cinematic letter spacing expansion
    _letterSpacingAnimation = Tween<double>(begin: 4.0, end: 10.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 2450), () {
      _goToProfileGate();
    });
  }

  Future<void> _goToProfileGate() async {
    if (!mounted) return;
    _timer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final bool alreadyDone = prefs.getBool('voidflix_global_onboarding_completed') ?? false;
    final String? profilesList = prefs.getString('voidflix_profiles_list');
    final bool hasProfiles = profilesList != null && profilesList.isNotEmpty && profilesList != '[]';

    final bool isFirstTime = !alreadyDone && !hasProfiles;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            isFirstTime ? const OnboardingScreen() : const ProfileGateScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _goToProfileGate,
      child: Scaffold(
        backgroundColor: const Color(0xFF08080C),
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final glowVal = _glowAnimation.value;
            final scaleVal = _scaleAnimation.value;
            final opacityVal = _opacityAnimation.value;
            final spacingVal = _letterSpacingAnimation.value;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Deep background subtle vignette
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [
                        Color(0xFF14101A),
                        Color(0xFF07070A),
                      ],
                    ),
                  ),
                ),

                // Cinematic Red Pulse/Aura
                Transform.scale(
                  scale: 1.0 + (glowVal * 0.4),
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryRed.withValues(alpha: 0.35 * glowVal),
                          blurRadius: 100 * glowVal + 10,
                          spreadRadius: 20 * glowVal,
                        ),
                      ],
                    ),
                  ),
                ),

                // Center animated brand logo
                Opacity(
                  opacity: opacityVal.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scaleVal,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Stylized VOIDFLIX logo
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'VOID',
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 62,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryRed,
                                  letterSpacing: spacingVal,
                                  shadows: [
                                    Shadow(
                                      color: AppTheme.primaryRed.withValues(alpha: 0.8),
                                      blurRadius: 24,
                                    ),
                                    const Shadow(
                                      color: Colors.black,
                                      offset: Offset(0, 4),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                              TextSpan(
                                text: 'FLIX',
                                style: GoogleFonts.bebasNeue(
                                  fontSize: 62,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: spacingVal,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.white70,
                                      blurRadius: 16,
                                    ),
                                    Shadow(
                                      color: Colors.black,
                                      offset: Offset(0, 4),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Sleek subtitle
                        Opacity(
                          opacity: (_controller.value * 1.5).clamp(0.0, 1.0),
                          child: Text(
                            'STREAM UNLIMITED',
                            style: GoogleFonts.inter(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom skip hint
                Positioned(
                  bottom: 30,
                  child: Opacity(
                    opacity: (_controller.value > 0.4) ? 0.35 : 0.0,
                    child: const Text(
                      'Tap anywhere to start',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 1.2,
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
