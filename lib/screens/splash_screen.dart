import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
import 'main_navigation_screen.dart';
import 'onboarding_screen.dart';

/// OP Cinematic Netflix-grade Splash Screen for VOIDFLIX.
///
/// Features:
/// 1. Authentic 3D Ribbon 'V' monogram emergence with crimson gradients & drop shadow.
/// 2. Iconic Netflix "Swoop" glide & scale using exact cubic bezier splines (0.684, 0, 0.455, 1).
/// 3. Curved arch typography reveal of "OIDFLIX" sequentially unfurling from behind the ribbon.
/// 4. Synchronized multi-stage haptic feedback (emergence, lock, ta-dum burst).
/// 5. Dramatic "Ta-dum" zoom into camera lens with prismatic vertical spectral light beams.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Animation Curves
  late Animation<double> _ribbonDrawProgress;
  late Animation<double> _swoopProgress;
  late Animation<double> _swoopScale;
  late Animation<double> _wordmarkReveal;
  late Animation<double> _gleamProgress;
  late Animation<double> _zoomAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _ambientGlow;

  Timer? _timer;
  bool _navigated = false;
  bool _hapticStage1Triggered = false;
  bool _hapticStage2Triggered = false;
  bool _hapticStage3Triggered = false;

  @override
  void initState() {
    super.initState();

    // 2800ms total runtime: punchy, authentic, deeply cinematic
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // 1. Ribbon V emergence in center (0% - 35%)
    _ribbonDrawProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
    );

    // 2. The Iconic Netflix Swoop translation (36% - 58%)
    // Exact cubic spline matching Netflix Logo Swoop.svg: keySplines="0.684 0 0.455 1"
    _swoopProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.36, 0.58, curve: Cubic(0.684, 0.0, 0.455, 1.0)),
    );

    // 3. Swoop Scale down from Hero to Wordmark size (34% - 56%)
    // Exact cubic spline matching Netflix SVG: keySplines="0.655 0 0.461 1"
    _swoopScale = Tween<double>(begin: 1.0, end: 0.34).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.56, curve: Cubic(0.655, 0.0, 0.461, 1.0)),
      ),
    );

    // 4. Wordmark letters "OIDFLIX" unfurl from behind swooping ribbon (42% - 68%)
    _wordmarkReveal = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 0.68, curve: Curves.easeOutCubic),
    );

    // 5. Logo lock gleam (68% - 74%)
    _gleamProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 0.74, curve: Curves.easeInOut),
    );

    // 6. Ambient crimson background pulse (10% - 75%)
    _ambientGlow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.75, curve: Curves.easeInOut),
    );

    // 7. Iconic Ta-Dum exponential zoom into camera (75% - 100%)
    _zoomAnimation = Tween<double>(begin: 1.0, end: 12.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 1.0, curve: Curves.easeInExpo),
      ),
    );

    // 8. Final camera fade out (86% - 100%)
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.86, 1.0, curve: Curves.easeIn),
      ),
    );

    // Listener for synchronized tactile haptics
    _controller.addListener(() {
      final val = _controller.value;
      if (val >= 0.15 && !_hapticStage1Triggered) {
        _hapticStage1Triggered = true;
        HapticFeedback.lightImpact();
      }
      if (val >= 0.60 && !_hapticStage2Triggered) {
        _hapticStage2Triggered = true;
        HapticFeedback.mediumImpact();
      }
      if (val >= 0.75 && !_hapticStage3Triggered) {
        _hapticStage3Triggered = true;
        HapticFeedback.heavyImpact();
      }
    });

    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 2750), () {
      _proceedNext();
    });
  }

  Future<void> _proceedNext() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _timer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final bool alreadyDone = prefs.getBool('voidflix_global_onboarding_completed') ?? false;
    final String? profilesList = prefs.getString('voidflix_profiles_list');
    final bool hasProfiles = profilesList != null && profilesList.isNotEmpty && profilesList != '[]';

    Widget target;
    if (!alreadyDone && !hasProfiles) {
      target = const OnboardingScreen();
    } else {
      target = const MainNavigationScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => target,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 450),
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
      onTap: _proceedNext,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final ribbonVal = _ribbonDrawProgress.value;
            final swoopVal = _swoopProgress.value;
            final swoopScaleVal = _swoopScale.value;
            final wordmarkVal = _wordmarkReveal.value;
            final gleamVal = _gleamProgress.value;
            final glowVal = _ambientGlow.value;
            final zoomVal = _zoomAnimation.value;
            final fadeVal = _fadeAnimation.value;

            // Dimensions for the swoop trajectory
            // The wordmark total width is approx 230px, centered at (0, 0).
            // 'V' position is on the far left of VOIDFLIX (around X = -100px).
            const double targetVx = -99.0;
            const double targetVy = 0.0;
            final currentVx = targetVx * swoopVal;
            final currentVy = targetVy * swoopVal;

            return Stack(
              alignment: Alignment.center,
              children: [
                // 1. OLED Pure Black Background
                const ColoredBox(color: Colors.black),

                // 2. Subtle Cinematic Crimson Ambient Radial Glow
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.85,
                        colors: [
                          AppTheme.primaryRed.withValues(alpha: 0.20 * glowVal),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Prismatic Spectral Light Beams (erupts during Ta-dum zoom)
                if (_controller.value >= 0.70)
                  Positioned.fill(
                    child: Opacity(
                      opacity: ((_controller.value - 0.70) / 0.20).clamp(0.0, 1.0) * fadeVal,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _NetflixSpectralBeamsPainter(
                          progress: (_controller.value - 0.70) / 0.30,
                        ),
                      ),
                    ),
                  ),

                // 4. Central Hero Container (Monogram + Arched Wordmark)
                Opacity(
                  opacity: fadeVal.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: zoomVal,
                    child: Center(
                      child: SizedBox(
                        width: 320,
                        height: 180,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // --- LAYER A: Trailing Letters (OIDFLIX) ---
                            // Arched curved baseline matching the authentic Netflix smile
                            _buildArchedLetters(wordmarkVal, gleamVal),

                            // --- LAYER B: The Swooping 3D Ribbon 'V' ---
                            Transform.translate(
                              offset: Offset(currentVx, currentVy),
                              child: Transform.scale(
                                scale: swoopScaleVal,
                                child: SizedBox(
                                  width: 110,
                                  height: 120,
                                  child: CustomPaint(
                                    size: const Size(110, 120),
                                    painter: _NetflixRibbonVPainter(
                                      progress: ribbonVal,
                                      gleam: gleamVal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 5. Subtle "Tap to skip" prompt for accessibility
                Positioned(
                  bottom: 30,
                  child: Opacity(
                    opacity: (_controller.value > 0.40 && _controller.value < 0.75) ? 0.40 : 0.0,
                    child: const Text(
                      'Tap to skip',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w500,
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

  /// Builds the arched trailing letters "OIDFLIX" with Netflix concave baseline arch
  Widget _buildArchedLetters(double revealProgress, double gleam) {
    if (revealProgress <= 0.0) {
      return const SizedBox.shrink();
    }

    // Letters following 'V' in VOIDFLIX:
    const letters = ['O', 'I', 'D', 'F', 'L', 'I', 'X'];

    // Relative X positions for each letter centered around the wordmark
    // V is at -99
    const xOffsets = [-66.0, -42.0, -22.0, 6.0, 32.0, 54.0, 78.0];

    // Arch baseline offsets (concave upward curve: center lifted higher than edges)
    // Parabolic arc formula: dy = (1 - (dist / maxDist)^2) * -archHeight
    // OIDFLIX center is around 'F' (index 3), lifted up by ~6.5px
    const archOffsets = [-2.8, -4.5, -6.0, -6.5, -5.8, -4.2, -1.5];

    return Stack(
      alignment: Alignment.center,
      children: List.generate(letters.length, (index) {
        final letter = letters[index];
        final targetX = xOffsets[index];
        final archY = archOffsets[index];

        // Staggered reveal from left to right as the ribbon swoops past
        final letterDelay = index * 0.08;
        final letterProgress = ((revealProgress - letterDelay) / 0.50).clamp(0.0, 1.0);

        if (letterProgress <= 0.0) return const SizedBox.shrink();

        // Slide in slightly from the right as it reveals
        final slideX = targetX + (12.0 * (1.0 - letterProgress));

        return Transform.translate(
          offset: Offset(slideX, archY),
          child: Opacity(
            opacity: letterProgress,
            child: Text(
              letter,
              style: GoogleFonts.bebasNeue(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryRed,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: AppTheme.primaryRed.withValues(alpha: 0.55 + 0.40 * gleam),
                    blurRadius: 16 + (gleam * 12),
                  ),
                  const Shadow(
                    color: Colors.black,
                    offset: Offset(0, 3),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Custom painter for the authentic 3D Ribbon 'V' monogram
/// Left Arm: Deep Crimson base layer (#8B0007 - #B80B14)
/// Right Arm: Vivid Scarlet Red (#E50914 - #FF2B33) overlapping with realistic cast shadow
class _NetflixRibbonVPainter extends CustomPainter {
  final double progress;
  final double gleam;

  _NetflixRibbonVPainter({
    required this.progress,
    required this.gleam,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;

    // --- 1. LEFT ARM OF THE 'V' (Base layer, dark crimson) ---
    final leftPath = Path();
    leftPath.moveTo(w * 0.10, 0);
    leftPath.lineTo(w * 0.38, 0);
    leftPath.lineTo(w * 0.52, h * progress);
    leftPath.lineTo(w * 0.24, h * progress);
    leftPath.close();

    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF8B0007),
          Color(0xFFB80B14),
          Color(0xFF94040B),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(leftPath, leftPaint);

    // --- 2. CAST SHADOW FROM OVERLAPPING RIGHT ARM ---
    final shadowPath = Path();
    shadowPath.moveTo(w * 0.44, 0);
    shadowPath.lineTo(w * 0.54, 0);
    shadowPath.lineTo(w * 0.54, h * progress);
    shadowPath.lineTo(w * 0.34, h * progress);
    shadowPath.close();

    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0.70),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(shadowPath, shadowPaint);

    // --- 3. RIGHT ARM OF THE 'V' (Foreground ribbon, bright Netflix red) ---
    final rightPath = Path();
    rightPath.moveTo(w * 0.90, 0);
    rightPath.lineTo(w * 0.62, 0);
    rightPath.lineTo(w * 0.48, h * progress);
    rightPath.lineTo(w * 0.76, h * progress);
    rightPath.close();

    final rightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFE50914),
          Color.lerp(const Color(0xFFFF222A), Colors.white, gleam * 0.35)!,
          const Color(0xFFD80812),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.4);

    canvas.drawPath(rightPath, rightPaint);

    // --- 4. GLOSS HIGHLIGHT ALONG RIGHT OUTER EDGE ---
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * progress + 0.35 * gleam)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(w * 0.90, 0),
      Offset(w * 0.76, h * progress),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NetflixRibbonVPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.gleam != gleam;
  }
}

/// Custom painter for signature Netflix Ta-dum vertical spectral light rays
class _NetflixSpectralBeamsPainter extends CustomPainter {
  final double progress;

  _NetflixSpectralBeamsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final random = math.Random(1337);

    const beamCount = 38;
    for (int i = 0; i < beamCount; i++) {
      final x = (i / beamCount) * w + (random.nextDouble() * 4 - 2);
      final beamHeight = h * (0.45 + random.nextDouble() * 0.55) * progress.clamp(0.0, 1.0);
      final yStart = (h - beamHeight) / 2;

      Color beamColor;
      if (i % 6 == 0) {
        // Crisp white prism streak
        beamColor = Colors.white.withValues(alpha: 0.55 * progress.clamp(0.0, 1.0));
      } else if (i % 4 == 0) {
        // Bright magenta/violet spectrum
        beamColor = const Color(0xFFFF2277).withValues(alpha: 0.65 * progress.clamp(0.0, 1.0));
      } else if (i % 3 == 0) {
        // Neon scarlet
        beamColor = const Color(0xFFFF3838).withValues(alpha: 0.75 * progress.clamp(0.0, 1.0));
      } else {
        // Deep Netflix crimson
        beamColor = const Color(0xFFE50914).withValues(alpha: (0.3 + random.nextDouble() * 0.5) * progress.clamp(0.0, 1.0));
      }

      final beamPaint = Paint()
        ..color = beamColor
        ..strokeWidth = 2.0 + random.nextDouble() * 3.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);

      canvas.drawLine(
        Offset(x, yStart),
        Offset(x, yStart + beamHeight),
        beamPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetflixSpectralBeamsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
