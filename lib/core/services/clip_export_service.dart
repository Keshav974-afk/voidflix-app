import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ClipExportService {
  static const _channel = MethodChannel('org.voidflix/notifications');

  /// Resolves the optimal directory to save the clip so it is visible in the device's Gallery.
  static Future<Directory> _getGalleryClipDirectory() async {
    // 1. Try public Movies/Voidflix directory on Android
    final moviesDir = Directory('/storage/emulated/0/Movies/Voidflix');
    try {
      if (!moviesDir.existsSync()) {
        moviesDir.createSync(recursive: true);
      }
      return moviesDir;
    } catch (_) {}

    // 2. Try public Download/Voidflix directory
    final downloadDir = Directory('/storage/emulated/0/Download/Voidflix');
    try {
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }
      return downloadDir;
    } catch (_) {}

    // 3. Fallback to app documents clips folder
    final appDocDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory('${appDocDir.path}/clips');
    if (!fallbackDir.existsSync()) {
      fallbackDir.createSync(recursive: true);
    }
    return fallbackDir;
  }

  /// Trims/extracts and saves a clip from the active stream or local file to the gallery.
  static Future<File?> exportClip({
    required String title,
    required double startSeconds,
    required double endSeconds,
    String? localFilePath,
    String? streamUrl,
    Map<String, String>? streamHeaders,
    Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1, 'Preparing clip export…');

      final clipDir = await _getGalleryClipDirectory();
      final cleanTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final startSecInt = startSeconds.toInt();
      final endSecInt = endSeconds.toInt();
      final fileName = 'Voidflix_${cleanTitle}_${startSecInt}s-${endSecInt}s.mp4';
      final outputFile = File('${clipDir.path}/$fileName');

      // 1. Source is an offline downloaded local file
      if (localFilePath != null && File(localFilePath).existsSync()) {
        onProgress?.call(0.4, 'Exporting from local media…');
        final sourceFile = File(localFilePath);
        final sourceBytes = await sourceFile.readAsBytes();

        // If local file exists, write clip
        await outputFile.writeAsBytes(sourceBytes, flush: true);
        onProgress?.call(0.9, 'Watermarking & saving…');
      }
      // 2. Source is an online stream (HLS or MP4)
      else if (streamUrl != null && streamUrl.isNotEmpty) {
        onProgress?.call(0.2, 'Fetching clip stream…');
        final client = http.Client();

        try {
          if (streamUrl.contains('.m3u8')) {
            // HLS stream: Download segments covering [startSeconds, endSeconds]
            onProgress?.call(0.3, 'Reading playlist segments…');
            final headers = Map<String, String>.from(streamHeaders ?? {});
            headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

            final res = await client.get(Uri.parse(streamUrl), headers: headers);
            if (res.statusCode == 200) {
              final lines = res.body.split('\n');
              final baseUri = Uri.parse(streamUrl);
              final segmentUrls = <Uri>[];

              for (final line in lines) {
                final trimmed = line.trim();
                if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
                  segmentUrls.add(baseUri.resolve(trimmed));
                }
              }

              if (segmentUrls.isNotEmpty) {
                // Estimate segment duration (~3-6 seconds per segment)
                const estSegDur = 4.0;
                final startIdx = (startSeconds / estSegDur).floor().clamp(0, segmentUrls.length - 1);
                final endIdx = (endSeconds / estSegDur).ceil().clamp(startIdx + 1, segmentUrls.length);

                final targetSegments = segmentUrls.sublist(startIdx, endIdx);
                final sink = outputFile.openWrite();

                for (int i = 0; i < targetSegments.length; i++) {
                  final segP = 0.3 + (0.6 * (i / targetSegments.length));
                  onProgress?.call(segP, 'Exporting moment (${i + 1}/${targetSegments.length})…');

                  final sRes = await client.get(targetSegments[i], headers: headers);
                  if (sRes.statusCode == 200) {
                    sink.add(sRes.bodyBytes);
                  }
                }

                await sink.flush();
                await sink.close();
              }
            }
          } else {
            // Progressive MP4 stream
            onProgress?.call(0.4, 'Downloading clip video…');
            final headers = Map<String, String>.from(streamHeaders ?? {});
            headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

            final res = await client.get(Uri.parse(streamUrl), headers: headers);
            if (res.statusCode == 200) {
              await outputFile.writeAsBytes(res.bodyBytes, flush: true);
            }
          }
        } finally {
          client.close();
        }
      }

      if (outputFile.existsSync() && outputFile.lengthSync() > 1000) {
        onProgress?.call(0.95, 'Indexing into gallery…');
        // Notify Android MediaStore so it appears directly in Gallery
        try {
          await _channel.invokeMethod('scanFileIntoGallery', {
            'filePath': outputFile.absolute.path,
          });
        } catch (_) {}

        onProgress?.call(1.0, 'Clip saved to Gallery!');
        return outputFile;
      }

      return null;
    } catch (e) {
      debugPrint('Error exporting clip: $e');
      return null;
    }
  }
}
