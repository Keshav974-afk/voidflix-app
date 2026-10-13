import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/constants/theme_constants.dart';
import 'providers/download_provider.dart';
import 'providers/history_provider.dart';
import 'providers/media_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/watchlist_provider.dart';
import 'screens/splash_screen.dart';

class VoidflixHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Prevents 60+ second socket hangs on Wi-Fi with broken IPv6 routing
    client.connectionTimeout = const Duration(seconds: 7);
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = VoidflixHttpOverrides();

  // Dark system navigation bar & status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF121218),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const FlowflixApp());
}

class FlowflixApp extends StatelessWidget {
  const FlowflixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MediaProvider()..fetchHomeData()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProxyProvider<ProfileProvider, WatchlistProvider>(
          create: (_) => WatchlistProvider(),
          update: (_, profileProv, watchlistProv) {
            final prov = watchlistProv ?? WatchlistProvider();
            final active = profileProv.activeProfileOrNull;
            if (active != null) {
              prov.setProfile(active.id);
            }
            return prov;
          },
        ),
        ChangeNotifierProxyProvider<ProfileProvider, HistoryProvider>(
          create: (_) => HistoryProvider(),
          update: (_, profileProv, historyProv) {
            final prov = historyProv ?? HistoryProvider();
            final active = profileProv.activeProfileOrNull;
            if (active != null) {
              prov.setProfile(active.id);
            }
            return prov;
          },
        ),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()..loadDownloads()),
      ],
      child: MaterialApp(
        title: 'Voidflix',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
