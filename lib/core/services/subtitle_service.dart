import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SubtitleCue {
  final int startMs;
  final int endMs;
  final String text;

  const SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  bool matches(int positionMs) {
    return positionMs >= startMs && positionMs <= endMs;
  }
}

class SubtitleTrack {
  final String label;
  final String language;
  final String url;

  const SubtitleTrack({
    required this.label,
    required this.language,
    required this.url,
  });

  @override
  String toString() => 'SubtitleTrack($label - $language)';
}

class SubtitleService {
  final Map<String, List<SubtitleCue>> _cache = {};

  /// Loads and parses subtitle cues from a remote URL (.srt or .vtt).
  Future<List<SubtitleCue>> loadTrack(String url) async {
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];

      final cues = parseSubtitles(res.body);
      _cache[url] = cues;
      return cues;
    } catch (e) {
      debugPrint('Failed to load subtitle track ($url): $e');
      return [];
    }
  }

  /// Parses raw SRT or VTT content into a sorted list of SubtitleCues.
  static List<SubtitleCue> parseSubtitles(String raw) {
    final cues = <SubtitleCue>[];
    // Normalize newlines and strip BOM
    final clean = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\uFEFF', '').trim();
    final blocks = clean.split('\n\n');

    final timeRegex = RegExp(
      r'(?:(\d{1,2}):)?(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(?:(\d{1,2}):)?(\d{2}):(\d{2})[,.](\d{3})',
    );

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      int timeLineIndex = -1;
      Match? match;

      for (var i = 0; i < lines.length; i++) {
        final m = timeRegex.firstMatch(lines[i]);
        if (m != null) {
          timeLineIndex = i;
          match = m;
          break;
        }
      }

      if (match == null || timeLineIndex == -1) continue;

      final startMs = _parseTime(
        match.group(1),
        match.group(2)!,
        match.group(3)!,
        match.group(4)!,
      );
      final endMs = _parseTime(
        match.group(5),
        match.group(6)!,
        match.group(7)!,
        match.group(8)!,
      );

      final textLines = lines.sublist(timeLineIndex + 1);
      final rawText = textLines.join('\n').trim();
      final sanitized = _cleanSubtitleText(rawText);

      if (sanitized.isNotEmpty && endMs > startMs) {
        cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: sanitized));
      }
    }

    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static int _parseTime(String? hours, String minutes, String seconds, String millis) {
    final h = hours != null ? int.tryParse(hours) ?? 0 : 0;
    final m = int.tryParse(minutes) ?? 0;
    final s = int.tryParse(seconds) ?? 0;
    final ms = int.tryParse(millis) ?? 0;
    return (h * 3600000) + (m * 60000) + (s * 1000) + ms;
  }

  static String _cleanSubtitleText(String text) {
    return text
        // Remove HTML-like tags: <i>, </i>, <b>, <font color="...">, etc.
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Remove ASS/SSA style tags: {\an8}, {\pos(x,y)}, etc.
        .replaceAll(RegExp(r'\{[^}]+\}'), '')
        .trim();
  }

  /// Returns the text for the cue matching the given playback position.
  static String? getCueAt(List<SubtitleCue> cues, Duration position) {
    if (cues.isEmpty) return null;
    final posMs = position.inMilliseconds;

    // Binary search for efficiency
    int low = 0;
    int high = cues.length - 1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final cue = cues[mid];

      if (posMs < cue.startMs) {
        high = mid - 1;
      } else if (posMs > cue.endMs) {
        low = mid + 1;
      } else {
        return cue.text;
      }
    }

    return null;
  }
}
