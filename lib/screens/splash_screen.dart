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
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.85, end: 1.0),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE50914).withValues(alpha: 0.15),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE50914).withValues(alpha: 0.4),
                              blurRadius: 32,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'VOIDFLIX',
                        style: GoogleFonts.bebasNeue(
                          fontSize: 48,
                          letterSpacing: 6,
                          color: const Color(0xFFE50914),
                          shadows: [
                            Shadow(
                              color: const Color(0xFFE50914).withValues(alpha: 0.6),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ULTRA HD STREAMING',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
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
  }
}
