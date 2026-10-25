import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'aoneroom_client.dart';

/// Resolves TMDB metadata (id, title, media_type, release year) to Aoneroom `subjectId`.
class AoneroomMatcher {
  static final AoneroomMatcher instance = AoneroomMatcher._internal();
  AoneroomMatcher._internal();

  // In-memory mapping cache: key "$type:$tmdbId" -> subjectId
  final Map<String, String> _memoryCache = {};

  // Cached pool of catalog subjects from /home and /trending (1-hour memory TTL)
  List<Map<String, dynamic>>? _catalogPool;
  DateTime? _catalogPoolTimestamp;

  static const Duration _cacheTtl = Duration(hours: 24);
  static const Duration _catalogTtl = Duration(hours: 1);
  static const double _minMatchConfidence = 0.85;

  /// Resolves TMDB title to Aoneroom subjectId using local cache, catalog scanning, and fuzzy string similarity.
  Future<String?> resolveSubjectId({
    required String type, // 'movie' or 'tv'
    required int tmdbId,
    required String title,
    String? releaseDate,
    int? year,
  }) async {
    final cacheKey = '$type:$tmdbId';

    // 1. In-memory check (instant 0ms)
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // 2. Persistent SharedPreferences check (24h TTL)
    final cachedId = await _getCachedFromPrefs(cacheKey);
    if (cachedId != null && cachedId.isNotEmpty) {
      _memoryCache[cacheKey] = cachedId;
      return cachedId;
    }

    // 3. Fallback: Fuzzy match against Aoneroom catalog (trending + home operating lists)
    final catalog = await _getCatalogPool();
    if (catalog.isEmpty) {
      debugPrint('AoneroomMatcher: catalog pool is empty');
      return null;
    }

    final targetYear = year ?? _parseYear(releaseDate);
    final normalizedTargetTitle = _normalizeTitle(title);

    String? bestSubjectId;
    double highestScore = 0.0;

    for (final item in catalog) {
      final rawTitle = item['title']?.toString() ?? '';
      if (rawTitle.isEmpty) continue;

      final normalizedCandidateTitle = _normalizeTitle(rawTitle);
      final similarity = _calculateSimilarity(normalizedTargetTitle, normalizedCandidateTitle);

      // Verify release year if present
      final candidateDate = item['releaseDate']?.toString();
      final candidateYear = _parseYear(candidateDate);

      double score = similarity;
      if (targetYear != null && candidateYear != null) {
        final yearDiff = (targetYear - candidateYear).abs();
        if (yearDiff == 0) {
          score = min(1.0, score + 0.05); // Bonus for exact year match
        } else if (yearDiff > 1) {
          score -= 0.20; // Strict penalty for year mismatch
        }
      }

      if (score > highestScore && score >= _minMatchConfidence) {
        highestScore = score;
        bestSubjectId = item['subjectId']?.toString();
      }
    }

    if (bestSubjectId != null && bestSubjectId.isNotEmpty) {
      debugPrint(
        'AoneroomMatcher: Matched "$title" ($targetYear) -> subjectId $bestSubjectId (confidence: ${(highestScore * 100).toStringAsFixed(1)}%)',
      );
      // Persist to caches
      _memoryCache[cacheKey] = bestSubjectId;
      await _saveToPrefs(cacheKey, bestSubjectId);
      return bestSubjectId;
    }

    debugPrint('AoneroomMatcher: No confident match for "$title" (best score: ${(highestScore * 100).toStringAsFixed(1)}%)');
    return null;
  }

  /// Manually save an established mapping (e.g. from cloud database or user selection)
  Future<void> saveMapping(String type, int tmdbId, String subjectId) async {
    final key = '$type:$tmdbId';
    _memoryCache[key] = subjectId;
    await _saveToPrefs(key, subjectId);
  }

  // ---------------------------------------------------------------------------
  // Catalog Caching & Candidate Fetching
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _getCatalogPool() async {
    if (_catalogPool != null &&
        _catalogPoolTimestamp != null &&
        DateTime.now().difference(_catalogPoolTimestamp!) < _catalogTtl) {
      return _catalogPool!;
    }

    final pool = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    try {
      // 1. Trending subjects
      final trending = await AoneroomClient.instance.getTrendingSubjects();
      for (final item in trending) {
        final id = item['subjectId']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          pool.add(item);
        }
      }

      // 2. Home subjects across 30+ categories
      final homeSubs = await AoneroomClient.instance.getHomeSubjects();
      for (final item in homeSubs) {
        final id = item['subjectId']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          pool.add(item);
        }
      }

