import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../core/constants/voidflix_svg_asset.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/app_analytics_service.dart';
import '../core/utils/platform_utils.dart';
import 'onboarding_screen.dart';
import 'profile_gate_screen.dart';
import 'update_required_screen.dart';

/// Authentic Netflix-Grade Splash Screen for VOIDFLIX.
///
/// Directly renders the official VOIDFLIX Logo Swoop SVG animation via
/// high-performance hardware-accelerated WebView engine, ensuring a 100% exact,
/// pixel-perfect match between the standalone SVG and in-app launch experience.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  WebViewController? _controller;
  Timer? _timer;
  Timer? _hapticTimer1;
  Timer? _hapticTimer2;
  Timer? _hapticTimer3;
  bool _navigated = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    if (PlatformUtils.isWebViewSupported) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black);

      if (controller.platform is AndroidWebViewController) {
        final android = controller.platform as AndroidWebViewController;
        android.setMediaPlaybackRequiresUserGesture(false);
      }

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _ready = true;
              });
            }
          },
        ),
      );

      // Build self-contained HTML page containing the exact VOIDFLIX logo swoop SVG
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100vw;
      height: 100vh;
      background: #000000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
      pointer-events: none;
      user-select: none;
      -webkit-user-select: none;
    }
    svg {
      width: 100vw;
      height: 100vh;
      max-width: 100%;
      max-height: 100%;
      display: block;
      object-fit: contain;
    }
  </style>
