import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowflix_app/core/constants/api_constants.dart';
import 'package:http/http.dart' as http;

class _RealNetworkHttpOverrides extends HttpOverrides {}

void main() {
  HttpOverrides.global = _RealNetworkHttpOverrides();

  test('Test Cinejoy Extraction in Dart', () async {
    final type = 'movie';
    final tmdbId = 157336;

    // 1. Get TMDB info
    final tmdbUri = Uri.parse(
      'https://api.themoviedb.org/3/$type/$tmdbId?api_key=${ApiConstants.tmdbApiKey}&append_to_response=external_ids',
    );
    final tmdbRes = await http.get(tmdbUri);
    expect(tmdbRes.statusCode, equals(200));
    final tmdbJson = jsonDecode(tmdbRes.body) as Map<String, dynamic>;
    final title = (tmdbJson['title'] ?? tmdbJson['name']) as String;
    final year = ((tmdbJson['release_date'] ?? tmdbJson['first_air_date'] ?? '') as String).substring(0, 4);
    final extIds = tmdbJson['external_ids'] as Map<String, dynamic>?;
    final imdbId = (tmdbJson['imdb_id'] ?? extIds?['imdb_id'] ?? '') as String;

    print('Title: $title, Year: $year, IMDb: $imdbId');

    final server = 'Lisbon';
    final tParam = type == 'movie' ? 'movie' : 'series';
    final wingUrl =
        'https://api.wing.st/?title=${Uri.encodeComponent(title)}&type=$tParam&year=$year&imdb=$imdbId&tmdb=$tmdbId&server=$server';

    print('Calling enc-cinejoy...');
    final encUri = Uri.parse('https://enc-dec.app/api/enc-cinejoy?url=${Uri.encodeComponent(wingUrl)}');
    final encRes = await http.get(encUri, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    });
    expect(encRes.statusCode, equals(200));
    final encJson = jsonDecode(encRes.body) as Map<String, dynamic>;
    expect(encJson['status'], equals(200));
    final encResult = encJson['result'] as Map<String, dynamic>;
    final encData = encResult['data'] as String;
    final encState = encResult['state']; // dynamic

    // Decode b64
    var b64 = encData.replaceAll('-', '+').replaceAll('_', '/');
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    final postBytes = base64Decode(b64);

    print('Posting to api.wing.st/g...');
    final wingRes = await http.post(
      Uri.parse('https://api.wing.st/g'),
      body: postBytes,
      headers: {
        'Accept': '*/*',
        'Origin': 'https://cinejoy.pk',
        'Referer': 'https://cinejoy.pk/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );
    expect(wingRes.statusCode, equals(200));
    final encBytes = wingRes.bodyBytes;
    print('Got encrypted response bytes: ${encBytes.length}');

    // Decrypt
    print('Calling dec-cinejoy...');
    final decUri = Uri.parse('https://enc-dec.app/api/dec-cinejoy');
    final decRes = await http.post(
      decUri,
      body: jsonEncode({
        'text': base64UrlEncode(encBytes).replaceAll('=', ''),
        'state': encState,
      }),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );
    expect(decRes.statusCode, equals(200));
    final decJson = jsonDecode(decRes.body) as Map<String, dynamic>;
    print('decJson: $decJson');
    expect(decJson['status'], equals(200));
    final dataMap = decJson['result']['data'] as Map<String, dynamic>;
    final streamList = dataMap['stream'] as List<dynamic>;
    expect(streamList.isNotEmpty, isTrue);
    final playlist = streamList.first['playlist'] as String;
    print('Extracted Playlist: $playlist');

    // Test stream playback
    final playRes = await http.get(Uri.parse(playlist));
    print('Stream playback status: ${playRes.statusCode}');
    expect(playRes.statusCode, equals(200));
    expect(playRes.body.contains('#EXTM3U'), isTrue);
    print('SUCCESS! Playlist is valid HLS.');
  });
}