      _catalogPool = pool;
      _catalogPoolTimestamp = DateTime.now();
    } catch (e) {
      debugPrint('AoneroomMatcher: error building catalog pool: $e');
    }

    return pool;
  }

  // ---------------------------------------------------------------------------
  // String Normalization & Similarity Scoring
  // ---------------------------------------------------------------------------

  /// Cleans titles by removing bracketed notes, season suffixes, punctuation, and extra whitespace.
  static String _normalizeTitle(String raw) {
    var s = raw.toLowerCase();

    // Replace & with and
    s = s.replaceAll('&', ' and ');

    // Remove bracketed dub tags, e.g. [English], [Hindi Dub], (2023)
    s = s.replaceAll(RegExp(r'\[.*?\]'), ' ');
    s = s.replaceAll(RegExp(r'\(.*?\)'), ' ');

    // Remove season markers like S1-S6, Season 1, etc.
    s = s.replaceAll(RegExp(r'\bs\d+(-s\d+)?\b'), ' ');
    s = s.replaceAll(RegExp(r'\bseason\s*\d+\b'), ' ');
    s = s.replaceAll(RegExp(r'\bseries\b'), ' ');

    // Remove all punctuation
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    // Remove common stop words at start
    s = s.trim();
    if (s.startsWith('the ')) s = s.substring(4).trim();
    if (s.startsWith('a ')) s = s.substring(2).trim();

    // Collapse multiple spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Calculates a blend of Dice's Coefficient (bigram overlap) and Levenshtein similarity.
  static double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    // Substring containment check for high-confidence match
    if (s1.length > 5 && s2.length > 5) {
      if (s1.contains(s2) || s2.contains(s1)) {
        final ratio = min(s1.length, s2.length) / max(s1.length, s2.length);
        if (ratio >= 0.70) return min(1.0, 0.85 + (ratio * 0.15));
      }
    }

    final dice = _diceCoefficient(s1, s2);
    final lev = _levenshteinSimilarity(s1, s2);

    return (dice * 0.6) + (lev * 0.4);
  }

  /// Dice's Coefficient based on letter bigrams.
  static double _diceCoefficient(String s1, String s2) {
    if (s1.length < 2 || s2.length < 2) {
      return s1 == s2 ? 1.0 : 0.0;
    }

    final bigrams1 = <String, int>{};
    for (int i = 0; i < s1.length - 1; i++) {
      final b = s1.substring(i, i + 2);
      bigrams1[b] = (bigrams1[b] ?? 0) + 1;
    }

    int matches = 0;
    for (int i = 0; i < s2.length - 1; i++) {
      final b = s2.substring(i, i + 2);
      final count = bigrams1[b] ?? 0;
      if (count > 0) {
        matches++;
        bigrams1[b] = count - 1;
      }
    }

    final totalBigrams = (s1.length - 1) + (s2.length - 1);
    return (2.0 * matches) / totalBigrams;
  }

  /// Normalized Levenshtein similarity (1.0 - (dist / maxLen)).
  static double _levenshteinSimilarity(String s1, String s2) {
    final maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;

    final dist = _levenshteinDistance(s1, s2);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshteinDistance(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;
    final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = min(
          d[i - 1][j] + 1, // deletion
          min(
            d[i][j - 1] + 1, // insertion
            d[i - 1][j - 1] + cost, // substitution
          ),
        );
      }
    }
    return d[m][n];
  }

  static int? _parseYear(String? date) {
    if (date == null || date.isEmpty) return null;
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(date);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // SharedPreferences Cache Persistence
  // ---------------------------------------------------------------------------

  Future<String?> _getCachedFromPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('aoneroom_map_$key');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final ts = DateTime.tryParse(map['timestamp'] ?? '');
        final id = map['subjectId']?.toString();
        if (ts != null && id != null && DateTime.now().difference(ts) < _cacheTtl) {
          return id;
        } else {
          prefs.remove('aoneroom_map_$key');
        }
      }
    } catch (e) {
      debugPrint('AoneroomMatcher: error reading cache from prefs: $e');
    }
    return null;
  }

  Future<void> _saveToPrefs(String key, String subjectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'subjectId': subjectId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await prefs.setString('aoneroom_map_$key', payload);
    } catch (e) {
      debugPrint('AoneroomMatcher: error saving cache to prefs: $e');
    }
  }
}
