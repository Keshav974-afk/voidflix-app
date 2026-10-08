import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/stream_extractor.dart';
import '../models/downloaded_item.dart';

class DownloadProvider extends ChangeNotifier {
  static const String _storageKey = 'voidflix_downloads_data';

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

  Future<void> loadDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _items.clear();
        for (final item in list) {
          final d = DownloadedItem.fromJson(item as Map<String, dynamic>);
          // Verify local file exists for completed items
          if (d.status == 'completed' && File(d.localFilePath).existsSync()) {
            _items.add(d);
          } else if (d.status == 'downloading') {
            // Reset interrupted downloads to failed so user can restart
            _items.add(d.copyWith(status: 'failed'));
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

  double getProgress(String id) {
    final item = getItem(id);
    return item?.progress ?? 0.0;
  }

  DownloadedItem? getItem(String id) {
    return _items.where((i) => i.id == id).firstOrNull;
  }

  /// Initiates extraction and starts streaming download directly to app storage
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

    // 1. Create or update item in downloading state
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/downloads');
    if (!downloadDir.existsSync()) {
      await downloadDir.create(recursive: true);
    }
    final targetPath = '${downloadDir.path}/$id.mp4';

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
      progress: 0.02,
      downloadedAt: DateTime.now(),
    );

    _items.removeWhere((i) => i.id == id);
    _items.insert(0, item);
    notifyListeners();
    await _saveDownloads();

    // 2. Perform stream extraction to find direct video source
    try {
      final streams = await StreamExtractor.extractAll(
        type: mediaType,
        tmdbId: mediaId,
        season: season,
        episode: episode,
      );

      if (streams.isEmpty) {
        throw Exception('No direct stream available for offline download.');
      }

      // Pick best stream: preferably an MP4 with 1080p or 720p, or primary direct stream
      String downloadUrl = streams.first.url;
      Map<String, String> headers = streams.first.headers;
      String quality = 'HD';

      for (final s in streams) {
        if (s.qualities.isNotEmpty) {
          final bestQuality = s.qualities.first;
          downloadUrl = bestQuality.url;
          headers = s.headers;
          quality = bestQuality.label;
          break;
        }
      }

      // 3. Start chunked file download with progress reporting
      final client = http.Client();
      _activeClients[id] = client;

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers.addAll(headers);

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download server returned HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final file = File(targetPath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final p = (receivedBytes / totalBytes).clamp(0.05, 0.99);
          // Throttle updates for smooth performance
          if ((p - item.progress).abs() > 0.02) {
            item = item.copyWith(
              progress: p,
              fileSizeBytes: receivedBytes,
            );
            final idx = _items.indexWhere((i) => i.id == id);
            if (idx != -1) {
              _items[idx] = item;
              notifyListeners();
            }
          }
        }
      }

      await sink.flush();
      await sink.close();
      _activeClients.remove(id);

      // 4. Mark completed
      final finalSizeBytes = await file.length();
      item = item.copyWith(
        status: 'completed',
        progress: 1.0,
        fileSizeBytes: finalSizeBytes,
        quality: quality,
      );

      final idx = _items.indexWhere((i) => i.id == id);
      if (idx != -1) {
        _items[idx] = item;
        notifyListeners();
      }
      await _saveDownloads();
    } catch (e) {
      debugPrint('Download error ($id): $e');
      _activeClients.remove(id);

      // Remove partially written file if error occurs
      final file = File(targetPath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final idx = _items.indexWhere((i) => i.id == id);
      if (idx != -1) {
        _items[idx] = item.copyWith(status: 'failed', progress: 0.0);
        notifyListeners();
      }
      await _saveDownloads();
    }
  }

  void cancelDownload(String id) {
    final client = _activeClients.remove(id);
    client?.close();

    final item = getItem(id);
    if (item != null) {
      final file = File(item.localFilePath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
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
