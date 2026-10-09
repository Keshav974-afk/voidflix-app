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
import '../models/downloaded_item.dart';

class _DownloadCandidate {
  final String url;
  final Map<String, String> headers;
  final bool isHls;
  final String qualityLabel;

  const _DownloadCandidate({
    required this.url,
    required this.headers,
    required this.isHls,
    required this.qualityLabel,
  });
}

class DownloadProvider extends ChangeNotifier {
  static const String _storageKey = 'voidflix_downloads_data';
  static const _notifChannel = MethodChannel('org.voidflix/notifications');

  final List<DownloadedItem> _items = [];
  final Map<String, http.Client> _activeClients = {};

  List<DownloadedItem> get items => List.unmodifiable(_items);

  List<DownloadedItem> get completedItems =>
      _items.where((i) => i.status == 'completed').toList();

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
          final file = File(d.localFilePath);
          final partFile = File('${d.localFilePath}.part');
          final segDir = Directory('${d.localFilePath}.segments');

          // Verify completed items actually exist and are non-empty (> 100KB)
          if (d.status == 'completed') {
            if (file.existsSync() && file.lengthSync() > 100000) {
              _items.add(d);
            } else {
              // File was missing or corrupted while app was closed
              if (file.existsSync()) {
                try {
                  file.deleteSync();
                } catch (_) {}
              }
              _items.add(d.copyWith(status: 'failed', progress: 0.0));
            }
          } else if (d.status == 'downloading') {
            // App was closed or killed while download was in progress.
            // Check if we have partial downloaded content to resume from.
            final hasPart = partFile.existsSync() && partFile.lengthSync() > 0;
            final hasSegs = segDir.existsSync() && segDir.listSync().isNotEmpty;

            if (hasPart || hasSegs) {
              _items.add(d.copyWith(status: 'paused'));
            } else {
              _items.add(d.copyWith(status: 'failed', progress: 0.0));
            }
          } else {
            _items.add(d);
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
    return _items.any((i) => i.id == id && i.status == 'completed');
  }

  bool isDownloading(String id) {
    return _items.any((i) => i.id == id && i.status == 'downloading');
  }

  bool isPaused(String id) {
    return _items.any((i) => i.id == id && (i.status == 'paused' || i.status == 'failed'));
  }

  double getProgress(String id) {
    final item = getItem(id);
    return item?.progress ?? 0.0;
  }

