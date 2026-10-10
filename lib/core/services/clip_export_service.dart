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

  static String _formatSrtTimestamp(double seconds) {
    final ms = (seconds * 1000).toInt();
    final h = (ms ~/ 3600000).toString().padLeft(2, '0');
    final m = ((ms % 3600000) ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final millis = (ms % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$millis';
  }

  static String _generateSrt(List<Map<String, dynamic>> subtitles, double startSeconds) {
    final buffer = StringBuffer();
    int index = 1;
    for (final item in subtitles) {
      final sSec = (item['start'] as num).toDouble() / 1000.0;
      final eSec = (item['end'] as num).toDouble() / 1000.0;
      final text = item['text'] as String;

      final relStart = (sSec - startSeconds).clamp(0.0, double.infinity);
      final relEnd = (eSec - startSeconds).clamp(relStart + 0.5, double.infinity);

      buffer.writeln('$index');
      buffer.writeln('${_formatSrtTimestamp(relStart)} --> ${_formatSrtTimestamp(relEnd)}');
      buffer.writeln(text);
      buffer.writeln();
      index++;
    }
    return buffer.toString();
  }

  /// Trims/extracts and saves a clip from the active stream or local file to the gallery
  /// with low-memory streaming and native hardware-accelerated sample trimming.
  static Future<File?> exportClip({
    required String title,
    required double startSeconds,
    required double endSeconds,
    String? localFilePath,
    String? streamUrl,
    Map<String, String>? streamHeaders,
    List<Map<String, dynamic>>? subtitles,
    bool burnSubtitles = false,
    Function(double progress, String status)? onProgress,
  }) async {
    File? tempSourceFile;
    try {
      onProgress?.call(0.05, 'Preparing clip export…');

      final clipDir = await _getGalleryClipDirectory();
      final cleanTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final startSecInt = startSeconds.toInt();
      final endSecInt = endSeconds.toInt();
      final fileName = 'Voidflix_${cleanTitle}_${startSecInt}s-${endSecInt}s.mp4';
      final outputFile = File('${clipDir.path}/$fileName');

      final subtitleList = subtitles ?? <Map<String, dynamic>>[];

      // Generate sidecar .srt subtitle file if subtitles were enabled
      if (burnSubtitles && subtitleList.isNotEmpty) {
        try {
          final srtFile = File('${clipDir.path}/Voidflix_${cleanTitle}_${startSecInt}s-${endSecInt}s.srt');
          await srtFile.writeAsString(_generateSrt(subtitleList, startSeconds));
          try {
            await _channel.invokeMethod('scanFileIntoGallery', {
              'filePath': srtFile.absolute.path,
            });
          } catch (_) {}
        } catch (_) {}
      }

      String? inputVideoPath;
      int startMs = (startSeconds * 1000).toInt();
      int endMs = (endSeconds * 1000).toInt();
      List<Map<String, dynamic>> adjustedCues = subtitleList;

      // 1. Source is an offline downloaded local file
      if (localFilePath != null && File(localFilePath).existsSync()) {
        onProgress?.call(0.3, 'Using local offline media…');
        inputVideoPath = localFilePath;
      }
      // 2. Source is an online stream (HLS or progressive MP4)
      else if (streamUrl != null && streamUrl.isNotEmpty) {
        onProgress?.call(0.1, 'Resolving stream…');
        final client = http.Client();
        final cacheDir = await getTemporaryDirectory();

        try {
          if (streamUrl.contains('.m3u8')) {
            onProgress?.call(0.15, 'Reading playlist…');
            final headers = Map<String, String>.from(streamHeaders ?? {});
            headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

            final res = await client.get(Uri.parse(streamUrl), headers: headers).timeout(const Duration(seconds: 10));
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
                const estSegDur = 4.0;
                final startIdx = (startSeconds / estSegDur).floor().clamp(0, segmentUrls.length - 1);
                final endIdx = (endSeconds / estSegDur).ceil().clamp(startIdx + 1, segmentUrls.length);

                final targetSegments = segmentUrls.sublist(startIdx, endIdx);
                tempSourceFile = File('${cacheDir.path}/temp_clip_${DateTime.now().millisecondsSinceEpoch}.ts');
                
                // Low-memory streaming directly to disk with RandomAccessFile
                final raf = await tempSourceFile.open(mode: FileMode.write);

                try {
                  for (int i = 0; i < targetSegments.length; i++) {
                    final segP = 0.2 + (0.5 * (i / targetSegments.length));
                    onProgress?.call(segP, 'Downloading stream (${(segP * 100).toInt()}%)…');

                    bool downloaded = false;
                    for (int attempt = 0; attempt < 2; attempt++) {
                      try {
                        final req = http.Request('GET', targetSegments[i]);
                        req.headers.addAll(headers);
                        final streamedRes = await client.send(req).timeout(const Duration(seconds: 10));
                        if (streamedRes.statusCode == 200) {
                          await for (final chunk in streamedRes.stream) {
                            await raf.writeFrom(chunk);
                          }
                          await raf.flush();
                          downloaded = true;
                          break;
                        }
                      } catch (e) {
                        debugPrint('Segment $i download retry ${attempt + 1}: $e');
                        await Future.delayed(const Duration(milliseconds: 150));
                      }
                    }
                    if (!downloaded) {
                      debugPrint('Segment $i skipped after retries');
                    }
                  }
                } finally {
                  await raf.close();
                }

                inputVideoPath = tempSourceFile.path;
                final offsetSec = startIdx * estSegDur;
                final relStartSec = (startSeconds - offsetSec).clamp(0.0, double.infinity);
                final relEndSec = (endSeconds - offsetSec).clamp(relStartSec + 1.0, double.infinity);
                startMs = (relStartSec * 1000).toInt();
                endMs = (relEndSec * 1000).toInt();

                final offsetMs = (offsetSec * 1000).toInt();
                adjustedCues = subtitleList.map((c) {
                  return {
                    'start': ((c['start'] as num).toInt() - offsetMs),
                    'end': ((c['end'] as num).toInt() - offsetMs),
                    'text': c['text'],
                  };
                }).toList();
              }
            }
          } else {
            // Progressive MP4 stream with chunk streaming
            onProgress?.call(0.2, 'Downloading stream…');
            final headers = Map<String, String>.from(streamHeaders ?? {});
            headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

            final req = http.Request('GET', Uri.parse(streamUrl));
            req.headers.addAll(headers);
            final streamedRes = await client.send(req).timeout(const Duration(seconds: 25));
            if (streamedRes.statusCode == 200 || streamedRes.statusCode == 206) {
              tempSourceFile = File('${cacheDir.path}/temp_clip_${DateTime.now().millisecondsSinceEpoch}.mp4');
              final raf = await tempSourceFile.open(mode: FileMode.write);
              try {
                await for (final chunk in streamedRes.stream) {
                  await raf.writeFrom(chunk);
                }
                await raf.flush();
              } finally {
                await raf.close();
              }
              inputVideoPath = tempSourceFile.path;
            }
          }
        } finally {
          client.close();
        }
      }

      if (inputVideoPath != null && File(inputVideoPath).existsSync()) {
        onProgress?.call(0.75, 'Extracting & trimming clip…');

        // Invoke native Android MediaExtractor / MediaMuxer via MethodChannel
        try {
          final res = await _channel.invokeMethod('trimAndExportClip', {
            'inputPath': inputVideoPath,
            'outputPath': outputFile.absolute.path,
            'startMs': startMs,
            'endMs': endMs,
            'burnSubtitles': burnSubtitles,
            'subtitles': adjustedCues,
          });

          if (res != null && outputFile.existsSync() && outputFile.lengthSync() > 500) {
            onProgress?.call(1.0, 'Clip saved to Gallery!');
            return outputFile;
          }
        } catch (nativeErr) {
          debugPrint('Native clip export error: $nativeErr');
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error exporting clip: $e');
      return null;
    } finally {
      // Clean up temporary segment file
      if (tempSourceFile != null && tempSourceFile.existsSync()) {
        try {
          tempSourceFile.deleteSync();
        } catch (_) {}
      }
    }
  }
}
