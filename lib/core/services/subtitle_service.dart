import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  /// Whether the text contains Right-To-Left characters (Urdu, Arabic, Persian, Hebrew)
  bool get isRtl {
    return RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]').hasMatch(text);
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

  Map<String, dynamic> toJson() => {
        'label': label,
        'language': language,
        'url': url,
      };

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
        label: (json['label'] as String?) ?? 'Sub',
        language: (json['language'] as String?) ?? 'en',
        url: (json['url'] as String?) ?? '',
      );

  @override
  String toString() => 'SubtitleTrack($label - $language)';
}

class SubtitleService {
  final Map<String, List<SubtitleCue>> _cache = {};

  /// Loads and parses subtitle cues from a remote URL or local file path (.srt or .vtt).
  Future<List<SubtitleCue>> loadTrack(String url) async {
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return [];

        // Always decode response bytes using UTF-8 to prevent character corruption
        // in languages like Urdu, Hindi, Nepali, etc.
        final text = utf8.decode(res.bodyBytes, allowMalformed: true);
        final cues = parseSubtitles(text);
        _cache[url] = cues;
        return cues;
      } else {
        String path = url;
        if (path.startsWith('file://')) {
          try {
            path = Uri.parse(path).toFilePath();
          } catch (_) {
            path = path.replaceFirst('file://', '');
          }
        }
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final content = utf8.decode(bytes, allowMalformed: true);
          final cues = parseSubtitles(content);
          _cache[url] = cues;
          return cues;
        }
      }
      return [];
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

  /// Cleans subtitle lines by removing WebVTT/HTML/SSA formatting and unescaping
  /// all HTML numeric entities, hex entities, and unicode characters so languages like
  /// Urdu, Hindi, Nepali, etc. compile and render into pure native text.
  static String _cleanSubtitleText(String raw) {
    String text = raw;

    // 1. Remove WebVTT intra-line timestamps e.g. <00:01:23.456>
    text = text.replaceAll(RegExp(r'<\d{2}:\d{2}:\d{2}[.,]\d{3}>'), '');

    // 2. Remove HTML-like tags: <i>, </i>, <b>, <font color="...">, <v Speaker>, <c.yellow>
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 3. Remove ASS/SSA style tags: {\an8}, {\pos(x,y)}, etc.
    text = text.replaceAll(RegExp(r'\{[^}]+\}'), '');

    // 4. Decode hex entities: &#x0627; or &#X627; (Urdu/Arabic/Devanagari characters)
    text = text.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (match) {
      final hex = match.group(1);
      if (hex == null) return '';
      final code = int.tryParse(hex, radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // 5. Decode decimal entities: &#1575; or &#2344;
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final dec = match.group(1);
      if (dec == null) return '';
      final code = int.tryParse(dec);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // 6. Decode Unicode escape sequences: \u0627 or \u0915
    text = text.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      final hex = match.group(1);
      if (hex == null) return '';
      final code = int.tryParse(hex, radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // 7. Decode common named HTML entities
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lrm;', '')
        .replaceAll('&rlm;', '');

    return text.trim();
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
