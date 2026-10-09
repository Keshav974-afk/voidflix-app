import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../core/constants/voidflix_svg_asset.dart';
import 'main_navigation_screen.dart';
import 'onboarding_screen.dart';

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
  late final WebViewController _controller;
  Timer? _timer;
  Timer? _hapticTimer1;
  Timer? _hapticTimer2;
  Timer? _hapticTimer3;
  bool _navigated = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
    }

    _controller.setNavigationDelegate(
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

    _controller.loadHtmlString(htmlContent);

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

            // Hardware-accelerated SVG renderer
            AnimatedOpacity(
              opacity: _ready ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: SizedBox.expand(
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
