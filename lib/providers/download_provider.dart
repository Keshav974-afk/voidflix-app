import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/stream_extractor.dart';
import '../core/services/subtitle_service.dart';
import '../core/utils/language_utils.dart';
import '../models/downloaded_item.dart';

class _DownloadCandidate {
  final String url;
  final Map<String, String> headers;
  final bool isHls;
  final String qualityLabel;
  final String serverName;
  final String audioLanguage;
  final int height;
  final int score;

  const _DownloadCandidate({
    required this.url,
    required this.headers,
    required this.isHls,
    required this.qualityLabel,
    this.serverName = 'Direct',
    this.audioLanguage = 'Original',
    this.height = 1080,
    this.score = 0,
  });

  _DownloadCandidate copyWith({
    String? url,
    Map<String, String>? headers,
    bool? isHls,
    String? qualityLabel,
    String? serverName,
    String? audioLanguage,
    int? height,
    int? score,
  }) {
    return _DownloadCandidate(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      isHls: isHls ?? this.isHls,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      serverName: serverName ?? this.serverName,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      height: height ?? this.height,
      score: score ?? this.score,
    );
  }
}

class _HlsVariantCandidate {
  final String url;
  final int height;
  const _HlsVariantCandidate({required this.url, required this.height});
}

class DownloadProvider extends ChangeNotifier {
  static const String _storageKey = 'voidflix_downloads_data';
  static const _notifChannel = MethodChannel('org.voidflix/notifications');

  final List<DownloadedItem> _items = [];
  final Map<String, http.Client> _activeClients = {};
  String? _activeProfileId;

  void setActiveProfileId(String? id) {
    if (_activeProfileId != id) {
      _activeProfileId = id;
      notifyListeners();
    }
  }

  String? get activeProfileId => _activeProfileId;

  List<DownloadedItem> get items {
    if (_activeProfileId == null || _activeProfileId!.isEmpty) {
      return List.unmodifiable(_items);
    }
    return List.unmodifiable(
      _items.where((i) => i.profileId == null || i.profileId == _activeProfileId).toList(),
    );
  }

  List<DownloadedItem> get completedItems =>
      items.where((i) => i.status == 'completed').toList();

  /// Sanitizes title by removing any attached season/episode tags (e.g. ": S1E2 ...")
  static String sanitizeTitle(String rawTitle) {
    if (rawTitle.isEmpty) return rawTitle;
    final regex = RegExp(r':\s*S\d+.*$', caseSensitive: false);
    return rawTitle.replaceAll(regex, '').trim();
  }

  static String generateId(String mediaType, int mediaId, {int season = 1, int episode = 1}) {
    if (mediaType == 'tv') {
      return 'tv_${mediaId}_s${season}_e$episode';
    }
    return 'movie_$mediaId';
  }

  static Future<void> _updateSystemNotification({
    required int id,
    required String title,
    required int progress,
    bool isDone = false,
  }) async {
    try {
      await _notifChannel.invokeMethod('updateDownloadProgress', {
        'id': id,
        'title': title,
        'progress': progress,
        'isDone': isDone,
      });
    } catch (_) {}
  }

  static Future<void> _cancelSystemNotification(int id) async {
    try {
      await _notifChannel.invokeMethod('cancelDownloadNotification', {
        'id': id,
      });
    } catch (_) {}
  }

  Future<void> loadDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _items.clear();
        for (final item in list) {
          final d = DownloadedItem.fromJson(item as Map<String, dynamic>);
          final cleanTitle = sanitizeTitle(d.title);
          var current = cleanTitle != d.title ? d.copyWith(title: cleanTitle) : d;

          // Attach offline subtitle if available on disk but not yet linked
          if (current.localSubtitlePath == null || current.localSubtitlePath!.isEmpty || !File(current.localSubtitlePath!).existsSync()) {
            final downloadDir = File(current.localFilePath).parent;
            String? resolvedSub;
            final manifestFile = File('${downloadDir.path}/${current.id}_subs.json');
            if (manifestFile.existsSync()) {
              try {
                final subsList = jsonDecode(manifestFile.readAsStringSync()) as List;
                if (subsList.isNotEmpty && subsList.first['path'] != null) {
                  final candidate = subsList.first['path'] as String;
                  if (File(candidate).existsSync()) {
                    resolvedSub = candidate;
                  }
                }
              } catch (_) {}
            }
            if (resolvedSub == null || !File(resolvedSub).existsSync()) {
              try {
                final matching = downloadDir
                    .listSync()
                    .whereType<File>()
                    .where((f) => f.path.contains('${current.id}_sub_') && (f.path.endsWith('.vtt') || f.path.endsWith('.srt')))
                    .toList();
                if (matching.isNotEmpty) {
                  resolvedSub = matching.first.path;
                }
              } catch (_) {}
            }
            if (resolvedSub == null) {
              final subFile = File('${current.localFilePath.replaceAll('.mp4', '')}_sub_en.vtt');
              if (subFile.existsSync()) {
                resolvedSub = subFile.path;
              }
            }
            if (resolvedSub != null && File(resolvedSub).existsSync()) {
              current = current.copyWith(localSubtitlePath: resolvedSub);
            }
          }

          final file = File(current.localFilePath);
          final partFile = File('${current.localFilePath}.part');
          final segDir = Directory('${current.localFilePath}.segments');

          // Verify completed items actually exist and are non-empty (> 100KB)
          if (current.status == 'completed') {
            if (file.existsSync() && file.lengthSync() > 100000) {
              _items.add(current);
            } else {
              // File was missing or corrupted while app was closed
              if (file.existsSync()) {
                try {
                  file.deleteSync();
                } catch (_) {}
              }
              _items.add(current.copyWith(status: 'failed', progress: 0.0));
            }
          } else if (current.status == 'downloading') {
            // App was closed or killed while download was in progress.
            // Check if we have partial downloaded content to resume from.
            final hasPart = partFile.existsSync() && partFile.lengthSync() > 0;
            final hasSegs = segDir.existsSync() && segDir.listSync().isNotEmpty;

            if (hasPart || hasSegs) {
              _items.add(current.copyWith(status: 'paused'));
            } else {
              _items.add(current.copyWith(status: 'failed', progress: 0.0));
            }
          } else {
            _items.add(current);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load downloads: $e');
    }
  }

