import 'package:flutter_test/flutter_test.dart';
import 'package:flowflix_app/core/services/stream_extractor.dart';

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});

  test('Audit all extractors for Interstellar (TMDB 157336)', () async {
    print('\n--- TESTING TMDB FETCH DIRECTLY ---');
    try {
      final tmdbRes = await http.get(
        Uri.parse('https://api.themoviedb.org/3/movie/157336?api_key=8265bd1679663a7ea12ac168da84d2e8'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      print('TMDB direct status: ${tmdbRes.statusCode}');
      print('TMDB direct body: ${tmdbRes.body}');
    } catch (e) {
      print('TMDB direct error: $e');
    }

    print('\n--- TESTING CINEJOY LISBON ---');
    StreamExtractor.clearCache();
    try {
      final lisbon = await StreamExtractor.extractCinejoy(type: 'movie', tmdbId: 157336, preferredServer: 'Lisbon');
      print('Cinejoy Lisbon count: ${lisbon.length}');
      for (final s in lisbon) {
        print('  - ${s.sourceName} | ${s.qualityLabel} | URL: ${s.url}');
        print('    Qualities: ${s.qualities.map((q) => "${q.label}: ${q.url}").join(", ")}');
        try {
          final res = await http.get(Uri.parse(s.url), headers: s.headers);
          print('    Stream URL status: ${res.statusCode}');
        } catch (pe) {
          print('    Probe error: $pe');
        }
      }
    } catch (e, st) {
      print('Cinejoy Lisbon Error: $e\n$st');
    }

    print('\n--- TESTING CINEJOY NEBULA ---');
    try {
      final nebula = await StreamExtractor.extractCinejoy(type: 'movie', tmdbId: 157336, preferredServer: 'Nebula');
      print('Cinejoy Nebula count: ${nebula.length}');
      for (final s in nebula) {
        print('  - ${s.sourceName} | ${s.qualityLabel} | URL: ${s.url}');
      }
    } catch (e, st) {
      print('Cinejoy Nebula Error: $e\n$st');
    }

    print('\n--- TESTING VIDROCK ---');
    try {
      final vidrock = await StreamExtractor.extractVidrock(type: 'movie', tmdbId: 157336);
      print('Vidrock count: ${vidrock.length}');
      for (final s in vidrock) {
        print('  - ${s.sourceName} | URL: ${s.url}');
      }
    } catch (e, st) {
      print('Vidrock Error: $e\n$st');
    }

    print('\n--- TESTING VIDLINK ---');
    try {
      final vidlink = await StreamExtractor.extractVidlink(type: 'movie', tmdbId: 157336);
      if (vidlink != null) {
        print('Vidlink: ${vidlink.sourceName} | URL: ${vidlink.url} | Qualities: ${vidlink.qualities.length}');
      } else {
        print('Vidlink returned null');
      }
    } catch (e, st) {
      print('Vidlink Error: $e\n$st');
    }
  });
}
