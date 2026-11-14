import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/api_service.dart';
import '../services/tv_mode_service.dart';
import '../../models/media_item.dart';
import '../../screens/detail_screen.dart';
import '../../widgets/detail_modal.dart';

class PendingDeepLink {
  final String mediaType; // 'movie' or 'tv'
  final int mediaId;
  final int? season;
  final int? episode;
  final String rawUrl;

  PendingDeepLink({
    required this.mediaType,
    required this.mediaId,
    this.season,
    this.episode,
    required this.rawUrl,
  });

  @override
  String toString() =>
      'PendingDeepLink($mediaType, id: $mediaId, season: $season, episode: $episode)';
}

class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._internal();
  factory DeepLinkService() => instance;
  DeepLinkService._internal();

  static const MethodChannel _channel = MethodChannel('org.voidflix/notifications');
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isHandling = false;

  PendingDeepLink? _pendingLink;
  PendingDeepLink? get pendingLink => _pendingLink;

  bool _isMainAppReady = false;
  BuildContext? _activeContext;

  void init(GlobalKey<NavigatorState> navKey) {
    _navigatorKey = navKey;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          handleDeepLink(link);
        }
      }
    });

    // Check if app was launched via deep link
    _channel.invokeMethod<String>('getInitialDeepLink').then((link) {
      if (link != null && link.isNotEmpty) {
        handleDeepLink(link);
      }
    }).catchError((_) {});
  }

  /// Called by MainNavigationScreen once mounted and ready to present modals
  void notifyMainAppReady(BuildContext context) {
    _isMainAppReady = true;
    _activeContext = context;
    if (_pendingLink != null) {
      debugPrint('DeepLinkService: Main app ready with queued link: $_pendingLink');
      _executePendingDeepLink();
    }
  }

  /// If user logs out or switches profiles back to ProfileGateScreen
  void setAppNotReady() {
    _isMainAppReady = false;
    _activeContext = null;
  }

  Future<void> handleDeepLink(String urlString) async {
    try {
      final uri = Uri.tryParse(urlString);
      if (uri == null) return;

      // Extract path segments
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      String? mediaType;
      int? mediaId;

      if (uri.scheme == 'voidflix') {
        if (uri.host == 'watch' || (segments.isNotEmpty && segments.first == 'watch')) {
          final effectiveSegs = uri.host == 'watch' ? segments : segments.sublist(1);
          if (effectiveSegs.length >= 2) {
            mediaType = effectiveSegs[0];
            mediaId = int.tryParse(effectiveSegs[1]);
          }
        } else if (uri.host == 'movie' || uri.host == 'tv') {
          mediaType = uri.host;
          mediaId = segments.isNotEmpty ? int.tryParse(segments[0]) : null;
        } else if (segments.length >= 2 && (segments[0] == 'movie' || segments[0] == 'tv')) {
          mediaType = segments[0];
          mediaId = int.tryParse(segments[1]);
        }
      } else {
        if (segments.isNotEmpty && segments[0] == 'watch' && segments.length >= 3) {
          mediaType = segments[1];
          mediaId = int.tryParse(segments[2]);
        } else if (segments.length >= 2 && (segments[0] == 'movie' || segments[0] == 'tv')) {
          mediaType = segments[0];
          mediaId = int.tryParse(segments[1]);
        }
      }

      if (mediaType == null || mediaId == null || mediaId <= 0) return;
      mediaType = mediaType == 'tv' ? 'tv' : 'movie';

      // Parse season and episode from query parameters
      int? season;
      final sStr = uri.queryParameters['s'] ??
          uri.queryParameters['season'] ??
          uri.queryParameters['season_number'];
      if (sStr != null) {
        season = int.tryParse(sStr);
      }

      int? episode;
      final eStr = uri.queryParameters['e'] ??
          uri.queryParameters['episode'] ??
          uri.queryParameters['episode_number'];
      if (eStr != null) {
        episode = int.tryParse(eStr);
      }

      // Check path segments for /season/X or /episode/Y as fallback
      if (season == null) {
        final sIdx = segments.indexOf('season');
        if (sIdx != -1 && sIdx + 1 < segments.length) {
          season = int.tryParse(segments[sIdx + 1]);
        }
      }
      if (episode == null) {
        final eIdx = segments.indexOf('episode');
        if (eIdx != -1 && eIdx + 1 < segments.length) {
          episode = int.tryParse(segments[eIdx + 1]);
        }
      }

      _pendingLink = PendingDeepLink(
        mediaType: mediaType,
        mediaId: mediaId,
        season: season,
        episode: episode,
        rawUrl: urlString,
      );

      debugPrint('DeepLinkService: Registered $_pendingLink (mainAppReady: $_isMainAppReady)');

      // If user has already selected a profile and MainNavigationScreen is actively mounted:
      if (_isMainAppReady) {
        _executePendingDeepLink();
      }
    } catch (e) {
      debugPrint('DeepLinkService: Error parsing link $urlString: $e');
    }
  }

  Future<void> _executePendingDeepLink() async {
    if (_isHandling || _pendingLink == null) return;
    _isHandling = true;

    final target = _pendingLink!;
    _pendingLink = null;

    try {
      MediaItem item;
      try {
        final detail = await ApiService().getDetails(target.mediaType, target.mediaId);
        item = detail.toMediaItem();
      } catch (_) {
        item = MediaItem(
          id: target.mediaId,
          title: target.mediaType == 'tv' ? 'TV Series' : 'Movie',
          mediaType: target.mediaType,
          overview: '',
          voteAverage: 0.0,
        );
      }

      final navContext = _navigatorKey?.currentContext ?? _activeContext;
      if (navContext == null || !navContext.mounted) {
        // Context not mounted yet; restore pending link so next notify catches it
        _pendingLink = target;
        return;
      }

      debugPrint('DeepLinkService: Executing navigation for $target');

      if (TvModeService().isTvMode) {
        Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              mediaId: target.mediaId,
              mediaType: target.mediaType,
              initialSeason: target.season,
              initialEpisode: target.episode,
            ),
          ),
        );
      } else {
        DetailModal.show(
          navContext,
          item,
          initialSeason: target.season,
          initialEpisode: target.episode,
        );
      }
    } catch (e) {
      debugPrint('DeepLinkService: Error executing navigation: $e');
    } finally {
      _isHandling = false;
    }
  }
}