  Future<void> _saveDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_items.map((i) => i.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('Failed to save downloads: $e');
    }
  }

  bool isDownloaded(String id) {
    return items.any((i) => i.id == id && i.status == 'completed');
  }

  bool isDownloading(String id) {
    return items.any((i) => i.id == id && i.status == 'downloading');
  }

  bool isPaused(String id) {
    return items.any((i) => i.id == id && (i.status == 'paused' || i.status == 'failed'));
  }

  double getProgress(String id) {
    final item = getItem(id);
    return item?.progress ?? 0.0;
  }

  DownloadedItem? getItem(String id) {
    return items.where((i) => i.id == id).firstOrNull;
  }

  DownloadedItem? getItemByPath(String path) {
    return _items.where((i) => i.localFilePath == path).firstOrNull;
  }

  /// Launch external browser resolver for web downloads (same as web flowflix-web/src/lib/download.ts)
  static Future<bool> launchWebDownload({
    required String mediaType,
    required int mediaId,
    int season = 1,
    int episode = 1,
  }) async {
    final urls = [
      mediaType == 'tv'
          ? 'https://moviebox.ph/tv/download?tmdb=$mediaId&s=$season&e=$episode'
          : 'https://moviebox.ph/movies/download?tmdb=$mediaId',
      'https://voidflix.org/watch/$mediaType/$mediaId',
      mediaType == 'tv'
          ? 'https://dl.vidsrc.vip/tv/$mediaId/$season/$episode'
          : 'https://dl.vidsrc.vip/movie/$mediaId',
    ];

    for (final url in urls) {
      final uri = Uri.parse(url);
      try {
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) return true;
        }
      } catch (_) {}
    }
    return false;
  }

