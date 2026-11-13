import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/api_service.dart';
import '../services/tv_mode_service.dart';
import '../../models/media_item.dart';
import '../../screens/detail_screen.dart';
import '../../widgets/detail_modal.dart';

class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._internal();
  factory DeepLinkService() => instance;
  DeepLinkService._internal();

  static const MethodChannel _channel = MethodChannel('org.voidflix/notifications');
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _isHandling = false;

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
        Future.delayed(const Duration(milliseconds: 1000), () {
          handleDeepLink(link);
        });
      }
    }).catchError((_) {});
  }

  Future<void> handleDeepLink(String urlString) async {
    if (_isHandling) return;
    _isHandling = true;

    try {
      final uri = Uri.tryParse(urlString);
      if (uri == null) return;

      // Supported formats:
      // voidflix://watch/movie/12345
      // voidflix://watch/tv/12345?s=1&e=1
      // voidflix://movie/12345
      // voidflix://tv/12345
      // https://voidflix.org/watch/movie/12345
      // https://voidflix.org/watch/tv/12345?s=1&e=1
      // https://voidflix.org/movie/12345
      // https://voidflix.org/tv/12345

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

      MediaItem item;
      try {
        final detail = await ApiService().getDetails(mediaType, mediaId);
        item = detail.toMediaItem();
      } catch (_) {
        item = MediaItem(
          id: mediaId,
          title: 'Movie',
          mediaType: mediaType,
          overview: '',
          voteAverage: 0.0,
        );
      }

      final navContext = _navigatorKey?.currentContext;
      if (navContext == null || !navContext.mounted) return;

      if (TvModeService().isTvMode) {
        Navigator.of(navContext).push(
          MaterialPageRoute(
            builder: (_) => DetailScreen(mediaId: mediaId!, mediaType: mediaType!),
          ),
        );
      } else {
        DetailModal.show(navContext, item);
      }
    } catch (_) {
    } finally {
      _isHandling = false;
    }
  }
}