</head>
<body>
$voidflixSwoopSvg
</body>
</html>
''';
      controller.loadHtmlString(htmlContent);
      _controller = controller;
    } else {
      _ready = true;
    }

    // Synchronized tactile haptics matching the SVG animation milestones
    // 1. Ribbon V emergence
    _hapticTimer1 = Timer(const Duration(milliseconds: 200), () {
      HapticFeedback.lightImpact();
    });
    // 2. Swoop glide and scale lock
    _hapticTimer2 = Timer(const Duration(milliseconds: 1750), () {
      HapticFeedback.mediumImpact();
    });
    // 3. Ta-dum impact lock
    _hapticTimer3 = Timer(const Duration(milliseconds: 2550), () {
      HapticFeedback.heavyImpact();
    });

    // Proceed to next screen after animation completes (3200ms)
    _timer = Timer(const Duration(milliseconds: 3200), () {
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

    // 3. Strict Version Gating: If current app version is older, DO NOT RUN THE APP.
    // Only show "Please update your app" screen!
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
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  void _cancelTimers() {
    _timer?.cancel();
    _hapticTimer1?.cancel();
    _hapticTimer2?.cancel();
    _hapticTimer3?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _proceedNext,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pure black backdrop
            const ColoredBox(color: Colors.black),

            // Hardware-accelerated SVG renderer (mobile) or Native Flutter Glow Logo (desktop)
            if (_controller != null)
              AnimatedOpacity(
                opacity: _ready ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: SizedBox.expand(
                  child: WebViewWidget(controller: _controller!),
                ),
              )
            else
              const SizedBox.expand(
                child: _NativeNetflixCinematicIntro(),
              ),
          ],
        ),
      ),
    );
  }
}

class _NativeNetflixCinematicIntro extends StatefulWidget {
  const _NativeNetflixCinematicIntro();

  @override
  State<_NativeNetflixCinematicIntro> createState() => _NativeNetflixCinematicIntroState();
}

class _NativeNetflixCinematicIntroState extends State<_NativeNetflixCinematicIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _NetflixCinematicPainter(progress: _controller.value),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 180),
                // Glowing VOIDFLIX Wordmark
                Opacity(
                  opacity: (_controller.value < 0.4)
                      ? 0.0
                      : ((_controller.value - 0.4) / 0.3).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * ((_controller.value - 0.4) / 0.6).clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'VOIDFLIX',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 54,
                            letterSpacing: 8,
                            color: const Color(0xFFE50914),
                            shadows: [
                              Shadow(
                                color: const Color(0xFFE50914).withValues(alpha: 0.8),
                                blurRadius: 28,
                              ),
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.9),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ULTRA HD STREAMING',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(
                              alpha: (_controller.value < 0.55)
                                  ? 0.0
                                  : ((_controller.value - 0.55) / 0.35).clamp(0.0, 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NetflixCinematicPainter extends CustomPainter {
  final double progress;

  _NetflixCinematicPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);

    // 1. Deep Core Ambient Crimson Glow
    final glowProgress = (progress < 0.3)
        ? progress / 0.3
        : (progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3));
    final glowRadius = (size.shortestSide * 0.45) * (0.8 + 0.3 * glowProgress);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE50914).withValues(alpha: 0.28 * glowProgress),
          const Color(0xFF900008).withValues(alpha: 0.12 * glowProgress),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));

    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Prismatic Light Streaks / Spectrum Blast (The iconic Netflix transition)
    if (progress > 0.45) {
      final rayProgress = ((progress - 0.45) / 0.50).clamp(0.0, 1.0);
      final rayOpacity = (rayProgress < 0.3)
          ? rayProgress / 0.3
          : (1.0 - (rayProgress - 0.3) / 0.7);

      final rayColors = [
        const Color(0xFFE50914), // Red
        const Color(0xFFD50000), // Dark Red
        const Color(0xFF9C27B0), // Purple
        const Color(0xFF673AB7), // Deep Purple
        const Color(0xFF2196F3), // Blue
        const Color(0xFF00E5FF), // Cyan
        const Color(0xFF00B0FF), // Light Blue
        const Color(0xFFFF4081), // Pink
        const Color(0xFFFF1744), // Neon Red
        const Color(0xFFFF9100), // Orange
        const Color(0xFFFFD600), // Yellow
        const Color(0xFF00E676), // Green
        const Color(0xFF651FFF), // Indigo
        const Color(0xFFE50914), // Red
      ];

      final rayCount = rayColors.length;
      final rayWidth = size.width * 0.015;
      final maxRayHeight = size.height * 0.95;

      for (int i = 0; i < rayCount; i++) {
        final relIdx = (i - rayCount / 2);
        final xOffset = center.dx + relIdx * (rayWidth * 2.4);
        final color = rayColors[i];
        final currentRayHeight = maxRayHeight * (0.3 + 0.7 * Curves.easeOutCubic.transform(rayProgress));

        final rayPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              color.withValues(alpha: 0.75 * rayOpacity),
              color.withValues(alpha: 0.95 * rayOpacity),
              color.withValues(alpha: 0.75 * rayOpacity),
              Colors.transparent,
            ],
            stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          ).createShader(Rect.fromLTWH(
            xOffset - rayWidth / 2,
            center.dy - currentRayHeight / 2,
            rayWidth,
            currentRayHeight,
          ));

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              xOffset - rayWidth / 2,
              center.dy - currentRayHeight / 2,
              rayWidth,
              currentRayHeight,
            ),
            const Radius.circular(2),
          ),
          rayPaint,
        );
      }
    }

    // 3. The 3D Ribbon 'V' Monogram
    canvas.save();
    canvas.translate(center.dx, center.dy - 35);

    // Hero scale expansion
    final scaleProgress = Curves.easeOutCubic.transform(progress.clamp(0.0, 0.7) / 0.7);
    final scale = 0.5 + 0.5 * scaleProgress;
    canvas.scale(scale, scale);

    final ribbonHeight = 160.0;
    final ribbonWidth = 34.0;
    final armSpread = 58.0;

    // Left Ribbon Arm (Dark Crimson base fold)
    final leftArmProgress = Curves.easeInOut.transform(progress.clamp(0.0, 0.4) / 0.4);
    if (leftArmProgress > 0) {
      final leftPath = Path()
        ..moveTo(-armSpread, -ribbonHeight / 2)
        ..lineTo(-armSpread + ribbonWidth, -ribbonHeight / 2)
        ..lineTo(ribbonWidth / 2 * leftArmProgress, (ribbonHeight / 2) * leftArmProgress)
        ..lineTo((-ribbonWidth / 2) * leftArmProgress, (ribbonHeight / 2) * leftArmProgress)
        ..close();

      final leftShader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF800004),
          Color(0xFFB1060F),
          Color(0xFF6B0003),
        ],
      ).createShader(Rect.fromLTWH(-armSpread, -ribbonHeight / 2, armSpread + ribbonWidth, ribbonHeight));

      canvas.drawPath(leftPath, Paint()..shader = leftShader);
    }

    // Shadow cast by Right Arm onto Left Arm
    if (progress > 0.15) {
      final shadowProgress = Curves.easeInOut.transform(((progress - 0.15) / 0.35).clamp(0.0, 1.0));
      final shadowPath = Path()
        ..moveTo(-8, -20)
        ..lineTo(ribbonWidth, -ribbonHeight / 2)
        ..lineTo(armSpread, -ribbonHeight / 2)
        ..lineTo(0, (ribbonHeight / 2) * shadowProgress)
        ..close();

      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.65 * shadowProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      canvas.drawPath(shadowPath, shadowPaint);
    }

    // Right Ribbon Arm (Foreground vibrant red with drop shadow)
    final rightArmProgress = Curves.easeInOut.transform(((progress - 0.1) / 0.4).clamp(0.0, 1.0));
    if (rightArmProgress > 0) {
      final rightPath = Path()
        ..moveTo(armSpread, -ribbonHeight / 2)
        ..lineTo(armSpread - ribbonWidth, -ribbonHeight / 2)
        ..lineTo((-ribbonWidth / 2) * rightArmProgress, (ribbonHeight / 2) * rightArmProgress)
        ..lineTo((ribbonWidth / 2) * rightArmProgress, (ribbonHeight / 2) * rightArmProgress)
        ..close();

      // Outer glow for Right Arm
      final rightGlowPaint = Paint()
        ..color = const Color(0xFFE50914).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawPath(rightPath, rightGlowPaint);

      final rightShader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color(0xFFFF2430),
          Color(0xFFE50914),
          Color(0xFFB1060F),
        ],
      ).createShader(Rect.fromLTWH(-ribbonWidth / 2, -ribbonHeight / 2, armSpread + ribbonWidth, ribbonHeight));

      canvas.drawPath(rightPath, Paint()..shader = rightShader);

      // High-Gloss Specular Edge Line
      final sheenPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(armSpread, -ribbonHeight / 2),
        Offset(ribbonWidth / 2 * rightArmProgress, ribbonHeight / 2 * rightArmProgress),
        sheenPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NetflixCinematicPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
