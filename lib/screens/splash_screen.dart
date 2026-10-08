import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
import 'main_navigation_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _ribbonProgress;
  late Animation<double> _glowAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _zoomAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // 1. Ribbon growth & emergence (0% - 40%)
    _ribbonProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
    );

    // 2. Ambient crimson pulse & spectral ray expansion (20% - 70%)
    _glowAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.70, curve: Curves.easeInOut),
    );

    // 3. Brand text reveal (35% - 70%)
    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.70, curve: Curves.easeIn),
    );

    // 4. Dramatic Netflix Ta-dum zoom into camera (72% - 100%)
    _zoomAnimation = Tween<double>(begin: 1.0, end: 8.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.72, 1.0, curve: Curves.easeInExpo),
      ),
    );

    // 5. Fade out at the very end of zoom (85% - 100%)
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.82, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 2550), () {
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
      // Seamless Netflix experience: proceed straight into main navigation
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
            final ribbonVal = _ribbonProgress.value;
            final glowVal = _glowAnimation.value;
            final textVal = _textFadeAnimation.value;
            final zoomVal = _zoomAnimation.value;
            final fadeVal = _fadeAnimation.value;

            return Stack(
              alignment: Alignment.center,
              children: [
                // 1. Pure cinematic black background with subtle radial crimson glow
                Container(
                  color: Colors.black,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.9,
                        colors: [
                          AppTheme.primaryRed.withValues(alpha: 0.16 * glowVal),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Central Zoom Container (Monogram + Spectral Spectrum + Brand)
                Opacity(
                  opacity: fadeVal.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: zoomVal,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Netflix-style 3D V Monogram with Spectral Beams
                          SizedBox(
                            width: 140,
                            height: 150,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Ambient spectral light beams
                                CustomPaint(
                                  size: const Size(140, 150),
                                  painter: _NetflixSpectralBeamsPainter(
                                    progress: glowVal,
                                  ),
                                ),
                                // 3D Ribbon Monogram
                                CustomPaint(
                                  size: const Size(110, 120),
                                  painter: _NetflixMonogramPainter(
                                    progress: ribbonVal,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Brand Title: VOIDFLIX
                          Opacity(
                            opacity: textVal.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1.0 - textVal)),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'VOID',
                                          style: GoogleFonts.bebasNeue(
                                            fontSize: 54,
                                            fontWeight: FontWeight.w900,
                                            color: AppTheme.primaryRed,
                                            letterSpacing: 8.0,
                                            shadows: [
                                              Shadow(
                                                color: AppTheme.primaryRed.withValues(alpha: 0.75),
                                                blurRadius: 28,
                                              ),
                                              const Shadow(
                                                color: Colors.black,
                                                offset: Offset(0, 4),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'FLIX',
                                          style: GoogleFonts.bebasNeue(
                                            fontSize: 54,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 8.0,
                                            shadows: const [
                                              Shadow(
                                                color: Colors.white60,
                                                blurRadius: 18,
                                              ),
                                              Shadow(
                                                color: Colors.black,
                                                offset: Offset(0, 4),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'WATCH UNLIMITED',
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 5.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Subtle skip hint at bottom
                Positioned(
                  bottom: 28,
                  child: Opacity(
                    opacity: (_controller.value > 0.45 && _controller.value < 0.8) ? 0.35 : 0.0,
                    child: const Text(
                      'Tap to skip',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.4,
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

/// Custom painter that creates the authentic Netflix 3D ribbon "V" monogram
class _NetflixMonogramPainter extends CustomPainter {
  final double progress;

  _NetflixMonogramPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;

    // Left Arm of the V (Deep Crimson base layer)
    final leftPath = Path();
    leftPath.moveTo(w * 0.12, 0);
    leftPath.lineTo(w * 0.38, 0);
    leftPath.lineTo(w * 0.52, h * progress);
    leftPath.lineTo(w * 0.26, h * progress);
    leftPath.close();

    final leftPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF8B0007),
          Color(0xFFB80B14),
          Color(0xFF98040C),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(leftPath, leftPaint);

    // Cast shadow from overlapping Right Arm onto Left Arm
    final shadowPath = Path();
    shadowPath.moveTo(w * 0.45, 0);
    shadowPath.lineTo(w * 0.54, 0);
    shadowPath.lineTo(w * 0.54, h * progress);
    shadowPath.lineTo(w * 0.35, h * progress);
    shadowPath.close();

    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0.65),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(shadowPath, shadowPaint);

    // Right Arm of the V (Bright foreground ribbon with glossy flame red)
    final rightPath = Path();
    rightPath.moveTo(w * 0.88, 0);
    rightPath.lineTo(w * 0.62, 0);
    rightPath.lineTo(w * 0.48, h * progress);
    rightPath.lineTo(w * 0.74, h * progress);
    rightPath.close();

    final rightPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFE50914),
          Color(0xFFFF222A),
          Color(0xFFD80812),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.5);

    canvas.drawPath(rightPath, rightPaint);

    // Gloss highlight along right edge
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28 * progress)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(w * 0.88, 0),
      Offset(w * 0.74, h * progress),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NetflixMonogramPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Custom painter for the signature Netflix spectral vertical light beams
class _NetflixSpectralBeamsPainter extends CustomPainter {
  final double progress;

  _NetflixSpectralBeamsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final random = math.Random(42);

    // Draw vertical spectral beam bars resembling the Ta-dum light spectrum
    const beamCount = 28;
    for (int i = 0; i < beamCount; i++) {
      final x = (i / beamCount) * w + (random.nextDouble() * 3 - 1.5);
      final beamHeight = h * (0.4 + random.nextDouble() * 0.6) * progress;
      final yStart = (h - beamHeight) / 2;

      // Color variation: crimson, scarlet, flame red, with rare white streaks
      Color beamColor;
      if (i % 7 == 0) {
        beamColor = Colors.white.withValues(alpha: 0.45 * progress);
      } else if (i % 4 == 0) {
        beamColor = const Color(0xFFFF414A).withValues(alpha: 0.6 * progress);
      } else {
        beamColor = const Color(0xFFE50914).withValues(alpha: (0.2 + random.nextDouble() * 0.5) * progress);
      }

      final beamPaint = Paint()
        ..color = beamColor
        ..strokeWidth = 1.8 + random.nextDouble() * 2.2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

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
