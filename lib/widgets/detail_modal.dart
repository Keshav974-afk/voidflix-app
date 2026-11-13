import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/youtube_service.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/platform_utils.dart';
import '../models/media_item.dart';
import '../models/media_detail.dart';
import '../providers/download_provider.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import '../screens/downloads_screen.dart';
import '../screens/player_screen.dart';
import 'download_quality_picker.dart';
import 'media_card.dart';
import 'netflix_season_picker.dart';

class DetailModal extends StatefulWidget {
  final MediaItem item;
  final bool isDialog;

  const DetailModal({super.key, required this.item, this.isDialog = false});

  static Future<void> show(BuildContext context, MediaItem item) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    if (isWide) {
      return showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (_) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840, maxHeight: 720),
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DetailModal(item: item, isDialog: true),
              ),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetailModal(item: item),
    );
  }

  @override
  State<DetailModal> createState() => _DetailModalState();
}

class _DetailModalState extends State<DetailModal> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  MediaDetail? _detail;
  bool _isLoading = true;
  int _selectedSeason = 1;
  List<TvEpisode> _episodes = [];
  bool _isLoadingEpisodes = false;
  int _selectedTab = 0; // 0: Episodes (tv) or Trailers (movie), etc.
  bool _isLiked = false;

  // Trailer Player state
  String? _trailerKey;
  WebViewController? _trailerWebController;
  VideoPlayerController? _trailerVideoController;
  bool _isPlayingTrailer = false;
  bool _isTrailerMuted = true;
  bool _isTrailerLoading = false;
  bool _showMuteToast = false;
  Timer? _muteToastTimer;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _stopTrailer();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final profileProvider = context.read<ProfileProvider>();
      final activeProfile = profileProvider.activeProfile;
      final pref = activeProfile.preferredAudioLang ??
          (activeProfile.preferredLanguages.isNotEmpty ? activeProfile.preferredLanguages.first : null);
      final prefLangCode = (pref != null && !pref.toLowerCase().contains('original'))
          ? LanguageUtils.getInfo(pref).code.toLowerCase()
          : null;

      final detail = await _apiService.getDetails(
        widget.item.mediaType,
        widget.item.id,
        languageCode: prefLangCode,
      );

      if (mounted) {
        final trailerKey = detail.findTrailerKey(preferredLangCode: prefLangCode);
        setState(() {
          _detail = detail;
          _trailerKey = trailerKey;
          _isLoading = false;
        });

        if (widget.item.mediaType == 'tv' && detail.seasons.isNotEmpty) {
          _selectedSeason = detail.seasons.first.seasonNumber;
          _loadSeasonEpisodes(_selectedSeason);
        }

        // Autoplay trailer preview smoothly after bottom sheet settles
        if (trailerKey != null && trailerKey.isNotEmpty) {
          _autoPlayTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) {
              _initTrailer(trailerKey);
            }
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initTrailer(String key) {
    if (key.isEmpty) return;
    _stopTrailer(clearKey: false);
    setState(() {
      _trailerKey = key;
      _isTrailerLoading = true;
    });

    if (PlatformUtils.isWebViewSupported) {
      final controller = WebViewController()
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
              if (mounted) {
                setState(() {
                  _isTrailerLoading = false;
                  _isPlayingTrailer = true;
                });
              }
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

      final html = YoutubeService.buildTrailerEmbedHtml(key, isMuted: _isTrailerMuted);
      controller.loadHtmlString(html, baseUrl: 'https://voidflix.org');

      if (mounted) {
        setState(() {
          _trailerWebController = controller;
        });
      }
    } else {
      _initNativeTrailer(key);
    }
  }

  Future<void> _initNativeTrailer(String key) async {
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
        vc.setVolume(_isTrailerMuted ? 0.0 : 1.0);
        await vc.play();
        if (mounted) {
          setState(() {
            _trailerVideoController = vc;
            _isTrailerLoading = false;
            _isPlayingTrailer = true;
          });
        }
      } else {
        if (mounted) setState(() => _isTrailerLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isTrailerLoading = false);
    }
  }

  void _toggleTrailerMute() {
    final newMute = !_isTrailerMuted;
    setState(() {
      _isTrailerMuted = newMute;
      _showMuteToast = true;
    });
    _muteToastTimer?.cancel();
    _muteToastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _showMuteToast = false);
    });

    if (PlatformUtils.isWebViewSupported) {
      final fn = newMute ? 'mute' : 'unMute';
      _trailerWebController?.runJavaScript('''
        var f = document.getElementById("trailer-frame");
        if (f && f.contentWindow) {
          f.contentWindow.postMessage('{"event":"command","func":"$fn","args":""}', '*');
        }
      ''');
    } else {
      _trailerVideoController?.setVolume(newMute ? 0.0 : 1.0);
    }
  }

  void _stopTrailer({bool clearKey = true}) {
    _autoPlayTimer?.cancel();
    _muteToastTimer?.cancel();
    try {
      if (PlatformUtils.isWebViewSupported) {
        _trailerWebController?.runJavaScript('''
          var f = document.getElementById("trailer-frame");
          if (f && f.contentWindow) {
            f.contentWindow.postMessage('{"event":"command","func":"pauseVideo","args":""}', '*');
          }
          document.body.innerHTML = '';
        ''');
        _trailerWebController?.loadHtmlString('<html><body style="background:#000;"></body></html>');
      }
      _trailerWebController = null;
      final vc = _trailerVideoController;
      _trailerVideoController = null;
      vc?.pause();
      vc?.dispose();
      if (mounted) {
        setState(() {
          _isPlayingTrailer = false;
          _isTrailerLoading = false;
          if (clearKey) _trailerKey = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSeasonEpisodes(int seasonNumber) async {
    setState(() => _isLoadingEpisodes = true);
    try {
      final episodes = await _apiService.getSeasonEpisodes(widget.item.id, seasonNumber);
      if (mounted) {
        setState(() {
          _episodes = episodes;
          _isLoadingEpisodes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  void _playMedia({
    int season = 1,
    int episode = 1,
    String? localFilePath,
    String? episodeTitle,
    double? startPositionSeconds,
  }) {
    _stopTrailer();
    Navigator.of(context).pop(); // Dismiss modal
    final title = widget.item.mediaType == 'tv' && episodeTitle != null
        ? '${widget.item.title}: S${season}E$episode "$episodeTitle"'
        : widget.item.title;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: widget.item.id,
          mediaTitle: title,
          mediaType: widget.item.mediaType,
          season: season,
          episode: episode,
          posterPath: widget.item.posterPath,
          backdropPath: widget.item.backdropPath,
          localFilePath: localFilePath,
          startPositionSeconds: startPositionSeconds,
          originalLanguage: _detail?.originalLanguage,
        ),
      ),
    );
  }

  Future<void> _openSeasonPicker() async {
    if (_detail == null || _detail!.seasons.isEmpty) return;
    final newSeason = await NetflixSeasonPicker.show(
      context: context,
      seasons: _detail!.seasons,
      selectedSeason: _selectedSeason,
    );
    if (newSeason != null && newSeason != _selectedSeason && mounted) {
      setState(() => _selectedSeason = newSeason);
      _loadSeasonEpisodes(newSeason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = context.watch<WatchlistProvider>();
    final historyProvider = context.watch<HistoryProvider>();
    final downloadProvider = context.watch<DownloadProvider>();
    final inList = watchlistProvider.isInWatchlist(widget.item.id);
    final savedProgress = historyProvider.getProgress(widget.item.id);

    final backdropUrl = ApiConstants.getImageUrl(
      widget.item.backdropPath ?? widget.item.posterPath,
      size: 'w780',
    );

    final matchPercentage = widget.item.voteAverage > 0
        ? (widget.item.voteAverage * 10).round().clamp(75, 99)
        : 95;

    final isTv = widget.item.mediaType == 'tv';

    return Container(
      height: widget.isDialog ? null : MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: widget.isDialog
            ? BorderRadius.circular(16)
            : const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Drag handle indicator (only on bottom sheet)
          if (!widget.isDialog)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (_isLoading)
            const LinearProgressIndicator(
              color: AppTheme.primaryRed,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),

          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Top Backdrop / Trailer Section with Live Mobile Preview
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      // 1. 16:9 Player / Backdrop Frame
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Backdrop Base Image
                            backdropUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: backdropUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 780,
                                    memCacheHeight: 440,
                                    filterQuality: FilterQuality.low,
                                    placeholder: (c, u) => Container(color: const Color(0xFF222222)),
                                    errorWidget: (c, u, e) => Container(color: const Color(0xFF222222)),
                                  )
                                : Container(color: const Color(0xFF222222)),

                            // Interactive Trailer Video Player (Web or Native)
                            if (_isPlayingTrailer && _trailerWebController != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: false,
                                  child: WebViewWidget(controller: _trailerWebController!),
                                ),
                              )
                            else if (_isPlayingTrailer && _trailerVideoController != null && _trailerVideoController!.value.isInitialized)
                              Positioned.fill(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _trailerVideoController!.value.size.width,
                                    height: _trailerVideoController!.value.size.height,
                                    child: VideoPlayer(_trailerVideoController!),
                                  ),
                                ),
                              ),

                            // Loading Spinner when trailer is buffering
                            if (_isTrailerLoading)
                              Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(color: AppTheme.primaryRed, strokeWidth: 2.5),
                                  ),
                                ),
                              ),

                            // "Play Trailer" overlay button when stopped or available
                            if (_trailerKey != null && !_isPlayingTrailer && !_isTrailerLoading)
                              Center(
                                child: GestureDetector(
                                  onTap: () => _initTrailer(_trailerKey!),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white38, width: 1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.5),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                        SizedBox(width: 6),
                                        Text(
                                          'Preview Trailer',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Gradient fade at bottom
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.6, 1.0],
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.3),
                                  const Color(0xFF181818),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Trailer Badge on Top Left
                      Positioned(
                        top: 12,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.8), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_filter_outlined, color: AppTheme.primaryRed, size: 12),
                              SizedBox(width: 5),
                              Text(
                                'OFFICIAL TRAILER',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Sound Mute Toggle on Bottom Right (when trailer is playing)
                      if (_isPlayingTrailer)
                        Positioned(
                          bottom: 12,
                          right: 14,
                          child: GestureDetector(
                            onTap: _toggleTrailerMute,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 0.8),
                              ),
                              child: Icon(
                                _isTrailerMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),

                      // Central Sound HUD indicator
                      if (_showMuteToast)
                        Positioned.fill(
                          child: Center(
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isTrailerMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isTrailerMuted ? 'Muted' : 'Sound On',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Close button top right - stops trailer and pops modal
                      Positioned(
                        top: 12,
                        right: 14,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _stopTrailer();
                              Navigator.of(context).pop();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.75),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content body
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Stylized Logo (where available) with Plain Text Fallback
                        if (_detail?.logoPath != null && _detail!.logoPath!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: CachedNetworkImage(
                              imageUrl: ApiConstants.getImageUrl(_detail!.logoPath, size: 'w500'),
                              height: 56,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              placeholder: (c, u) => Text(
                                widget.item.title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              errorWidget: (c, u, e) => Text(
                                widget.item.title,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            widget.item.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        const SizedBox(height: 6),

                        // Metadata Row (Rating, Match %, Year, Maturity, Duration, HD, CC)
                        Row(
                          children: [
                            if (widget.item.voteAverage > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, color: AppTheme.primaryRed, size: 13),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.item.voteAverage.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '$matchPercentage% Match',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (widget.item.year.isNotEmpty) ...[
                              Text(
                                widget.item.year,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                isTv ? 'TV-MA' : 'PG-13',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_detail?.runtime != null && _detail!.runtime! > 0) ...[
                              Text(
                                '${_detail!.runtime}m',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'HD',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'CC',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Big Play / Resume button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final s = savedProgress?.season ?? (isTv ? _selectedSeason : 1);
                              final e = savedProgress?.episode ?? 1;
                              final offlineId = isTv
                                  ? DownloadProvider.generateId('tv', widget.item.id, season: s, episode: e)
                                  : DownloadProvider.generateId('movie', widget.item.id);
                              final offlineItem = downloadProvider.getItem(offlineId);
                              final localFile = offlineItem?.status == 'completed' ? offlineItem?.localFilePath : null;
                              final posSec = savedProgress != null && savedProgress.positionSeconds > 0
                                  ? savedProgress.positionSeconds.toDouble()
                                  : (savedProgress != null && savedProgress.progress > 0 && savedProgress.durationSeconds > 0
                                      ? (savedProgress.progress * savedProgress.durationSeconds).toDouble()
                                      : null);

                              _playMedia(season: s, episode: e, localFilePath: localFile, startPositionSeconds: posSec);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow, color: Colors.black, size: 26),
                            label: Text(
                              savedProgress != null
                                  ? (isTv
                                      ? 'Resume S${savedProgress.season} : E${savedProgress.episode}'
                                      : 'Resume')
                                  : 'Play',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Full-width Download Button (Site / Netflix Style)
                        Builder(
                          builder: (ctx) {
                            final firstEp = _episodes.isNotEmpty ? _episodes.first : null;
                            final targetEpNum = firstEp?.episodeNumber ?? 1;
                            final mainDlId = isTv
                                ? DownloadProvider.generateId('tv', widget.item.id, season: _selectedSeason, episode: targetEpNum)
                                : DownloadProvider.generateId('movie', widget.item.id);
                            final isDl = downloadProvider.isDownloaded(mainDlId);
                            final isDownloading = downloadProvider.isDownloading(mainDlId);
                            final progress = downloadProvider.getProgress(mainDlId);
                            final dlItem = downloadProvider.getItem(mainDlId);

                            if (isDownloading) {
                              return SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF262626),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  icon: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      value: progress > 0 ? progress : null,
                                      strokeWidth: 2.2,
                                      color: AppTheme.primaryRed,
                                    ),
                                  ),
                                  label: Text(
                                    'Downloading ${(progress * 100).toInt()}%',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              );
                            }

                            if (isDl) {
                              final mb = dlItem != null
                                  ? '${(dlItem.fileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
                                  : 'HD';
                              return SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _playMedia(
                                      season: _selectedSeason,
                                      episode: targetEpNum,
                                      episodeTitle: firstEp?.name,
                                      localFilePath: dlItem?.localFilePath,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF262626),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  icon: const Icon(Icons.download_done_rounded, color: AppTheme.primaryRed, size: 22),
                                  label: Text(
                                    'Downloaded ($mb)',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              );
                            }

                            return SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  DownloadQualityPicker.show(
                                    context,
                                    mediaId: widget.item.id,
                                    title: widget.item.title,
                                    mediaType: widget.item.mediaType,
                                    season: _selectedSeason,
                                    episode: targetEpNum,
                                    episodeTitle: firstEp?.name,
                                    episodeDescription: firstEp?.overview ?? _detail?.overview,
                                    posterPath: widget.item.posterPath,
                                    backdropPath: widget.item.backdropPath,
                                    stillPath: firstEp?.stillPath,
                                    runtime: firstEp != null && firstEp.runtime > 0 ? firstEp.runtime : (_detail?.runtime ?? 0),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF262626),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                ),
                                icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 22),
                                label: Text(
                                  isTv ? 'Download S$_selectedSeason:E$targetEpNum' : 'Download',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // Action buttons row: [My List] [Rate] [Share] [Download Season]
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActionButton(
                              icon: inList ? Icons.check : Icons.add,
                              label: 'My List',
                              isActive: inList,
                              onTap: () => watchlistProvider.toggleWatchlist(widget.item),
                            ),
                            _buildActionButton(
                              icon: _isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                              label: 'Rate',
                              isActive: _isLiked,
                              onTap: () => setState(() => _isLiked = !_isLiked),
                            ),
                            _buildActionButton(
                              icon: Icons.share_outlined,
                              label: 'Share',
                              isActive: false,
                              onTap: () {
                                final shareUrl = widget.item.mediaType == 'tv'
                                    ? 'https://voidflix.org/watch/tv/${widget.item.id}?s=$_selectedSeason&e=1'
                                    : 'https://voidflix.org/watch/movie/${widget.item.id}';
                                SharePlus.instance.share(
                                  ShareParams(
                                    text: 'Check out "${widget.item.title}" on Voidflix!\n$shareUrl',
                                    subject: 'Watch ${widget.item.title} on Voidflix',
                                  ),
                                );
                              },
                            ),
                            if (isTv)
                              _buildActionButton(
                                icon: Icons.file_download_outlined,
                                label: 'Download S$_selectedSeason',
                                isActive: false,
                                onTap: () {
                                  if (_episodes.isEmpty) {
                                    downloadProvider.startDownload(
                                      mediaId: widget.item.id,
                                      title: widget.item.title,
                                      mediaType: 'tv',
                                      season: _selectedSeason,
                                      episode: 1,
                                      posterPath: widget.item.posterPath,
                                      backdropPath: widget.item.backdropPath,
                                    );
                                  } else {
                                    for (final ep in _episodes) {
                                      downloadProvider.startDownload(
                                        mediaId: widget.item.id,
                                        title: widget.item.title,
                                        mediaType: 'tv',
                                        season: _selectedSeason,
                                        episode: ep.episodeNumber,
                                        episodeTitle: ep.name,
                                        episodeDescription: ep.overview,
                                        posterPath: widget.item.posterPath,
                                        backdropPath: widget.item.backdropPath,
                                        stillPath: ep.stillPath,
                                        runtime: ep.runtime,
                                      );
                                    }
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Storyline Overview
                        Text(
                          widget.item.overview.isNotEmpty
                              ? widget.item.overview
                              : (_detail?.overview ?? 'No overview available.'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Genres
                        if (_detail?.genres != null && _detail!.genres.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _detail!.genres.map((g) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                  ),
                                  child: Text(
                                    g,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        const Divider(color: Color(0xFF2A2A2A)),
                      ],
                    ),
                  ),
                ),

                // TV Shows: Episodes (0) / Trailers & More (1) / More Like This (2)
                if (isTv) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildTabButton(
                            title: 'Episodes',
                            isSelected: _selectedTab == 0,
                            onTap: () => setState(() => _selectedTab = 0),
                          ),
                          const SizedBox(width: 16),
                          _buildTabButton(
                            title: 'Trailers & More',
                            isSelected: _selectedTab == 1,
                            onTap: () => setState(() => _selectedTab = 1),
                          ),
                          const SizedBox(width: 16),
                          _buildTabButton(
                            title: 'More Like This',
                            isSelected: _selectedTab == 2,
                            onTap: () => setState(() => _selectedTab = 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_selectedTab == 0) ...[
                    // Season Picker Dropdown Pill + Info (Web style)
                    if (_detail?.seasons != null && _detail!.seasons.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: _openSeasonPicker,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Season $_selectedSeason',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _openSeasonPicker,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2A2A2A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Episodes List
                    if (_isLoadingEpisodes)
                      const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(color: AppTheme.primaryRed),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final ep = _episodes[index];
                            final stillUrl = ApiConstants.getImageUrl(ep.stillPath, size: 'w300');
                            final epDlId = DownloadProvider.generateId(
                              'tv',
                              widget.item.id,
                              season: _selectedSeason,
                              episode: ep.episodeNumber,
                            );
                            final isEpDl = downloadProvider.isDownloaded(epDlId);
                            final isEpDownloading = downloadProvider.isDownloading(epDlId);
                            final epProg = downloadProvider.getProgress(epDlId);
                            final epDlItem = downloadProvider.getItem(epDlId);

                            return InkWell(
                              onTap: () {
                                final isSameEp = savedProgress != null &&
                                    savedProgress.season == _selectedSeason &&
                                    savedProgress.episode == ep.episodeNumber;
                                final posSec = isSameEp
                                    ? (savedProgress.positionSeconds > 0
                                        ? savedProgress.positionSeconds.toDouble()
                                        : (savedProgress.progress > 0 && savedProgress.durationSeconds > 0
                                            ? (savedProgress.progress * savedProgress.durationSeconds).toDouble()
                                            : null))
                                    : null;
                                _playMedia(
                                  season: _selectedSeason,
                                  episode: ep.episodeNumber,
                                  episodeTitle: ep.name,
                                  localFilePath: isEpDl ? epDlItem?.localFilePath : null,
                                  startPositionSeconds: posSec,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFF222222))),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Episode Still Thumbnail
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: SizedBox(
                                            width: 105,
                                            height: 65,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (stillUrl.isNotEmpty)
                                                  CachedNetworkImage(
                                                    imageUrl: stillUrl,
                                                    fit: BoxFit.cover,
                                                  )
                                                else
                                                  Container(color: const Color(0xFF2E2E2E)),
                                                Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Colors.black.withValues(alpha: 0.6),
                                                    ),
                                                    child: const Icon(
                                                      Icons.play_arrow,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Episode Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${ep.episodeNumber}. ${ep.name}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if (ep.runtime > 0) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${ep.runtime}m',
                                                  style: const TextStyle(
                                                    color: AppTheme.textMuted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),

                                        // Episode Download Button / Status
                                        if (isEpDownloading)
                                          SizedBox(
                                            width: 38,
                                            height: 38,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                CircularProgressIndicator(
                                                  value: epProg > 0 ? epProg : null,
                                                  strokeWidth: 2.5,
                                                  color: AppTheme.primaryRed,
                                                  backgroundColor: Colors.white12,
                                                ),
                                                IconButton(
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                  icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                                                  tooltip: 'Cancel Download',
                                                  onPressed: () => downloadProvider.cancelDownload(epDlId),
                                                ),
                                              ],
                                            ),
                                          )
                                        else if (isEpDl)
                                          IconButton(
                                            icon: const Icon(Icons.download_done_rounded, color: AppTheme.primaryRed, size: 24),
                                            tooltip: 'Downloaded - Play offline',
                                            onPressed: () => _playMedia(
                                              season: _selectedSeason,
                                              episode: ep.episodeNumber,
                                              episodeTitle: ep.name,
                                              localFilePath: epDlItem?.localFilePath,
                                            ),
                                          )
                                        else
                                          IconButton(
                                            icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 24),
                                            tooltip: 'Download Episode',
                                            onPressed: () {
                                              DownloadQualityPicker.show(
                                                context,
                                                mediaId: widget.item.id,
                                                title: widget.item.title,
                                                mediaType: 'tv',
                                                season: _selectedSeason,
                                                episode: ep.episodeNumber,
                                                episodeTitle: ep.name,
                                                episodeDescription: ep.overview,
                                                posterPath: widget.item.posterPath,
                                                backdropPath: widget.item.backdropPath,
                                                stillPath: ep.stillPath,
                                                runtime: ep.runtime,
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                    if (ep.overview.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        ep.overview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _episodes.length,
                        ),
                      ),
                  ] else if (_selectedTab == 1) ...[
                    // Trailers & More Grid / List
                    _buildTrailersSliver(),
                  ] else ...[
                    // Recommendations Grid
                    _buildRecommendationsSliver(),
                  ],
                ] else ...[
                  // Movies: Trailers & More (0) / More Like This (1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildTabButton(
                            title: 'Trailers & More',
                            isSelected: _selectedTab == 0,
                            onTap: () => setState(() => _selectedTab = 0),
                          ),
                          const SizedBox(width: 16),
                          _buildTabButton(
                            title: 'More Like This',
                            isSelected: _selectedTab == 1,
                            onTap: () => setState(() => _selectedTab = 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedTab == 0) ...[
                    _buildTrailersSliver(),
                  ] else ...[
                    _buildRecommendationsSliver(),
                  ],
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: isActive ? AppTheme.primaryRed : Colors.white,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppTheme.primaryRed : AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primaryRed : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMuted,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildTrailersSliver() {
    final vids = _detail?.videos ?? [];
    if (vids.isEmpty && (_trailerKey == null || _trailerKey!.isEmpty)) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          child: Center(
            child: Text(
              'No trailers available for this title.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final backdropUrl = ApiConstants.getImageUrl(
      widget.item.backdropPath ?? widget.item.posterPath,
      size: 'w780',
    );

    final displayList = vids.isNotEmpty
        ? vids
        : [
            MediaVideo(
              id: '1',
              name: 'Official Trailer',
              key: _trailerKey!,
              site: 'YouTube',
              type: 'Trailer',
            )
          ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final v = displayList[index];
            final thumb = v.youtubeThumbnailUrl.isNotEmpty ? v.youtubeThumbnailUrl : backdropUrl;
            final isCurrent = v.key == _trailerKey && _isPlayingTrailer;

            return InkWell(
              onTap: () {
                _initTrailer(v.key);
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCurrent ? AppTheme.primaryRed.withValues(alpha: 0.15) : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent ? AppTheme.primaryRed : Colors.white.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    // 16:9 Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CachedNetworkImage(
                            imageUrl: thumb,
                            width: 120,
                            height: 68,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Container(width: 120, height: 68, color: Colors.black26),
                            errorWidget: (c, u, e) => Container(width: 120, height: 68, color: Colors.black26),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCurrent ? AppTheme.primaryRed : Colors.black.withValues(alpha: 0.7),
                              border: Border.all(color: Colors.white70, width: 1),
                            ),
                            child: Icon(
                              isCurrent ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & Tag
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.9),
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  v.type.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 8),
                                const Text(
                                  'Playing Now',
                                  style: TextStyle(
                                    color: AppTheme.primaryRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: displayList.length,
        ),
      ),
    );
  }

  Widget _buildRecommendationsSliver() {
    final recs = _detail?.recommendations ?? [];
    if (recs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No recommendations found', style: TextStyle(color: Colors.white54)),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return MediaCard(
              item: recs[index],
              forceType: widget.item.mediaType,
              onTap: () {
                _stopTrailer();
                Navigator.of(context).pop();
                DetailModal.show(context, recs[index].copyWith(mediaType: widget.item.mediaType));
              },
            );
          },
          childCount: recs.length,
        ),
      ),
    );
  }
}
