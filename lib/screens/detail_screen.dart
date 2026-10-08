import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_detail.dart';
import '../providers/download_provider.dart';
import '../providers/history_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/netflix_season_picker.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final int mediaId;
  final String mediaType; // 'movie' or 'tv'

  const DetailScreen({
    super.key,
    required this.mediaId,
    required this.mediaType,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ApiService _apiService = ApiService();
  MediaDetail? _detail;
  bool _isLoading = true;
  String? _error;

  int _selectedSeason = 1;
  List<TvEpisode> _episodes = [];
  bool _isLoadingEpisodes = false;

  int _activeTabIndex = 0; // 0: Episodes (tv) or Trailers, 1: Trailers/More Like This, etc.
  bool _isMuted = true;

  WebViewController? _trailerWebController;
  String? _activeTrailerKey;
  bool _showTrailerVideo = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  void _updateTrailerPlayer(String key) {
    if (key.isEmpty || (key == _activeTrailerKey && _trailerWebController != null)) return;
    _activeTrailerKey = key;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint('Trailer WebView error: ${error.description}');
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
    }

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #000000;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    iframe {
      width: 100%;
      height: 100%;
      border: 0;
      pointer-events: auto;
    }
  </style>
</head>
<body>
  <iframe
    id="trailer-frame"
    src="https://www.youtube-nocookie.com/embed/$key?autoplay=1&mute=${_isMuted ? 1 : 0}&controls=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&origin=https://www.youtube.com"
    allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
    allowfullscreen>
  </iframe>
</body>
</html>
''';

    controller.loadHtmlString(html, baseUrl: 'https://www.youtube.com');

    if (mounted) {
      setState(() {
        _trailerWebController = controller;
        _showTrailerVideo = true;
      });
    }
  }

  void _toggleTrailerMute() {
    setState(() => _isMuted = !_isMuted);
    _trailerWebController?.runJavaScript('''
      var iframe = document.getElementById("trailer-frame");
      if (iframe && iframe.contentWindow) {
        iframe.contentWindow.postMessage(JSON.stringify({
          "event": "command",
          "func": "${_isMuted ? "mute" : "unMute"}",
          "args": []
        }), "*");
      }
    ''');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isMuted ? 'Muted' : 'Sound On'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await _apiService.getDetails(widget.mediaType, widget.mediaId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });

        // Initialize trailer preview if available
        final trailer = detail.videos.where((v) =>
            v.site.toLowerCase() == 'youtube' &&
            v.type.toLowerCase() == 'trailer').firstOrNull ??
            detail.videos.where((v) => v.site.toLowerCase() == 'youtube').firstOrNull;
        if (trailer != null && trailer.key.isNotEmpty) {
          _updateTrailerPlayer(trailer.key);
        }

        if (widget.mediaType == 'tv' && detail.seasons.isNotEmpty) {
          _selectedSeason = detail.seasons.first.seasonNumber;
          _loadSeasonEpisodes(_selectedSeason);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSeasonEpisodes(int seasonNumber) async {
    setState(() => _isLoadingEpisodes = true);
    try {
      final episodes = await _apiService.getSeasonEpisodes(widget.mediaId, seasonNumber);
      if (mounted) {
        setState(() {
          _episodes = episodes;
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEpisodes = false);
      }
    }
  }

  void _playMedia({
    int season = 1,
    int episode = 1,
    String? localFilePath,
    String? episodeTitle,
  }) {
    if (_detail == null) return;
    // Pause trailer so it never plays concurrently in the background
    try {
      _trailerWebController?.runJavaScript(
        'var v = document.querySelector("video"); if (v) v.pause();',
      );
    } catch (_) {}

    final title = _detail!.mediaType == 'tv' && episodeTitle != null
        ? '${_detail!.title}: S${season}E$episode "$episodeTitle"'
        : _detail!.title;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => PlayerScreen(
          mediaId: _detail!.id,
          mediaTitle: title,
          mediaType: _detail!.mediaType,
          season: season,
          episode: episode,
          posterPath: _detail!.posterPath,
          backdropPath: _detail!.backdropPath,
          localFilePath: localFilePath,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _openSeasonPickerSheet(MediaDetail detail) async {
    final newSeason = await NetflixSeasonPicker.show(
      context: context,
      seasons: detail.seasons,
      selectedSeason: _selectedSeason,
    );
    if (newSeason != null && newSeason != _selectedSeason && mounted) {
      setState(() => _selectedSeason = newSeason);
      _loadSeasonEpisodes(newSeason);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryRed),
        ),
      );
    }

    if (_error != null || _detail == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.primaryRed, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to load media details', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadDetail,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final backdropUrl = ApiConstants.getImageUrl(detail.backdropPath ?? detail.posterPath, size: 'original');
    final watchlistProvider = context.watch<WatchlistProvider>();
    final downloadProvider = context.watch<DownloadProvider>();
    final inWatchlist = watchlistProvider.isInWatchlist(detail.id);

    final isTv = detail.mediaType == 'tv';
    final tabs = isTv
        ? ['Episodes', 'Trailers & More', 'More Like This']
        : ['Trailers & More', 'More Like This'];

    final totalEpisodes = detail.seasons.fold<int>(0, (sum, s) => sum + s.episodeCount);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Collapsible Trailer / Video Header (Screenshots 1 & 4)
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Active Trailer / Backdrop View
                  if (_trailerWebController != null && _showTrailerVideo)
                    Positioned.fill(
                      child: WebViewWidget(controller: _trailerWebController!),
                    )
                  else if (backdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(color: AppTheme.surfaceVariant),
                      errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                    )
                  else
                    Container(color: AppTheme.surfaceVariant),

                  // Gradient (IgnorePointer ensures touches reach YouTube video player)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.4, 0.85, 1.0],
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                              AppTheme.background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Center circular play button overlay (if video is hidden or fallback)
                  if (!_showTrailerVideo || _trailerWebController == null)
                    Center(
                      child: GestureDetector(
                        onTap: () => _playMedia(season: _selectedSeason, episode: 1),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.65),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                        ),
                      ),
                    ),

                  // Sound Mute / Unmute Button in bottom right corner (Screenshot 4)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: GestureDetector(
                      onTap: _toggleTrailerMute,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  // Red progress line at bottom of trailer preview (Screenshot 4)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 2.5,
                      color: AppTheme.primaryRed,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content body matching Screenshots 1, 2, 4
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Red Brand Logo Badge (Screenshot 2 & 4)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'VOIDFLIX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Big Title (Screenshot 2 & 4)
                  Text(
                    detail.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Metadata Row: Year • Rating • Episodes • HD • Audio (Screenshot 2 & 4)
                  Row(
                    children: [
                      if (detail.releaseDate != null && detail.releaseDate!.isNotEmpty) ...[
                        Text(
                          detail.releaseDate!.split('-').first,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '13+',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isTv
                            ? (totalEpisodes > 0 ? '$totalEpisodes Episodes' : '16 Episodes')
                            : (detail.runtime != null && detail.runtime! > 0
                                ? (detail.runtime! >= 60
                                    ? '${detail.runtime! ~/ 60}h ${detail.runtime! % 60}m'
                                    : '${detail.runtime}m')
                                : 'Film'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white60, width: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'HD',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chat_bubble_outline, color: Colors.white60, size: 14),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Subtitle: "Watch all of Season 1 now" (Screenshot 2 & 4)
                  Text(
                    isTv ? 'Watch all of Season $_selectedSeason now' : (detail.tagline ?? 'Now streaming on Voidflix'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Full-width White Button: ▶ Play (Screenshot 2 & 4)
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final saved = context.read<HistoryProvider>().getProgress(detail.id);
                        final s = saved?.season ?? _selectedSeason;
                        final e = saved?.episode ?? 1;
                        final offlineId = isTv
                            ? DownloadProvider.generateId('tv', detail.id, season: s, episode: e)
                            : DownloadProvider.generateId('movie', detail.id);
                        final downloadProvider = context.read<DownloadProvider>();
                        final offlineItem = downloadProvider.getItem(offlineId);
                        final localFile = offlineItem?.status == 'completed' ? offlineItem?.localFilePath : null;

                        _playMedia(
                          season: s,
                          episode: e,
                          localFilePath: localFile,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.play_arrow, color: Colors.black, size: 26),
                      label: const Text(
                        'Play',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Full-width Dark Button: Download / Downloading / Downloaded
                  Consumer<DownloadProvider>(
                    builder: (btnCtx, downloadProvider, _) {
                      final firstEp = _episodes.isNotEmpty ? _episodes.first : null;
                      final targetEpNum = firstEp?.episodeNumber ?? 1;
                      final mainDownloadId = isTv
                          ? DownloadProvider.generateId('tv', detail.id, season: _selectedSeason, episode: targetEpNum)
                          : DownloadProvider.generateId('movie', detail.id);
                      final isMainDownloaded = downloadProvider.isDownloaded(mainDownloadId);
                      final isMainDownloading = downloadProvider.isDownloading(mainDownloadId);
                      final mainProgress = downloadProvider.getProgress(mainDownloadId);
                      final mainItem = downloadProvider.getItem(mainDownloadId);

                      if (isMainDownloading) {
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                value: mainProgress > 0 ? mainProgress : null,
                                strokeWidth: 2.2,
                                color: AppTheme.primaryRed,
                              ),
                            ),
                            label: Text(
                              'Downloading ${(mainProgress * 100).toInt()}%',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        );
                      }

                      if (isMainDownloaded) {
                        final mb = mainItem != null
                            ? '${(mainItem.fileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
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
                                localFilePath: mainItem?.localFilePath,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF262626),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                            downloadProvider.startDownload(
                              mediaId: detail.id,
                              title: detail.title,
                              mediaType: widget.mediaType,
                              season: _selectedSeason,
                              episode: targetEpNum,
                              episodeTitle: firstEp?.name,
                              posterPath: detail.posterPath,
                              backdropPath: detail.backdropPath,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Started download for ${detail.title}'),
                                backgroundColor: const Color(0xFFE50914),
                                action: SnackBarAction(
                                  label: 'View',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF262626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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

                  // Episode Spotlight (for TV Shows): S1:E1 "Episode 1" (Screenshot 2 & 4)
                  if (isTv) ...[
                    Text(
                      'S$_selectedSeason:E1 "${_episodes.isNotEmpty ? _episodes.first.name : 'Episode 1'}"',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Overview / Synopsis
                  Text(
                    detail.overview.isNotEmpty ? detail.overview : 'No overview available.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Starring & Creators (Screenshot 2 & 4)
                  if (detail.cast.isNotEmpty) ...[
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                        children: [
                          const TextSpan(text: 'Starring: ', style: TextStyle(color: Colors.white54)),
                          TextSpan(text: '${detail.cast.take(4).map((c) => c.name).join(', ')}... more'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                      children: [
                        TextSpan(
                          text: isTv ? 'Creators: ' : 'Director: ',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        TextSpan(
                          text: isTv ? 'Voidflix Studios, TMDB Creators' : 'Featured Director',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 4-Action Bar: [+ My List] [👍 Rate] [🔗 Share] [⤓ Download Season 1] (Screenshot 2 & 4)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // My List
                      GestureDetector(
                        onTap: () => watchlistProvider.toggleWatchlist(detail.toMediaItem()),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(inWatchlist ? Icons.check : Icons.add, color: Colors.white, size: 24),
                            const SizedBox(height: 5),
                            Text(
                              inWatchlist ? 'In List' : 'My List',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // Rate
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Rated! Added to your likes.')),
                          );
                        },
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.thumb_up_alt_outlined, color: Colors.white, size: 24),
                            SizedBox(height: 5),
                            Text('Rate', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),

                      // Share
                      GestureDetector(
                        onTap: () {
                          SharePlus.instance.share(
                            ShareParams(
                              text: 'Check out "${detail.title}" on Voidflix!\nhttps://voidflix.org/${detail.mediaType}/${detail.id}',
                              subject: 'Watch ${detail.title} on Voidflix',
                            ),
                          );
                        },
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.share_outlined, color: Colors.white, size: 24),
                            SizedBox(height: 5),
                            Text('Share', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),

                      // Download Season (Batch download like in web DetailModal.tsx)
                      GestureDetector(
                        onTap: () {
                          if (!isTv) {
                            downloadProvider.startDownload(
                              mediaId: detail.id,
                              title: detail.title,
                              mediaType: 'movie',
                              posterPath: detail.posterPath,
                              backdropPath: detail.backdropPath,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Downloading ${detail.title}...'),
                                backgroundColor: const Color(0xFFE50914),
                              ),
                            );
                            return;
                          }

                          if (_episodes.isEmpty) {
                            downloadProvider.startDownload(
                              mediaId: detail.id,
                              title: detail.title,
                              mediaType: 'tv',
                              season: _selectedSeason,
                              episode: 1,
                              posterPath: detail.posterPath,
                              backdropPath: detail.backdropPath,
                            );
                          } else {
                            for (final ep in _episodes) {
                              downloadProvider.startDownload(
                                mediaId: detail.id,
                                title: detail.title,
                                mediaType: 'tv',
                                season: _selectedSeason,
                                episode: ep.episodeNumber,
                                episodeTitle: ep.name,
                                posterPath: detail.posterPath,
                                backdropPath: detail.backdropPath,
                              );
                            }
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Downloading Season $_selectedSeason (${_episodes.length} episodes)...'),
                              backgroundColor: const Color(0xFFE50914),
                              action: SnackBarAction(
                                label: 'View',
                                textColor: Colors.white,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.file_download_outlined, color: Colors.white, size: 24),
                            const SizedBox(height: 5),
                            Text(
                              isTv ? 'Download\nSeason $_selectedSeason' : 'Download',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Divider before Tabs
                  const Divider(color: Colors.white12, thickness: 1),

                  // Clean Tabs with Red Indicator: [Episodes] [Trailers & More] [More Like This] (Screenshot 2 & 4)
                  Row(
                    children: List.generate(tabs.length, (idx) {
                      final isSel = idx == _activeTabIndex;
                      final label = tabs[idx];
                      return GestureDetector(
                        onTap: () => setState(() => _activeTabIndex = idx),
                        child: Container(
                          padding: const EdgeInsets.only(right: 22, top: 8, bottom: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: isSel ? AppTheme.primaryRed : Colors.transparent,
                                width: 3.5,
                              ),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white60,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  // TAB CONTENT
                  if (isTv && _activeTabIndex == 0) ...[
                    // EPISODES TAB
                    // Season Selector Dropdown Pill + Info (Matching Web flowflix-web/src/components/DetailModal.tsx)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => _openSeasonPickerSheet(detail),
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
                            onTap: () {
                              final sObj = detail.seasons.firstWhere(
                                (s) => s.seasonNumber == _selectedSeason,
                                orElse: () => detail.seasons.first,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    sObj.name.isNotEmpty
                                        ? '${sObj.name} of ${detail.title}'
                                        : 'Season $_selectedSeason of ${detail.title}',
                                  ),
                                  backgroundColor: const Color(0xFF262626),
                                ),
                              );
                            },
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
                    const SizedBox(height: 14),

                    // Episode List matching Screenshot 2 & 4
                    if (_isLoadingEpisodes)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(color: AppTheme.primaryRed),
                        ),
                      )
                    else if (_episodes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No episodes found for this season.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _episodes.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 18),
                        itemBuilder: (c, idx) {
                          final ep = _episodes[idx];
                          final stillUrl = ApiConstants.getImageUrl(ep.stillPath ?? detail.backdropPath, size: 'w300');
                          final epId = DownloadProvider.generateId(
                            'tv',
                            detail.id,
                            season: _selectedSeason,
                            episode: ep.episodeNumber,
                          );
                          final isEpDownloaded = downloadProvider.isDownloaded(epId);
                          final isEpDownloading = downloadProvider.isDownloading(epId);
                          final epProgress = downloadProvider.getProgress(epId);
                          final epDownloadedItem = downloadProvider.getItem(epId);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Episode Row: Thumbnail + Title/Duration + Download Icon (Screenshot 2 & 4)
                              Row(
                                children: [
                                  // 16:9 Thumbnail with Play Overlay & Red Progress Bar
                                  GestureDetector(
                                    onTap: () => _playMedia(
                                      season: _selectedSeason,
                                      episode: ep.episodeNumber,
                                      episodeTitle: ep.name,
                                      localFilePath: isEpDownloaded ? epDownloadedItem?.localFilePath : null,
                                    ),
                                    child: Container(
                                      width: 125,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color: AppTheme.cardColor,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (stillUrl.isNotEmpty)
                                            CachedNetworkImage(
                                              imageUrl: stillUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (c, u) => Container(color: AppTheme.surfaceVariant),
                                              errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                                            )
                                          else
                                            Container(color: AppTheme.surfaceVariant),

                                          // Dark overlay
                                          Container(color: Colors.black.withValues(alpha: 0.25)),

                                          // Center Play Button
                                          Center(
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black.withValues(alpha: 0.65),
                                                border: Border.all(color: Colors.white, width: 1.5),
                                              ),
                                              child: const Icon(
                                                Icons.play_arrow,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                          ),

                                          // Red progress line
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              height: 2.5,
                                              color: AppTheme.primaryRed,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Episode Title & Runtime
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
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${ep.runtime > 0 ? ep.runtime : 28}m',
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Download Button / Status (Screenshot 2 & 4)
                                  if (isEpDownloading)
                                    SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            value: epProgress > 0 ? epProgress : null,
                                            strokeWidth: 2.5,
                                            color: AppTheme.primaryRed,
                                            backgroundColor: Colors.white12,
                                          ),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                                            tooltip: 'Cancel Download',
                                            onPressed: () {
                                              downloadProvider.cancelDownload(epId);
                                            },
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isEpDownloaded)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_done_rounded,
                                        color: AppTheme.primaryRed,
                                        size: 24,
                                      ),
                                      tooltip: 'Downloaded - Play offline',
                                      onPressed: () {
                                        _playMedia(
                                          season: _selectedSeason,
                                          episode: ep.episodeNumber,
                                          episodeTitle: ep.name,
                                          localFilePath: epDownloadedItem?.localFilePath,
                                        );
                                      },
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(
                                        Icons.file_download_outlined,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      tooltip: 'Download Episode',
                                      onPressed: () {
                                        downloadProvider.startDownload(
                                          mediaId: detail.id,
                                          title: detail.title,
                                          mediaType: 'tv',
                                          season: _selectedSeason,
                                          episode: ep.episodeNumber,
                                          episodeTitle: ep.name,
                                          posterPath: detail.posterPath,
                                          backdropPath: detail.backdropPath,
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Downloading S$_selectedSeason:E${ep.episodeNumber} - ${ep.name}'),
                                            backgroundColor: const Color(0xFFE50914),
                                            duration: const Duration(seconds: 2),
                                            action: SnackBarAction(
                                              label: 'View',
                                              textColor: Colors.white,
                                              onPressed: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Episode Overview Synopsis
                              Text(
                                ep.overview.isNotEmpty ? ep.overview : 'Episode ${ep.episodeNumber}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ] else if ((!isTv && _activeTabIndex == 0) || (isTv && _activeTabIndex == 1)) ...[
                    // TRAILERS & MORE TAB
                    if (detail.videos.isEmpty && detail.trailerKey == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No trailers available for this title.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: detail.videos.isNotEmpty ? detail.videos.length : 1,
                        separatorBuilder: (c, i) => const SizedBox(height: 16),
                        itemBuilder: (c, idx) {
                          final v = detail.videos.isNotEmpty ? detail.videos[idx] : null;
                          final thumb = v?.youtubeThumbnailUrl ?? backdropUrl;
                          final trailerName = v?.name ?? 'Official Trailer';

                          return GestureDetector(
                            onTap: () {
                              if (v != null && v.key.isNotEmpty) {
                                _updateTrailerPlayer(v.key);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Playing: ${v.name}'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                _playMedia(season: _selectedSeason, episode: 1);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 190,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: AppTheme.cardColor,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: thumb,
                                        fit: BoxFit.cover,
                                        errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                                      ),
                                      Container(color: Colors.black.withValues(alpha: 0.3)),
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.black.withValues(alpha: 0.7),
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  trailerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ] else ...[
                    // MORE LIKE THIS TAB (3-column grid)
                    if (detail.recommendations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No similar titles found.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: detail.recommendations.length,
                        itemBuilder: (c, idx) {
                          final rec = detail.recommendations[idx];
                          final recPoster = ApiConstants.getImageUrl(rec.posterPath, size: 'w342');

                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DetailScreen(
                                    mediaId: rec.id,
                                    mediaType: rec.mediaType,
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: recPoster.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: recPoster,
                                      fit: BoxFit.cover,
                                      errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                                    )
                                  : Container(color: AppTheme.surfaceVariant),
                            ),
                          );
                        },
                      ),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
