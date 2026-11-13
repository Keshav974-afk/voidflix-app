import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../core/constants/theme_constants.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/youtube_service.dart';
import '../core/services/tv_mode_service.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/platform_utils.dart';
import '../models/media_item.dart';
import '../models/media_detail.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/detail_modal.dart';
import '../widgets/tv_back_button.dart';
import 'player_screen.dart';

class ClipsScreen extends StatefulWidget {
  final bool isActive;

  const ClipsScreen({super.key, this.isActive = true});

  @override
  State<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends State<ClipsScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isMuted = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<MediaItem> _buildClipsFeed(MediaProvider media, String? langCode) {
    final Set<int> seenIds = {};
    final List<MediaItem> feed = [];

    void addItems(List<MediaItem> items) {
      for (final it in items) {
        if (seenIds.add(it.id)) {
          feed.add(it);
        }
      }
    }

    if (langCode == 'hi' || langCode == 'pa' || langCode == 'ta' || langCode == 'te' || langCode == 'ml') {
      addItems(media.bollywoodMovies);
      addItems(media.indianSeries);
      addItems(media.southIndianMovies);
      addItems(media.trending);
      addItems(media.popularMovies);
    } else if (langCode == 'ko') {
      addItems(media.asianDrama);
      addItems(media.trending);
      addItems(media.popularMovies);
    } else if (langCode == 'ja') {
      addItems(media.anime);
      addItems(media.animeMovies);
      addItems(media.trending);
      addItems(media.popularMovies);
    } else {
      addItems(media.trending);
      addItems(media.popularMovies);
      addItems(media.trendingTV);
      addItems(media.nowPlayingMovies);
    }

    return feed.isEmpty ? media.trending : feed;
  }

  @override
  Widget build(BuildContext context) {
    // Strictly exclude Clips from Android TV mode
    if (TvModeService().isTvMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(backgroundColor: Colors.black);
    }

    final mediaProvider = context.watch<MediaProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final activeProfile = profileProvider.activeProfile;

    final pref = activeProfile.preferredAudioLang ??
        (activeProfile.preferredLanguages.isNotEmpty ? activeProfile.preferredLanguages.first : null);
    final prefLangCode = (pref != null && !pref.toLowerCase().contains('original'))
        ? LanguageUtils.getInfo(pref).code.toLowerCase()
        : null;

    final clips = _buildClipsFeed(mediaProvider, prefLangCode);
    final canPop = Navigator.of(context).canPop();

    if (clips.isEmpty) {
      return TvScreenWrapper(
        onBack: canPop ? () => Navigator.of(context).pop() : null,
        child: const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: AppTheme.primaryRed)),
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 480 : double.infinity),
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: clips.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    final item = clips[index];
                    final isCurrent = index == _currentPage;

                    return ClipPlayerTile(
                      key: ValueKey('clip_${item.id}'),
                      item: item,
                      isActive: widget.isActive && isCurrent,
                      isMuted: _isMuted,
                      preferredLangCode: prefLangCode,
                      onToggleMute: () {
                        setState(() => _isMuted = !_isMuted);
                      },
                    );
                  },
                ),
                if (canPop)
                  const SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: TvBackButton(showBackground: true),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClipPlayerTile extends StatefulWidget {
  final MediaItem item;
  final bool isActive;
  final bool isMuted;
  final String? preferredLangCode;
  final VoidCallback onToggleMute;

  const ClipPlayerTile({
    super.key,
    required this.item,
    required this.isActive,
    required this.isMuted,
    this.preferredLangCode,
    required this.onToggleMute,
  });

  @override
  State<ClipPlayerTile> createState() => _ClipPlayerTileState();
}

class _ClipPlayerTileState extends State<ClipPlayerTile> {
  final ApiService _apiService = ApiService();
  String? _trailerKey;
  MediaVideo? _activeVideo;
  String? _logoPath;
  WebViewController? _webController;
  VideoPlayerController? _videoPlayerController;
  bool _isLiked = false;
  bool _showMuteIndicator = false;
  Timer? _muteTimer;

  void _triggerMuteToggle() {
    widget.onToggleMute();
    _muteTimer?.cancel();
    setState(() => _showMuteIndicator = true);
    _muteTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _showMuteIndicator = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchTrailer();
  }

