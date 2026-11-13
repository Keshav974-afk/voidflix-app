import 'package:flutter_test/flutter_test.dart';
import 'package:flowflix_app/models/media_detail.dart';

void main() {
  group('Trailer and Clips Selection Tests', () {
    test('Trailer selection strictly ignores clips and behind the scenes', () {
      final detail = MediaDetail(
        id: 101,
        title: 'Epic Movie',
        overview: 'Overview',
        voteAverage: 8.5,
        mediaType: 'movie',
        genres: ['Action'],
        originalLanguage: 'ja',
        videos: [
          MediaVideo(
            id: 'v1',
            name: 'Cast Interview and B-Roll',
            key: 'key_bts_1',
            site: 'YouTube',
            type: 'Behind the Scenes',
            iso6391: 'en',
            official: true,
          ),
          MediaVideo(
            id: 'v2',
            name: 'Climactic Fight Scene Clip',
            key: 'key_clip_1',
            site: 'YouTube',
            type: 'Clip',
            iso6391: 'en',
            official: true,
          ),
          MediaVideo(
            id: 'v3',
            name: 'Director Featurette',
            key: 'key_feat_1',
            site: 'YouTube',
            type: 'Featurette',
            iso6391: 'ja',
            official: true,
          ),
        ],
      );

      // Since there are only BTS, Clips, and Featurettes, findTrailerKey MUST return null!
      final trailer = detail.findTrailerKey(preferredLangCode: 'en');
      expect(trailer, isNull);

      // But findBestClipVideo MUST find the clips / BTS!
      final bestClipEn = detail.findBestClipVideo(preferredLangCode: 'en');
      expect(bestClipEn, isNotNull);
      expect(bestClipEn!.key, equals('key_clip_1')); // Prefers actual clip over BTS
    });

    test('Trailer selection honors preferred language, then original language, then English', () {
      final detail = MediaDetail(
        id: 102,
        title: 'Demon Slayer: Mugen Train',
        overview: 'Tanjiro and the Demon Slayer Corps',
        voteAverage: 9.0,
        mediaType: 'movie',
        genres: ['Animation', 'Action'],
        originalLanguage: 'ja',
        videos: [
          MediaVideo(
            id: 'v_en_trailer',
            name: 'Official English Dub Trailer',
            key: 'key_en_trailer',
            site: 'YouTube',
            type: 'Trailer',
            iso6391: 'en',
            official: true,
          ),
          MediaVideo(
            id: 'v_ja_trailer',
            name: 'Official Main Japanese Trailer',
            key: 'key_ja_trailer',
            site: 'YouTube',
            type: 'Trailer',
            iso6391: 'ja',
            official: true,
          ),
          MediaVideo(
            id: 'v_hi_trailer',
            name: 'Official Hindi Trailer',
            key: 'key_hi_trailer',
            site: 'YouTube',
            type: 'Trailer',
            iso6391: 'hi',
            official: true,
          ),
          MediaVideo(
            id: 'v_bts',
            name: 'Making of Animation',
            key: 'key_bts',
            site: 'YouTube',
            type: 'Behind the Scenes',
            iso6391: 'hi',
            official: true,
          ),
        ],
      );

      // 1. User prefers Hindi -> must pick Hindi official trailer (NOT Hindi BTS)
      final hiTrailer = detail.findTrailerKey(preferredLangCode: 'hi');
      expect(hiTrailer, equals('key_hi_trailer'));

      // 2. User prefers Spanish (no Spanish trailer available) -> must fall back to original language (ja)
      final esTrailer = detail.findTrailerKey(preferredLangCode: 'es');
      expect(esTrailer, equals('key_ja_trailer'));

      // 3. User prefers English -> must pick English trailer
      final enTrailer = detail.findTrailerKey(preferredLangCode: 'en');
      expect(enTrailer, equals('key_en_trailer'));
    });

    test('Clips section prioritizes BTS and Clips over trailers', () {
      final detail = MediaDetail(
        id: 103,
        title: 'Ramayana: Rise of a Legend',
        overview: 'The legend begins',
        voteAverage: 8.9,
        mediaType: 'movie',
        genres: ['Action', 'Fantasy'],
        originalLanguage: 'hi',
        videos: [
          MediaVideo(
            id: 'v_hi_trailer',
            name: 'Official Trailer',
            key: 'key_hi_trailer',
            site: 'YouTube',
            type: 'Trailer',
            iso6391: 'hi',
            official: true,
          ),
          MediaVideo(
            id: 'v_hi_bts',
            name: 'Vision of Ramayana',
            key: 'key_hi_bts',
            site: 'YouTube',
            type: 'Behind the Scenes',
            iso6391: 'hi',
            official: true,
          ),
        ],
      );

      // Trailer section MUST pick trailer
      final trailer = detail.findTrailerKey(preferredLangCode: 'hi');
      expect(trailer, equals('key_hi_trailer'));

      // Clips section MUST pick BTS
      final clip = detail.findBestClipVideo(preferredLangCode: 'hi');
      expect(clip, isNotNull);
      expect(clip!.key, equals('key_hi_bts'));
      expect(clip.isBehindTheScenes, isTrue);
    });
  });
}