/// Retrieves user preferred audio languages from app settings and active profile
  Future<List<String>> _getPreferredAudioLanguages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appAudioPref = prefs.getString('voidflix_preferred_audio_lang');
      final langs = <String>[];
      if (appAudioPref != null &&
          appAudioPref.isNotEmpty &&
          appAudioPref != 'Original Audio' &&
          !appAudioPref.toLowerCase().contains('all languages')) {
        langs.add(appAudioPref);
      }
      final activeId = prefs.getString('voidflix_active_profile');
      if (activeId != null) {
        final audioLangPref = prefs.getString('profile_${activeId}_audio_lang');
        final profilesListStr = prefs.getString('voidflix_profiles_list');
        if (audioLangPref != null && audioLangPref.isNotEmpty) {
          final parts = audioLangPref
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty && p.toLowerCase() != 'original' && !p.toLowerCase().contains('all languages'));
          langs.addAll(parts);
        }
        if (profilesListStr != null && profilesListStr.isNotEmpty) {
          final list = jsonDecode(profilesListStr) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic> && item['id'] == activeId) {
              if (item['preferredAudioLang'] != null) langs.add(item['preferredAudioLang'] as String);
              if (item['preferredLanguages'] is List) {
                langs.addAll((item['preferredLanguages'] as List).map((e) => e.toString()));
              }
              break;
            }
          }
        }
      }
      return langs.toSet().toList();
    } catch (_) {}
    return const [];
  }

  /// Retrieves user preferred subtitle language
  Future<String?> _getPreferredSubtitleLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appSubPref = prefs.getString('voidflix_preferred_sub_lang');
      if (appSubPref != null && appSubPref.isNotEmpty && appSubPref != 'Off / None' && appSubPref != 'None') {
        return appSubPref;
      }
      final activeId = prefs.getString('voidflix_active_profile');
      if (activeId != null) {
        final profilesListStr = prefs.getString('voidflix_profiles_list');
        if (profilesListStr != null && profilesListStr.isNotEmpty) {
          final list = jsonDecode(profilesListStr) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic> && item['id'] == activeId) {
              return item['preferredSubtitleLang'] as String?;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves target download quality height (2160, 1080, 720, 480)
  Future<int> _getPreferredQualityHeight() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getString('voidflix_preferred_quality') ?? prefs.getString('voidflix_download_quality') ?? 'High';
      if (q.contains('4K') || q.contains('2160')) return 2160;
      if (q.contains('1080') || q == 'High' || q.contains('Full HD')) return 1080;
      if (q.contains('720') || q == 'Standard' || q.contains('HD')) return 720;
      if (q.contains('480') || q.contains('Data Saver')) return 480;
    } catch (_) {}
    return 1080;
  }

  /// Calculates language priority score:
  /// - User profile selected language: 100 - index
  /// - English fallback: 50
  /// - Any other language: 10
  int _getLangScore(String? lang, List<String> preferredLangs) {
    if (lang == null || lang.isEmpty) return 0;
    for (int i = 0; i < preferredLangs.length; i++) {
      if (LanguageUtils.matches(lang, preferredLangs[i])) {
        return 100 - i;
      }
    }
    if (LanguageUtils.matches(lang, 'en') || LanguageUtils.matches(lang, 'english')) {
      return 50;
    }
    return 10;
  }

  /// Downloads and caches the thumbnail locally on disk for 100% offline access
  Future<String?> _downloadLocalThumbnail({
    required String id,
    required Directory downloadDir,
    String? stillPath,
    String? backdropPath,
    String? posterPath,
  }) async {
    final chosenPath = stillPath ?? backdropPath ?? posterPath;
    if (chosenPath == null || chosenPath.isEmpty) return null;

    final thumbFile = File('${downloadDir.path}/${id}_thumb.jpg');
    if (thumbFile.existsSync() && thumbFile.lengthSync() > 1000) {
      return thumbFile.path;
    }

    try {
      final url = 'https://image.tmdb.org/t/p/w500$chosenPath';
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 && res.bodyBytes.length > 500) {
        await thumbFile.writeAsBytes(res.bodyBytes, flush: true);
        return thumbFile.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads and caches subtitle files (.vtt / .srt) locally on disk for 100% offline access
  Future<String?> _downloadLocalSubtitle({
    required String id,
    required String mediaType,
    required int mediaId,
    required int season,
    required int episode,
    required Directory downloadDir,
    required List<SubtitleTrack> availableSubs,
    String? preferredSubLang,
  }) async {
    final List<SubtitleTrack> subsToProcess = [...availableSubs];

    // If candidate streams did not have subtitles attached, query Voidflix extract endpoint
    if (subsToProcess.isEmpty) {
      try {
        final uri = Uri.parse(
          'https://voidflix.org/api/public/extract?type=$mediaType&id=$mediaId&s=$season&e=$episode',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic> && data['subs'] is List) {
            for (final s in data['subs']) {
              if (s is Map<String, dynamic> && s['url'] != null) {
                final subUrl = s['url'] as String;
                final resolvedUrl = subUrl.startsWith('http')
                    ? subUrl
                    : 'https://voidflix.org$subUrl';
                subsToProcess.add(SubtitleTrack(
                  label: (s['label'] as String?) ?? 'Sub',
                  language: (s['lang'] as String?) ?? 'en',
                  url: resolvedUrl,
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    // If still empty, attempt Vidlink extraction for rich multi-lingual captions
    if (subsToProcess.isEmpty) {
      try {
        final vidlink = await StreamExtractor.extractVidlink(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
        );
        if (vidlink != null && vidlink.subtitles.isNotEmpty) {
          subsToProcess.addAll(vidlink.subtitles);
        }
      } catch (_) {}
    }

    // If still empty, check shared cached subtitles
    if (subsToProcess.isEmpty) {
      try {
        final shared = await StreamExtractor.getSharedSubtitles(
          mediaType,
          mediaId,
          season,
          episode,
        );
        if (shared.isNotEmpty) {
          subsToProcess.addAll(shared);
        }
      } catch (_) {}
    }

    if (subsToProcess.isEmpty) return null;

    final preferredLangs = <String>[];
    if (preferredSubLang != null && preferredSubLang.isNotEmpty && preferredSubLang != 'Off / None' && preferredSubLang != 'None') {
      preferredLangs.add(preferredSubLang);
    }
    preferredLangs.addAll(await _getPreferredAudioLanguages());
    preferredLangs.add('en');
    preferredLangs.add('English');

    String? primarySubPath;
    final downloadedTracksMeta = <Map<String, String>>[];

    // Sort tracks prioritizing user profile language, then English, then any
    final sortedTracks = [...subsToProcess]..sort((a, b) {
      final aScore = _getLangScore(a.language.isNotEmpty ? a.language : a.label, preferredLangs);
      final bScore = _getLangScore(b.language.isNotEmpty ? b.language : b.label, preferredLangs);
      return bScore.compareTo(aScore);
    });

    final targetTracks = sortedTracks.take(4).toList();

    for (int i = 0; i < targetTracks.length; i++) {
      final track = targetTracks[i];
      final lang = track.language.isNotEmpty
          ? track.language.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          : 'sub$i';
      final file = File('${downloadDir.path}/${id}_sub_$lang.vtt');

      if (file.existsSync() && file.lengthSync() > 50) {
        downloadedTracksMeta.add({
          'label': track.label,
          'language': track.language,
          'path': file.path,
        });
        primarySubPath ??= file.path;
        continue;
      }

      try {
        final res = await http.get(Uri.parse(track.url)).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(res.bodyBytes, flush: true);
          downloadedTracksMeta.add({
            'label': track.label,
            'language': track.language,
            'path': file.path,
          });
          primarySubPath ??= file.path;
        }
      } catch (e) {
        debugPrint('Failed to download subtitle track (${track.label}): $e');
      }
    }

    if (downloadedTracksMeta.isNotEmpty) {
      try {
        final manifestFile = File('${downloadDir.path}/${id}_subs.json');
        await manifestFile.writeAsString(jsonEncode(downloadedTracksMeta), flush: true);
      } catch (_) {}
    }

    return primarySubPath;
  }

  /// Resumes a paused or interrupted download from exactly where it stopped
  Future<void> resumeDownload(String id) async {
    final item = getItem(id);
    if (item == null) return;
    if (isDownloading(id) || isDownloaded(id)) return;

    await startDownload(
      mediaId: item.mediaId,
      title: sanitizeTitle(item.title),
      mediaType: item.mediaType,
      season: item.season,
      episode: item.episode,
      episodeTitle: item.episodeTitle,
      episodeDescription: item.episodeDescription,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      stillPath: item.stillPath,
      runtime: item.runtime,
    );
  }

  /// Initiates high-speed parallel multi-source download with local thumbnail & resumption
  Future<void> startDownload({
    required int mediaId,
    required String title,
    required String mediaType,
    int season = 1,
    int episode = 1,
    String? episodeTitle,
    String? episodeDescription,
    String? posterPath,
    String? backdropPath,
    String? stillPath,
    int runtime = 0,
    String? preferredQuality,
    String? preferredAudio,
    String? preferredSubtitle,
  }) async {
    final cleanTitle = sanitizeTitle(title);
    final id = generateId(mediaType, mediaId, season: season, episode: episode);

    if (isDownloading(id) || isDownloaded(id)) return;

    // 1. Target directory & initial item registration
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!downloadDir.existsSync()) {
      await downloadDir.create(recursive: true);
    }

    final targetPath = '${downloadDir.path}/$id.mp4';
    final partPath = '$targetPath.part';
    final segmentsDirPath = '$targetPath.segments';

    final existingItem = getItem(id);
    final initialProgress = existingItem != null && existingItem.progress > 0.05
        ? existingItem.progress
        : 0.05;

    String? localThumb = existingItem?.localThumbnailPath;
    String? localSub = existingItem?.localSubtitlePath;

    var item = DownloadedItem(
      id: id,
      profileId: _activeProfileId,
      mediaId: mediaId,
      title: cleanTitle,
      mediaType: mediaType,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      episodeDescription: episodeDescription ?? existingItem?.episodeDescription,
      posterPath: posterPath,
      backdropPath: backdropPath,
      stillPath: stillPath ?? existingItem?.stillPath,
      runtime: runtime > 0 ? runtime : (existingItem?.runtime ?? 0),
      localFilePath: targetPath,
      localThumbnailPath: localThumb,
      localSubtitlePath: localSub,
      status: 'downloading',
      progress: initialProgress,
      downloadedAt: DateTime.now(),
    );

    _items.removeWhere((i) => i.id == id);
    _items.insert(0, item);
    notifyListeners();
    await _saveDownloads();

    // Asynchronously fetch thumbnail if missing
    if (localThumb == null || !File(localThumb).existsSync()) {
      _downloadLocalThumbnail(
        id: id,
        downloadDir: downloadDir,
        stillPath: stillPath,
        backdropPath: backdropPath,
        posterPath: posterPath,
      ).then((savedThumbPath) {
        if (savedThumbPath != null) {
          final idx = _items.indexWhere((i) => i.id == id);
          if (idx != -1) {
            _items[idx] = _items[idx].copyWith(localThumbnailPath: savedThumbPath);
            notifyListeners();
            _saveDownloads();
          }
        }
      });
    }

    final client = http.Client();
    _activeClients[id] = client;

    _updateSystemNotification(
      id: id.hashCode.abs(),
      title: cleanTitle,
      progress: (initialProgress * 100).toInt(),
      isDone: false,
    );

    try {
      // 2. Build prioritized candidate download stream list from the BEST servers
      final candidates = <_DownloadCandidate>[];
      final availableSubs = <SubtitleTrack>[];

      final preferredAudioLangs = preferredAudio != null && preferredAudio.isNotEmpty
          ? [preferredAudio, ...await _getPreferredAudioLanguages()]
          : await _getPreferredAudioLanguages();

      final targetHeight = preferredQuality != null
          ? (preferredQuality.contains('4K') || preferredQuality.contains('2160')
              ? 2160
              : preferredQuality.contains('1080')
                  ? 1080
                  : preferredQuality.contains('720')
                      ? 720
                      : 480)
          : await _getPreferredQualityHeight();

      // Priority 1: NetMirror (Direct High-Speed MP4 CDN with Multi-Quality 1080p/720p/480p, Range 206 & Preferred Dub)
      try {
        final netMirrorStreams = await StreamExtractor.extractNetMirror(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
          preferredAudioLang: preferredAudioLangs.isNotEmpty ? preferredAudioLangs.first : null,
        ).timeout(const Duration(seconds: 4));

        for (final s in netMirrorStreams) {
          if (s.subtitles.isNotEmpty) availableSubs.addAll(s.subtitles);
          for (final q in s.qualities) {
            candidates.add(_DownloadCandidate(
              url: q.url,
              headers: s.headers,
              isHls: false, // Direct progressive MP4 stream with byte-range 206!
              qualityLabel: q.label,
              serverName: 'StellarHD',
              audioLanguage: s.language,
              height: q.height > 0 ? q.height : 1080,
            ));
          }
          if (s.qualities.isEmpty && s.url.isNotEmpty) {
            candidates.add(_DownloadCandidate(
              url: s.url,
              headers: s.headers,
              isHls: false,
              qualityLabel: s.qualityLabel ?? '1080p',
              serverName: 'StellarHD',
              audioLanguage: s.language,
              height: 1080,
            ));
          }
        }
      } catch (e) {
        debugPrint('Download: NetMirror candidate error: $e');
      }

      // Priority 2: Meow (Telegram VPS 25k Channel Database with multi-audio & multi-quality direct MP4)
      try {
        final telegramStreams = await StreamExtractor.extractTelegram(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
        ).timeout(const Duration(seconds: 4));

        for (final s in telegramStreams) {
          if (s.subtitles.isNotEmpty) availableSubs.addAll(s.subtitles);
          for (final q in s.qualities) {
            candidates.add(_DownloadCandidate(
              url: q.url,
              headers: s.headers,
              isHls: false, // Direct progressive MP4 stream with byte-range 206!
              qualityLabel: q.label,
              serverName: 'Meow',
              audioLanguage: s.language,
              height: q.height > 0 ? q.height : 1080,
            ));
          }
          if (s.qualities.isEmpty && s.url.isNotEmpty) {
            candidates.add(_DownloadCandidate(
              url: s.url,
              headers: s.headers,
              isHls: s.type == 'hls' || s.url.contains('.m3u8'),
              qualityLabel: s.qualityLabel ?? '1080p',
              serverName: 'Meow',
              audioLanguage: s.language,
              height: 1080,
            ));
          }
        }
      } catch (e) {
        debugPrint('Download: Meow Telegram candidate error: $e');
      }

      // Priority 2: NebulaHD & Cine4K (Direct High-Speed CDN with Full Muxed Audio)
      try {
        final cinejoyStreams = await StreamExtractor.extractCinejoy(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
          title: cleanTitle,
        ).timeout(const Duration(seconds: 4));

        for (final s in cinejoyStreams) {
          if (s.subtitles.isNotEmpty) availableSubs.addAll(s.subtitles);
          for (final q in s.qualities) {
            candidates.add(_DownloadCandidate(
              url: q.url,
              headers: s.headers,
              isHls: true,
              qualityLabel: q.label,
              serverName: s.sourceName,
              audioLanguage: s.language,
              height: q.height > 0 ? q.height : 1080,
            ));
          }
          if (s.qualities.isEmpty && s.url.isNotEmpty) {
            candidates.add(_DownloadCandidate(
              url: s.url,
              headers: s.headers,
              isHls: true,
              qualityLabel: s.qualityLabel ?? '1080p Full HD',
              serverName: s.sourceName,
              audioLanguage: s.language,
              height: 1080,
            ));
          }
        }
      } catch (e) {
        debugPrint('Download: Cinejoy / NebulaHD candidate error: $e');
      }

      // Priority 3: Direct File Resolver (Stremio direct MP4 addon)
      try {
        final directFile = await StreamExtractor.extractDirectFileUrl(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
        ).timeout(const Duration(seconds: 4));
        if (directFile != null && directFile.isNotEmpty) {
          candidates.add(_DownloadCandidate(
            url: directFile,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            isHls: directFile.contains('.m3u8'),
            qualityLabel: '1080p',
            serverName: 'DirectFile',
            audioLanguage: 'Original',
            height: 1080,
          ));
        }
      } catch (_) {}

      // Priority 4: Vidlink & Vidrock
      try {
        final vidlinkStream = await StreamExtractor.extractVidlink(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
        ).timeout(const Duration(seconds: 4));
        if (vidlinkStream != null) {
          if (vidlinkStream.subtitles.isNotEmpty) availableSubs.addAll(vidlinkStream.subtitles);
          for (final q in vidlinkStream.qualities) {
            candidates.add(_DownloadCandidate(
              url: q.url,
              headers: vidlinkStream.headers,
              isHls: q.url.contains('.m3u8') || vidlinkStream.type == 'hls',
              qualityLabel: q.label,
              serverName: 'Vidlink',
              audioLanguage: vidlinkStream.language,
              height: q.height > 0 ? q.height : 1080,
            ));
          }
        }
      } catch (_) {}

      // Priority 5: Voidflix backend extraction
      try {
        final voidflixStream = await StreamExtractor.extractVoidflixBackend(
          type: mediaType,
          tmdbId: mediaId,
          season: season,
          episode: episode,
        ).timeout(const Duration(seconds: 4));
        if (voidflixStream != null) {
          if (voidflixStream.subtitles.isNotEmpty) availableSubs.addAll(voidflixStream.subtitles);
          for (final q in voidflixStream.qualities) {
            final proxiedDownloadUrl = q.url.contains('?')
                ? '${q.url}&download=${Uri.encodeComponent('$title.mp4')}'
                : '${q.url}?download=${Uri.encodeComponent('$title.mp4')}';
            candidates.add(_DownloadCandidate(
              url: proxiedDownloadUrl,
              headers: voidflixStream.headers,
              isHls: q.url.contains('.m3u8') || voidflixStream.type == 'hls',
              qualityLabel: q.label,
              serverName: 'Voidflix',
              audioLanguage: voidflixStream.language,
              height: q.height > 0 ? q.height : 1080,
            ));
          }
        }
      } catch (_) {}

      if (candidates.isEmpty) {
        throw Exception('No stream candidates available for offline download.');
      }

      // Score and sort candidates based on user preferences and server quality
      int scoreCandidate(_DownloadCandidate c) {
        int score = 0;

        // 1. Audio Language Match (Weight: 3000 points)
        if (preferredAudioLangs.isNotEmpty) {
          final topPref = preferredAudioLangs.first;
          if (LanguageUtils.matches(c.audioLanguage, topPref) ||
              LanguageUtils.matches(c.qualityLabel, topPref)) {
            score += 3000;
          } else {
            for (int i = 1; i < preferredAudioLangs.length; i++) {
              if (LanguageUtils.matches(c.audioLanguage, preferredAudioLangs[i]) ||
                  LanguageUtils.matches(c.qualityLabel, preferredAudioLangs[i])) {
                score += (2500 - (i * 200));
                break;
              }
            }
          }
        }
        if (LanguageUtils.matches(c.audioLanguage, 'en') ||
            LanguageUtils.matches(c.audioLanguage, 'english') ||
            c.qualityLabel.toLowerCase().contains('english')) {
          score += 400; // English fallback bonus
        }

        // 2. Video Quality Match (Weight: 2000 points)
        if (c.height == targetHeight) {
          score += 2000;
        } else if (c.height > 0) {
          final diff = (c.height - targetHeight).abs();
          score += (1500 - diff).clamp(100, 1500);
        }

        // 3. Best Server Weight
        if (c.serverName == 'NetMirror') {
          score += 3500; // Slot #1: NetMirror first priority with preferred dub & qualities
        } else if (c.serverName == 'Meow') {
          score += 1200; // Slot #2: Direct MP4 from 25k Telegram channel
        } else if (c.serverName.contains('NebulaHD')) {
          score += 900; // Slot #2: Full muxed AAC stereo audio HLS
        } else if (c.serverName.contains('Cine4K')) {
          score += 700;
        } else if (c.serverName == 'Vidlink') {
          score += 600;
        } else if (!c.isHls) {
          score += 500; // Direct MP4 bonus over HLS segments
        } else {
          score += 300;
        }

        return score;
      }

      final scoredCandidates = candidates
          .map((c) => c.copyWith(score: scoreCandidate(c)))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      // Download and cache offline subtitles in background respecting user preference
      final preferredSubLang = preferredSubtitle ?? await _getPreferredSubtitleLanguage();
      _downloadLocalSubtitle(
        id: id,
        mediaType: mediaType,
        mediaId: mediaId,
        season: season,
        episode: episode,
        downloadDir: downloadDir,
        availableSubs: availableSubs,
        preferredSubLang: preferredSubLang,
      ).then((savedSubPath) {
        if (savedSubPath != null) {
          final idx = _items.indexWhere((i) => i.id == id);
          if (idx != -1) {
            _items[idx] = _items[idx].copyWith(localSubtitlePath: savedSubPath);
            notifyListeners();
            _saveDownloads();
          }
        }
      });

      // 3. Attempt download across candidates with resumption
      bool downloadSuccess = false;
      String chosenQuality = 'HD';

      for (final candidate in scoredCandidates) {
        if (!_activeClients.containsKey(id)) {
          // Cancelled by user
          return;
        }

        debugPrint('Attempting high-efficiency download from: ${candidate.url} (HLS: ${candidate.isHls})');

        if (candidate.isHls) {
          downloadSuccess = await _downloadHlsStream(
            m3u8Url: candidate.url,
            headers: candidate.headers,
            targetPath: targetPath,
            partPath: partPath,
            segmentsDirPath: segmentsDirPath,
            downloadId: id,
            title: cleanTitle,
            targetHeight: targetHeight,
            onProgress: (p, bytes) {
              _updateProgress(id, p, bytes);
            },
          );
        } else {
          downloadSuccess = await _downloadProgressiveStream(
            downloadUrl: candidate.url,
            headers: candidate.headers,
            targetPath: targetPath,
            partPath: partPath,
            downloadId: id,
            title: cleanTitle,
            onProgress: (p, bytes) {
              _updateProgress(id, p, bytes);
            },
          );
        }

        if (downloadSuccess) {
          chosenQuality = candidate.qualityLabel;
          if (candidate.audioLanguage.isNotEmpty &&
              candidate.audioLanguage != 'Original' &&
              !chosenQuality.toLowerCase().contains(candidate.audioLanguage.toLowerCase())) {
            chosenQuality = '$chosenQuality • ${candidate.audioLanguage}';
          }
          break;
        }
      }

      if (!downloadSuccess) {
        throw Exception('All stream providers failed or rate-limited.');
      }

      // 4. Mark download as completed
      final finalFile = File(targetPath);
      final finalSizeBytes = await finalFile.length();

      // Ensure we preserve any subtitle downloaded during background task or scan disk
      final existingItem = getItem(id);
      String? finalSubPath = existingItem?.localSubtitlePath ?? item.localSubtitlePath;
      if (finalSubPath == null || !File(finalSubPath).existsSync()) {
        final manifestFile = File('${downloadDir.path}/${id}_subs.json');
        if (manifestFile.existsSync()) {
          try {
            final subsList = jsonDecode(manifestFile.readAsStringSync()) as List;
            if (subsList.isNotEmpty && subsList.first['path'] != null) {
              final candidate = subsList.first['path'] as String;
              if (File(candidate).existsSync()) {
                finalSubPath = candidate;
              }
            }
          } catch (_) {}
        }
      }
      if (finalSubPath == null || !File(finalSubPath).existsSync()) {
        try {
          final matching = downloadDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('${id}_sub_') && (f.path.endsWith('.vtt') || f.path.endsWith('.srt')))
              .toList();
          if (matching.isNotEmpty) {
            finalSubPath = matching.first.path;
          }
        } catch (_) {}
      }
      if (finalSubPath == null || !File(finalSubPath).existsSync()) {
        final subFile = File('${downloadDir.path}/${id}_sub_en.vtt');
        if (subFile.existsSync()) {
          finalSubPath = subFile.path;
        }
      }

      item = item.copyWith(
        status: 'completed',
        progress: 1.0,
        fileSizeBytes: finalSizeBytes,
        quality: chosenQuality,
        localSubtitlePath: finalSubPath,
      );

      final idx = _items.indexWhere((i) => i.id == id);
      if (idx != -1) {
        _items[idx] = item;
        notifyListeners();
      }
      await _saveDownloads();
      _activeClients.remove(id);

      _updateSystemNotification(
        id: id.hashCode.abs(),
        title: title,
        progress: 100,
        isDone: true,
      );
    } catch (e) {
      debugPrint('Download error ($id): $e');
      _activeClients.remove(id);
      _cancelSystemNotification(id.hashCode.abs());

      final partFile = File(partPath);
      final segDir = Directory(segmentsDirPath);
      final hasPartial = (partFile.existsSync() && partFile.lengthSync() > 0) ||
          (segDir.existsSync() && segDir.listSync().isNotEmpty);

      final idx = _items.indexWhere((i) => i.id == id);
      if (idx != -1) {
        _items[idx] = item.copyWith(
          status: hasPartial ? 'paused' : 'failed',
          progress: hasPartial ? item.progress : 0.0,
        );
        notifyListeners();
      }
      await _saveDownloads();
    }
  }

  void _updateProgress(String id, double p, int bytes) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      final current = _items[idx];
      if ((p - current.progress).abs() > 0.015 || p >= 0.99) {
        _items[idx] = current.copyWith(
          progress: p,
          fileSizeBytes: bytes,
        );
        notifyListeners();
      }
    }
  }

  /// High-speed parallel HLS MPEG-TS segment downloader with chunk concurrency & exact resumption
  Future<bool> _downloadHlsStream({
    required String m3u8Url,
    required Map<String, String> headers,
    required String targetPath,
    required String partPath,
    required String segmentsDirPath,
    required String downloadId,
    required String title,
    int targetHeight = 1080,
    required Function(double progress, int bytes) onProgress,
  }) async {
    final client = _activeClients[downloadId];
    if (client == null) return false;

    try {
      final reqHeaders = Map<String, String>.from(headers);
      reqHeaders['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

      final res = await client
          .get(Uri.parse(m3u8Url), headers: reqHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return false;

      var playlistContent = res.body;
      var playlistBaseUri = Uri.parse(m3u8Url);

      // Handle Master Playlist (pick variant matching user's preferred quality)
      if (playlistContent.contains('#EXT-X-STREAM-INF')) {
        final lines = LineSplitter.split(playlistContent).toList();
        final variants = <_HlsVariantCandidate>[];
        String? currentInfo;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            currentInfo = line;
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            final variantUrl = playlistBaseUri.resolve(line).toString();
            final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(currentInfo ?? '');
            final h = resMatch != null
                ? int.tryParse(resMatch.group(1)!) ?? 1080
                : (line.contains('4k')
                    ? 2160
                    : line.contains('1080')
                        ? 1080
                        : line.contains('720')
                            ? 720
                            : 480);
            variants.add(_HlsVariantCandidate(url: variantUrl, height: h));
            currentInfo = null;
          }
        }

        if (variants.isNotEmpty) {
          variants.sort((a, b) {
            final diffA = (a.height - targetHeight).abs();
            final diffB = (b.height - targetHeight).abs();
            return diffA.compareTo(diffB);
          });
          final bestVariantUrl = variants.first.url;
          final subRes = await client
              .get(Uri.parse(bestVariantUrl), headers: reqHeaders)
              .timeout(const Duration(seconds: 12));
          if (subRes.statusCode == 200) {
            playlistContent = subRes.body;
            playlistBaseUri = Uri.parse(bestVariantUrl);
          }
        }
      }

      // Audio health check: Reject if audio CDN is 502/broken
      final audioMatches = RegExp(r'#EXT-X-MEDIA:TYPE=AUDIO.*?URI="([^"]+)"').allMatches(playlistContent);
      if (audioMatches.isNotEmpty) {
        final firstAudioUri = audioMatches.first.group(1);
        if (firstAudioUri != null) {
          final resolvedAudio = playlistBaseUri.resolve(firstAudioUri);
          try {
            final aCheck = await client.get(resolvedAudio, headers: reqHeaders).timeout(const Duration(seconds: 2));
            if (aCheck.statusCode >= 400) {
              debugPrint('HLS audio CDN rejected with HTTP ${aCheck.statusCode} - skipping broken audio server');
              return false;
            }
          } catch (_) {
            return false;
          }
        }
      }

      // Extract all segment URIs
      final lines = LineSplitter.split(playlistContent).toList();
      final segmentUris = <Uri>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          segmentUris.add(playlistBaseUri.resolve(trimmed));
        }
      }

      if (segmentUris.isEmpty) return false;

      final segDir = Directory(segmentsDirPath);
      if (!segDir.existsSync()) {
        await segDir.create(recursive: true);
      }

      // Check for fragmented MP4 initialization segment (fMP4 / NebulaHD)
      final mapMatch = RegExp(r'#EXT-X-MAP:URI="([^"]+)"').firstMatch(playlistContent);
      File? initFile;
      if (mapMatch != null) {
        final initUri = playlistBaseUri.resolve(mapMatch.group(1)!);
        final initF = File('${segDir.path}/init.mp4');
        if (!initF.existsSync() || initF.lengthSync() == 0) {
          try {
            final initRes = await client.get(initUri, headers: reqHeaders).timeout(const Duration(seconds: 15));
            if (initRes.statusCode == 200 && initRes.bodyBytes.isNotEmpty) {
              await initF.writeAsBytes(initRes.bodyBytes, flush: true);
              initFile = initF;
            }
          } catch (e) {
            debugPrint('Failed to download fMP4 init segment: $e');
          }
        } else {
          initFile = initF;
        }
      }

      // Check existing downloaded segments to resume exactly from where left off
      int alreadyDownloaded = 0;
      int totalDownloadedBytes = 0;
      final missingIndices = <int>[];

      for (int i = 0; i < segmentUris.length; i++) {
        final segFileName = 'seg_${i.toString().padLeft(6, '0')}.ts';
        final segFile = File('${segDir.path}/$segFileName');
        if (segFile.existsSync() && segFile.lengthSync() > 0) {
          alreadyDownloaded++;
          totalDownloadedBytes += segFile.lengthSync();
        } else {
          missingIndices.add(i);
        }
      }

      if (alreadyDownloaded > 0) {
        final initialP = (alreadyDownloaded / segmentUris.length).clamp(0.05, 0.99);
        onProgress(initialP, totalDownloadedBytes);
      }

      // Multi-connection Parallel Worker Pool (Concurrency = 6 for maximum throughput)
      const concurrency = 6;
      int queueCursor = 0;
      int completedSegments = alreadyDownloaded;
      int notifTick = 0;
      bool hasAborted = false;

      Future<void> runWorker() async {
        while (!hasAborted) {
          if (!_activeClients.containsKey(downloadId)) {
            hasAborted = true;
            return;
          }

          int idx;
          // Thread-safe index retrieval
          if (queueCursor >= missingIndices.length) {
            break;
          }
          idx = missingIndices[queueCursor++];

          final segUri = segmentUris[idx];
          final segFileName = 'seg_${idx.toString().padLeft(6, '0')}.ts';
          final segFile = File('${segDir.path}/$segFileName');

          bool segSuccess = false;
          for (int attempt = 0; attempt < 5; attempt++) {
            if (!_activeClients.containsKey(downloadId)) {
              hasAborted = true;
              return;
            }
            try {
              final segRes = await client
                  .get(segUri, headers: reqHeaders)
                  .timeout(const Duration(seconds: 25));
              if (segRes.statusCode == 200 && segRes.bodyBytes.isNotEmpty) {
                await segFile.writeAsBytes(segRes.bodyBytes, flush: true);
                totalDownloadedBytes += segRes.bodyBytes.length;
                completedSegments++;
                segSuccess = true;
                break;
              }
            } catch (_) {
              if (attempt < 4) {
                await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
              }
            }
          }

          if (!segSuccess) {
            // Failed segment after 5 attempts
            hasAborted = true;
            return;
          }

          final p = (completedSegments / segmentUris.length).clamp(0.05, 0.99);
          onProgress(p, totalDownloadedBytes);

          if (++notifTick % 12 == 0) {
            _updateSystemNotification(
              id: downloadId.hashCode.abs(),
              title: title,
              progress: (p * 100).toInt(),
            );
          }
        }
      }

      final workerCount = missingIndices.length < concurrency ? missingIndices.length : concurrency;
      if (workerCount > 0) {
        await Future.wait(List.generate(workerCount, (_) => runWorker()));
      }

      if (!_activeClients.containsKey(downloadId) || hasAborted) {
        return false;
      }

      // Verify all segments exist
      for (int i = 0; i < segmentUris.length; i++) {
        final segFileName = 'seg_${i.toString().padLeft(6, '0')}.ts';
        final segFile = File('${segDir.path}/$segFileName');
        if (!segFile.existsSync() || segFile.lengthSync() == 0) {
          return false;
        }
      }

      // High-efficiency stream piping into .part file without heap memory spikes
      final partFile = File(partPath);
      final sink = partFile.openWrite(mode: FileMode.write);

      // Prepend fMP4 init segment if present (ensures valid, playable MP4 with audio)
      if (initFile != null && initFile.existsSync()) {
        await sink.addStream(initFile.openRead());
      }

      for (int i = 0; i < segmentUris.length; i++) {
        final segFileName = 'seg_${i.toString().padLeft(6, '0')}.ts';
        final segFile = File('${segDir.path}/$segFileName');
        if (segFile.existsSync()) {
          await sink.addStream(segFile.openRead());
        }
      }

      await sink.flush();
      await sink.close();

      final partLen = await partFile.length();
      if (partLen > 100000) {
        final targetFile = File(targetPath);
        try {
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          await partFile.rename(targetPath);
        } catch (_) {
          // Windows filesystem lock fallback: copy & delete
          await partFile.copy(targetPath);
          try {
            partFile.deleteSync();
          } catch (_) {}
        }

        // Clean up temporary segments folder
        try {
          await segDir.delete(recursive: true);
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('HLS parallel download error: $e');
      return false;
    }
  }

  /// High-speed progressive MP4 file downloader with HTTP Range resumption and stream buffers
  Future<bool> _downloadProgressiveStream({
    required String downloadUrl,
    required Map<String, String> headers,
    required String targetPath,
    required String partPath,
    required String downloadId,
    required String title,
    required Function(double progress, int bytes) onProgress,
  }) async {
    final client = _activeClients[downloadId];
    if (client == null) return false;

    try {
      final partFile = File(partPath);
      int existingBytes = 0;
      if (partFile.existsSync()) {
        existingBytes = partFile.lengthSync();
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers.addAll(headers);
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      request.headers['Accept'] = '*/*';
      request.headers['Accept-Encoding'] = 'identity';
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }
      request.followRedirects = true;
      request.maxRedirects = 10;

      final response = await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 206) {
        return false;
      }

      final isResume = response.statusCode == 206 && existingBytes > 0;
      final contentLength = response.contentLength ?? 0;
      final totalExpectedBytes = isResume ? (existingBytes + contentLength) : contentLength;

      final sink = partFile.openWrite(
        mode: isResume ? FileMode.append : FileMode.write,
      );

      int receivedBytes = isResume ? existingBytes : 0;
      int notifTick = 0;

      await for (final chunk in response.stream) {
        if (!_activeClients.containsKey(downloadId)) {
          await sink.flush();
          await sink.close();
          return false;
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalExpectedBytes > 0) {
          final p = (receivedBytes / totalExpectedBytes).clamp(0.05, 0.99);
          onProgress(p, receivedBytes);

          if (++notifTick % 25 == 0) {
            _updateSystemNotification(
              id: downloadId.hashCode.abs(),
              title: title,
              progress: (p * 100).toInt(),
            );
          }
        } else {
          onProgress(0.5, receivedBytes);
        }
      }

      await sink.flush();
      await sink.close();

      final downloadedLength = await partFile.length();
      if (downloadedLength > 100000) {
        final targetFile = File(targetPath);
        try {
          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          await partFile.rename(targetPath);
        } catch (_) {
          // Windows filesystem lock fallback: copy & delete
          await partFile.copy(targetPath);
          try {
            partFile.deleteSync();
          } catch (_) {}
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Progressive download error: $e');
      return false;
    }
  }

  void pauseDownload(String id) {
    final client = _activeClients.remove(id);
    client?.close();

    _cancelSystemNotification(id.hashCode.abs());

    final idx = _items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(status: 'paused');
      notifyListeners();
      _saveDownloads();
    }
  }

  void cancelDownload(String id) {
    final client = _activeClients.remove(id);
    client?.close();

    _cancelSystemNotification(id.hashCode.abs());

    final item = getItem(id);
    if (item != null) {
      final file = File(item.localFilePath);
      final partFile = File('${item.localFilePath}.part');
      final segDir = Directory('${item.localFilePath}.segments');
      final thumbFile = item.localThumbnailPath != null ? File(item.localThumbnailPath!) : null;

      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      if (segDir.existsSync()) {
        try {
          segDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      if (thumbFile != null && thumbFile.existsSync()) {
        try {
          thumbFile.deleteSync();
        } catch (_) {}
      }

      _items.removeWhere((i) => i.id == id);
      notifyListeners();
      _saveDownloads();
    }
  }

  Future<void> deleteDownload(String id) async {
    cancelDownload(id);
    final item = getItem(id);
    if (item != null) {
      final file = File(item.localFilePath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      final thumbFile = item.localThumbnailPath != null ? File(item.localThumbnailPath!) : null;
      if (thumbFile != null && thumbFile.existsSync()) {
        try {
          await thumbFile.delete();
        } catch (_) {}
      }
      _items.removeWhere((i) => i.id == id);
      notifyListeners();
      await _saveDownloads();
    }
  }
}