  @override
  void didUpdateWidget(covariant ClipPlayerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _resumeClip();
      } else {
        _pauseClip();
      }
    }
    if (oldWidget.isMuted != widget.isMuted) {
      _applyMute(widget.isMuted);
    }
  }

  void _pauseClip() {
    if (PlatformUtils.isWebViewSupported) {
      _webController?.runJavaScript('''
        var f = document.getElementById("trailer-frame");
        if (f && f.contentWindow) {
          f.contentWindow.postMessage('{"event":"command","func":"pauseVideo","args":""}', '*');
        }
      ''');
    } else {
      _videoPlayerController?.pause();
    }
  }

  void _resumeClip() {
    if (!widget.isActive) return;
    if (_trailerKey == null) return;

    if (PlatformUtils.isWebViewSupported) {
      if (_webController != null) {
        _webController?.runJavaScript('''
          var f = document.getElementById("trailer-frame");
          if (f && f.contentWindow) {
            f.contentWindow.postMessage('{"event":"command","func":"playVideo","args":""}', '*');
          }
        ''');
      } else {
        _initWebController(_trailerKey!);
      }
    } else {
      if (_videoPlayerController != null) {
        _videoPlayerController?.play();
      } else {
        _initNativePlayer(_trailerKey!);
      }
    }
  }

  void _applyMute(bool muted) {
    if (PlatformUtils.isWebViewSupported) {
      final fn = muted ? 'mute' : 'unMute';
      _webController?.runJavaScript('''
        var f = document.getElementById("trailer-frame");
        if (f && f.contentWindow) {
          f.contentWindow.postMessage('{"event":"command","func":"$fn","args":""}', '*');
        }
      ''');
    } else {
      _videoPlayerController?.setVolume(muted ? 0.0 : 1.0);
    }
  }

  @override
  void dispose() {
    _muteTimer?.cancel();
    _pauseClip();
    try {
      _webController?.loadHtmlString('<html><body style="background:#000;"></body></html>');
    } catch (_) {}
    _webController = null;
    _disposeNativePlayer();
    super.dispose();
  }

  void _disposeNativePlayer() {
    final vc = _videoPlayerController;
    _videoPlayerController = null;
    vc?.dispose();
  }

  Future<void> _fetchTrailer() async {
    try {
      final detail = await _apiService.getDetails(
        widget.item.mediaType,
        widget.item.id,
        languageCode: widget.preferredLangCode,
      );
      if (!mounted) return;

      if (detail.logoPath != null && detail.logoPath!.isNotEmpty) {
        _logoPath = detail.logoPath;
      }

      // Prioritize Clips, Behind the Scenes, and Featurettes in Clips section
      final bestClip = detail.findBestClipVideo(preferredLangCode: widget.preferredLangCode);
      if (bestClip != null && bestClip.key.isNotEmpty) {
        _activeVideo = bestClip;
        _trailerKey = bestClip.key;
        if (widget.isActive) {
          if (PlatformUtils.isWebViewSupported) {
            _initWebController(bestClip.key);
          } else {
            _initNativePlayer(bestClip.key);
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initNativePlayer(String key) async {
    _disposeNativePlayer();
    try {
      final directUrl = await YoutubeService.extractDirectStream(key);
      if (!mounted) return;
      if (directUrl != null && directUrl.isNotEmpty) {
        final vc = VideoPlayerController.networkUrl(Uri.parse(directUrl));
        await vc.initialize();
        if (!mounted) {
          vc.dispose();
          return;
        }
        vc.setLooping(true);
        vc.setVolume(widget.isMuted ? 0.0 : 1.0);
        if (widget.isActive) {
          await vc.play();
        }
        if (mounted) {
          setState(() => _videoPlayerController = vc);
        }
      }
    } catch (e) {
      debugPrint('Error playing direct trailer stream: $e');
    }
  }

  void _initWebController(String key) {
    if (!PlatformUtils.isWebViewSupported) return;
    if (key.isEmpty) return;
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.contains('embed') ||
                request.url.startsWith('about:blank') ||
                request.url.startsWith('data:') ||
                request.url.contains('voidflix.org')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (url) {
            controller.runJavaScript('''
              document.body.style.backgroundColor = "#000";
              document.body.style.margin = "0";
              document.body.style.padding = "0";
              document.body.style.overflow = "hidden";
            ''');
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
      android.setMixedContentMode(MixedContentMode.alwaysAllow);
      android.setAllowContentAccess(true);
      android.setAllowFileAccess(true);
    }

    final html = YoutubeService.buildTrailerEmbedHtml(key, isMuted: widget.isMuted);
    controller.loadHtmlString(html, baseUrl: 'https://voidflix.org');

    if (mounted) {
      setState(() => _webController = controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = context.watch<WatchlistProvider>();
    final isInWatchlist = watchlistProvider.isInWatchlist(widget.item.id);

    final backdropUrl = ApiService.getImageUrl(
      widget.item.backdropPath ?? widget.item.posterPath,
      size: 'w780',
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Trailer Video Player or High-Res Backdrop Fallback
        if (widget.isActive && _webController != null && _trailerKey != null)
          Positioned.fill(
            child: IgnorePointer(
              child: WebViewWidget(controller: _webController!),
            ),
          )
        else if (widget.isActive && _videoPlayerController != null && _videoPlayerController!.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoPlayerController!.value.size.width,
                height: _videoPlayerController!.value.size.height,
                child: VideoPlayer(_videoPlayerController!),
              ),
            ),
          )
        else
          CachedNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            memCacheWidth: 780,
            memCacheHeight: 440,
            filterQuality: FilterQuality.low,
            placeholder: (c, u) => Container(color: Colors.black),
            errorWidget: (c, u, e) => Container(color: Colors.black),
          ),

        // Direct YouTube external launch button if video cannot be embedded/streamed on PC
        if (!PlatformUtils.isWebViewSupported && _trailerKey != null && (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized))
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                _activeVideo?.isBehindTheScenes == true
                    ? 'Watch BTS on YouTube'
                    : (_activeVideo?.isClip == true
                        ? 'Watch Clip on YouTube'
                        : 'Watch on YouTube'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                _pauseClip();
                final ytUrl = 'https://www.youtube.com/watch?v=$_trailerKey';
                await launchUrl(Uri.parse(ytUrl), mode: LaunchMode.externalApplication);
                if (mounted && widget.isActive) {
                  _resumeClip();
                }
              },
            ),
          ),

        // 2. Subtle Gradient Overlay for readable UI
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x77000000),
                    Colors.transparent,
                    Color(0x99000000),
                    Color(0xF0000000),
                  ],
                  stops: [0.0, 0.35, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 3. Top Sound & Trailer Badge
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.8), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _activeVideo?.isBehindTheScenes == true
                          ? Icons.video_camera_back_outlined
                          : (_activeVideo?.isClip == true
                              ? Icons.movie_creation_outlined
                              : (_activeVideo?.isTeaser == true
                                  ? Icons.local_fire_department_outlined
                                  : Icons.movie_filter_outlined)),
                      color: AppTheme.primaryRed,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _activeVideo?.isBehindTheScenes == true
                          ? 'BEHIND THE SCENES'
                          : (_activeVideo?.isClip == true
                              ? 'FEATURED CLIP'
                              : (_activeVideo?.isTeaser == true
                                  ? 'OFFICIAL TEASER'
                                  : (_activeVideo?.isTrailer == true
                                      ? 'OFFICIAL TRAILER'
                                      : 'VOIDFLIX CLIPS'))),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _triggerMuteToggle,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Icon(
                    widget.isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Animated Central Volume / Mute Feedback HUD
        if (_showMuteIndicator)
          Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showMuteIndicator ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.isMuted ? 'Muted' : 'Sound On',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 4. Right Side Actions (Reels / Netflix style vertical icons)
        Positioned(
          right: 14,
          bottom: 110,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Like / Rate
              _buildRightAction(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                label: 'Like',
                color: _isLiked ? AppTheme.primaryRed : Colors.white,
                onTap: () {
                  setState(() => _isLiked = !_isLiked);
                },
              ),
              const SizedBox(height: 18),

              // My List
              _buildRightAction(
                icon: isInWatchlist ? Icons.check : Icons.add,
                label: 'My List',
                color: isInWatchlist ? AppTheme.primaryRed : Colors.white,
                onTap: () => watchlistProvider.toggleWatchlist(widget.item),
              ),
              const SizedBox(height: 18),

              // Native Share
              _buildRightAction(
                icon: Icons.share_outlined,
                label: 'Share',
                color: Colors.white,
                onTap: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Watch "${widget.item.title}" on Voidflix!\nhttps://voidflix.org/watch/${widget.item.mediaType}/${widget.item.id}',
                      subject: 'Watch ${widget.item.title} on Voidflix',
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // Info
              _buildRightAction(
                icon: Icons.info_outline,
                label: 'Details',
                color: Colors.white,
                onTap: () async {
                  _pauseClip();
                  await DetailModal.show(context, widget.item);
                  if (mounted && widget.isActive) {
                    _resumeClip();
                  }
                },
              ),
            ],
          ),
        ),

        // 5. Bottom Metadata & "Watch Full Movie / Show" Button
        Positioned(
          left: 16,
          right: 80,
          bottom: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_logoPath != null && _logoPath!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: CachedNetworkImage(
                    imageUrl: ApiConstants.getImageUrl(_logoPath, size: 'w500'),
                    height: 52,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    errorWidget: (c, u, e) => Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  widget.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              if (_activeVideo != null &&
                  _activeVideo!.name.isNotEmpty &&
                  !_activeVideo!.name.toLowerCase().contains(widget.item.title.toLowerCase())) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _activeVideo!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              if (widget.item.overview.isNotEmpty)
                Text(
                  widget.item.overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.play_arrow, color: Colors.black, size: 22),
                label: Text(
                  widget.item.mediaType == 'tv' ? 'Watch Full Series' : 'Watch Full Movie',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                ),
                onPressed: () async {
                  _pauseClip();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        mediaId: widget.item.id,
                        mediaTitle: widget.item.title,
                        mediaType: widget.item.mediaType,
                        posterPath: widget.item.posterPath,
                        backdropPath: widget.item.backdropPath,
                      ),
                    ),
                  );
                  if (mounted && widget.isActive) {
                    _resumeClip();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12, width: 0.8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