  DownloadedItem? getItem(String id) {
    return _items.where((i) => i.id == id).firstOrNull;
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

  /// Resumes a paused or interrupted download from where it stopped
  Future<void> resumeDownload(String id) async {
    final item = getItem(id);
    if (item == null) return;
    if (isDownloading(id) || isDownloaded(id)) return;

    await startDownload(
      mediaId: item.mediaId,
      title: item.title,
      mediaType: item.mediaType,
      season: item.season,
      episode: item.episode,
      episodeTitle: item.episodeTitle,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
    );
  }

  /// Initiates robust multi-source extraction and starts streaming download directly to app storage
  Future<void> startDownload({
    required int mediaId,
    required String title,
    required String mediaType,
    int season = 1,
    int episode = 1,
    String? episodeTitle,
    String? posterPath,
    String? backdropPath,
  }) async {
    final id = generateId(mediaType, mediaId, season: season, episode: episode);

    if (isDownloading(id) || isDownloaded(id)) return;

    // 1. Create target directory and item in downloading state
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

    var item = DownloadedItem(
      id: id,
      mediaId: mediaId,
      title: title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      posterPath: posterPath,
      backdropPath: backdropPath,
      localFilePath: targetPath,
      status: 'downloading',
      progress: initialProgress,
      downloadedAt: DateTime.now(),
    );

    _items.removeWhere((i) => i.id == id);
    _items.insert(0, item);
    notifyListeners();
    await _saveDownloads();

    final client = http.Client();
    _activeClients[id] = client;

    _updateSystemNotification(
      id: id.hashCode.abs(),
      title: title,
      progress: (initialProgress * 100).toInt(),
      isDone: false,
    );

    try {
      // 2. Build prioritized candidate download stream list
      final candidates = <_DownloadCandidate>[];

      // A. Direct file resolver (Stremio addon / direct MP4)
      final directFile = await StreamExtractor.extractDirectFileUrl(
        type: mediaType,
        tmdbId: mediaId,
        season: season,
        episode: episode,
      );
      if (directFile != null && directFile.isNotEmpty) {
        candidates.add(_DownloadCandidate(
          url: directFile,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          isHls: directFile.contains('.m3u8'),
          qualityLabel: '1080p',
        ));
      }

      // B. Voidflix backend extraction (matches web proxy)
      final voidflixStream = await StreamExtractor.extractVoidflixBackend(
        type: mediaType,
        tmdbId: mediaId,
        season: season,
        episode: episode,
      );
      if (voidflixStream != null) {
        for (final q in voidflixStream.qualities) {
          final proxiedDownloadUrl = q.url.contains('?')
              ? '${q.url}&download=${Uri.encodeComponent('$title.mp4')}'
              : '${q.url}?download=${Uri.encodeComponent('$title.mp4')}';
          candidates.add(_DownloadCandidate(
            url: proxiedDownloadUrl,
            headers: voidflixStream.headers,
            isHls: q.url.contains('.m3u8') || voidflixStream.type == 'hls',
            qualityLabel: q.label,
          ));
        }
        candidates.add(_DownloadCandidate(
          url: voidflixStream.url,
          headers: voidflixStream.headers,
          isHls: voidflixStream.type == 'hls' || voidflixStream.url.contains('.m3u8'),
          qualityLabel: voidflixStream.qualityLabel ?? 'HD',
        ));
      }

      // C. General stream extraction (Vidlink / Vidrock)
      final generalStreams = await StreamExtractor.extractAll(
        type: mediaType,
        tmdbId: mediaId,
        season: season,
        episode: episode,
      );
      for (final s in generalStreams) {
        for (final q in s.qualities) {
          candidates.add(_DownloadCandidate(
            url: q.url,
            headers: s.headers,
            isHls: q.url.contains('.m3u8') || s.type == 'hls',
            qualityLabel: q.label,
          ));
        }
        candidates.add(_DownloadCandidate(
          url: s.url,
          headers: s.headers,
          isHls: s.type == 'hls' || s.url.contains('.m3u8'),
          qualityLabel: s.qualityLabel ?? 'Auto',
        ));
      }

      if (candidates.isEmpty) {
        throw Exception('No stream candidates available for offline download.');
      }

      // 3. Attempt download across candidates until one succeeds
      bool downloadSuccess = false;
      String chosenQuality = 'HD';

      for (final candidate in candidates) {
        if (!_activeClients.containsKey(id)) {
          // Download was cancelled by user
          return;
        }

        debugPrint('Attempting download from: ${candidate.url} (HLS: ${candidate.isHls})');

        if (candidate.isHls) {
          downloadSuccess = await _downloadHlsStream(
            m3u8Url: candidate.url,
            headers: candidate.headers,
            targetPath: targetPath,
            partPath: partPath,
            segmentsDirPath: segmentsDirPath,
            downloadId: id,
            title: title,
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
            title: title,
            onProgress: (p, bytes) {
              _updateProgress(id, p, bytes);
            },
          );
        }

        if (downloadSuccess) {
          chosenQuality = candidate.qualityLabel;
          break;
        }
      }

      if (!downloadSuccess) {
        throw Exception('All stream providers failed to download or rate-limited.');
      }

      // 4. Mark download as completed
      final finalFile = File(targetPath);
      final finalSizeBytes = await finalFile.length();

      item = item.copyWith(
        status: 'completed',
        progress: 1.0,
        fileSizeBytes: finalSizeBytes,
        quality: chosenQuality,
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
      if ((p - current.progress).abs() > 0.02 || p >= 0.99) {
        _items[idx] = current.copyWith(
          progress: p,
          fileSizeBytes: bytes,
        );
        notifyListeners();
      }
    }
  }

  /// Downloads and concatenates HLS MPEG-TS segments with resumption support
  Future<bool> _downloadHlsStream({
    required String m3u8Url,
    required Map<String, String> headers,
    required String targetPath,
    required String partPath,
    required String segmentsDirPath,
    required String downloadId,
    required String title,
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
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;

      var playlistContent = res.body;
      var playlistBaseUri = Uri.parse(m3u8Url);

      // Handle Master Playlist (pick best variant)
      if (playlistContent.contains('#EXT-X-STREAM-INF')) {
        final lines = LineSplitter.split(playlistContent).toList();
        String? bestVariantUrl;
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF')) {
            for (int j = i + 1; j < lines.length; j++) {
              final nextLine = lines[j].trim();
              if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
                bestVariantUrl = playlistBaseUri.resolve(nextLine).toString();
                break;
              }
            }
            if (bestVariantUrl != null) break;
          }
        }

        if (bestVariantUrl != null) {
          final subRes = await client
              .get(Uri.parse(bestVariantUrl), headers: reqHeaders)
              .timeout(const Duration(seconds: 10));
          if (subRes.statusCode == 200) {
            playlistContent = subRes.body;
            playlistBaseUri = Uri.parse(bestVariantUrl);
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

      int totalDownloadedBytes = 0;
      int notifTick = 0;

      for (int i = 0; i < segmentUris.length; i++) {
        if (!_activeClients.containsKey(downloadId)) {
          return false;
        }

        final segFileName = 'seg_${i.toString().padLeft(6, '0')}.ts';
        final segFile = File('${segDir.path}/$segFileName');

        if (segFile.existsSync() && segFile.lengthSync() > 0) {
          totalDownloadedBytes += segFile.lengthSync();
          final p = ((i + 1) / segmentUris.length).clamp(0.05, 0.99);
          onProgress(p, totalDownloadedBytes);
          continue;
        }

        final segUri = segmentUris[i];
        try {
          final segRes = await client
              .get(segUri, headers: reqHeaders)
              .timeout(const Duration(seconds: 15));
          if (segRes.statusCode == 200) {
            await segFile.writeAsBytes(segRes.bodyBytes, flush: true);
            totalDownloadedBytes += segRes.bodyBytes.length;

            final p = ((i + 1) / segmentUris.length).clamp(0.05, 0.99);
            onProgress(p, totalDownloadedBytes);

            if (++notifTick % 10 == 0) {
              _updateSystemNotification(
                id: downloadId.hashCode.abs(),
                title: title,
                progress: (p * 100).toInt(),
              );
            }
          }
        } catch (_) {}
      }

      // Assemble all segments into part file
      final partFile = File(partPath);
      final sink = partFile.openWrite(mode: FileMode.write);

      for (int i = 0; i < segmentUris.length; i++) {
        final segFileName = 'seg_${i.toString().padLeft(6, '0')}.ts';
        final segFile = File('${segDir.path}/$segFileName');
        if (segFile.existsSync()) {
          sink.add(await segFile.readAsBytes());
        }
      }

      await sink.flush();
      await sink.close();

      final partLen = await partFile.length();
      if (partLen > 100000) {
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        await partFile.rename(targetPath);

        // Clean up temporary segments folder
        try {
          await segDir.delete(recursive: true);
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('HLS download error: $e');
      return false;
    }
  }

  /// Downloads progressive MP4 file with Range resumption and redirect support
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
        // Atomic promotion: replace any incomplete file with completed file
        final targetFile = File(targetPath);
        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        await partFile.rename(targetPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Progressive download error: $e');
      return false;
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
      _items.removeWhere((i) => i.id == id);
      notifyListeners();
      await _saveDownloads();
    }
  }
}
