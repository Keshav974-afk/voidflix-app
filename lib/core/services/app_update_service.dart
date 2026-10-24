import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateDownloadStatus {
  idle,
  downloading,
  installing,
  completed,
  cancelled,
  error,
}

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel('org.voidflix/notifications');
  static http.Client? _activeClient;
  static bool _isCancelled = false;

  /// Cancels any in-flight update download
  static void cancelDownload() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  /// Downloads the given update file with real-time stream progress and initiates installation
  static Future<bool> downloadAndInstall({
    required String downloadUrl,
    required String targetVersion,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    required void Function(UpdateDownloadStatus status, String? message) onStatusChanged,
  }) async {
    _isCancelled = false;
    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;

    try {
      onStatusChanged(UpdateDownloadStatus.downloading, 'Connecting to download server…');
      onProgress(0.0, 0, 0);

      final uri = Uri.parse(downloadUrl);
      final request = http.Request('GET', uri);
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();

      final extension = Platform.isWindows ? 'exe' : 'apk';
      final saveFile = File('${tempDir.path}/voidflix_v${targetVersion}_update.$extension');

      if (await saveFile.exists()) {
        try {
          await saveFile.delete();
        } catch (_) {}
      }

      final sink = saveFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        if (_isCancelled) {
          await sink.close();
          try {
            await saveFile.delete();
          } catch (_) {}
          onStatusChanged(UpdateDownloadStatus.cancelled, 'Download cancelled');
          return false;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final double progress = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;

        onProgress(progress, receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();

      if (_isCancelled) {
        try {
          await saveFile.delete();
        } catch (_) {}
        return false;
      }

      onProgress(1.0, receivedBytes, receivedBytes);
      onStatusChanged(UpdateDownloadStatus.installing, 'Opening package installer…');

      // Trigger Installation
      if (Platform.isAndroid) {
        try {
          final res = await _channel.invokeMethod<bool>('installApk', {
            'filePath': saveFile.path,
          });
          if (res == true) {
            onStatusChanged(UpdateDownloadStatus.completed, 'Installation prompt launched');
            return true;
          }
        } catch (e) {
          debugPrint('AppUpdateService: Error calling installApk: $e');
        }
      } else if (Platform.isWindows) {
        try {
          await Process.start(saveFile.path, []);
          onStatusChanged(UpdateDownloadStatus.completed, 'Setup installer launched');
          return true;
        } catch (e) {
          debugPrint('AppUpdateService: Error launching Windows installer: $e');
        }
      }

      // Fallback: Launch file or URL directly
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      onStatusChanged(UpdateDownloadStatus.completed, 'Ready');
      return true;
    } catch (e) {
      if (_isCancelled) {
        onStatusChanged(UpdateDownloadStatus.cancelled, 'Download cancelled');
        return false;
      }
      debugPrint('AppUpdateService: Download/install failed: $e');
      onStatusChanged(UpdateDownloadStatus.error, 'Download failed: $e');

      // Fallback to browser URL launch
      try {
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
      return false;
    } finally {
      _activeClient = null;
    }
  }

  /// Formats byte numbers to readable strings (e.g. 14.5 MB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
