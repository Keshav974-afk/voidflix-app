import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_detail.dart';
import '../models/server_config.dart';
import '../models/watch_progress.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';

class PlayerScreen extends StatefulWidget {
  final int mediaId;
  final String mediaTitle;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? posterPath;
  final String? backdropPath;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.mediaTitle,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    this.posterPath,
    this.backdropPath,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late WebViewController _webViewController;
  late int _currentSeason;
  late int _currentEpisode;
  late int _selectedServerIndex;
  bool _isLoading = true;
  bool _isLandscape = true;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isExiting = false;

  // Autoplay Next Episode system
  bool _showAutoplayCard = false;
  int _autoplayCountdown = 5;
  Timer? _autoplayTimer;

  // TV show series data
  List<TvSeason> _seasons = [];
  List<TvEpisode> _episodes = [];
  bool _isLoadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _selectedServerIndex = context.read<ProfileProvider>().selectedServerIndex;

    // Always open in full screen landscape
    _isLandscape = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initWebView();
    _recordWatchProgress();

    if (widget.mediaType == 'tv') {
      _fetchTvDetailsAndEpisodes();
    }

    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _autoplayTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _handleSmoothBack() async {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _cancelAutoplayTimer();
    _hideControlsTimer?.cancel();

    // 1. Smoothly restore portrait orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 2. Brief buffer for Android display compositor to begin smooth rotation
    await Future.delayed(const Duration(milliseconds: 140));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isLandscape) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  Future<void> _fetchTvDetailsAndEpisodes() async {
    try {
      final detail = await ApiService().getDetails('tv', widget.mediaId);
      if (mounted) {
        setState(() {
          _seasons = detail.seasons;
        });
        _loadEpisodesForSeason(_currentSeason);
      }
    } catch (e) {
      debugPrint('Error fetching seasons for player: $e');
      _loadEpisodesForSeason(_currentSeason);
    }
  }

  Future<void> _loadEpisodesForSeason(int seasonNum) async {
    if (widget.mediaType != 'tv') return;
    setState(() => _isLoadingEpisodes = true);
    try {
      final eps = await ApiService().getSeasonEpisodes(widget.mediaId, seasonNum);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoadingEpisodes = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading episodes for season $seasonNum: $e');
      if (mounted) {
        setState(() => _isLoadingEpisodes = false);
      }
    }
  }

  void _recordWatchProgress() {
    final progress = WatchProgress(
      id: widget.mediaId,
      title: widget.mediaTitle,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
      mediaType: widget.mediaType,
      season: _currentSeason,
      episode: _currentEpisode,
      progress: 0.1,
      lastWatched: DateTime.now(),
    );
    context.read<HistoryProvider>().saveProgress(progress);
  }

  String _buildCurrentUrl() {
    final server = ServerConfig.servers[_selectedServerIndex];
    return ServerConfig.getEmbedUrl(
      server: server,
      type: widget.mediaType,
      id: widget.mediaId,
      season: _currentSeason,
      episode: _currentEpisode,
    );
  }

  static const String _antiPopupScript = '''
(function() {
  try {
    // 1. Completely neutralize window.open popups
    window.open = function() {
      console.log('VOIDFLIX: Neutralized popup window.open');
      return null;
    };
    Object.defineProperty(window, 'open', {
      value: function() { return null; },
      writable: false,
      configurable: false
    });
  } catch(e) {}

  try {
    // 2. Suppress dialogue spams
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
  } catch(e) {}

  // 3. Neutralize target="_blank" so clicks never spawn new windows/tabs
  function disarmAnchors() {
    try {
      var links = document.querySelectorAll('a[target="_blank"]');
      for (var i = 0; i < links.length; i++) {
        links[i].removeAttribute('target');
      }
    } catch(e) {}
  }

  // 4. Remove transparent click-hijacking overlays
  function neutralizeClickHijackers() {
    try {
      var overlays = document.querySelectorAll('div, span, a');
      for (var i = 0; i < overlays.length; i++) {
        var el = overlays[i];
        if (el.tagName === 'A' && el.getAttribute('href')) {
          var href = el.getAttribute('href');
          if (href && !href.includes(window.location.hostname)) {
            var rect = el.getBoundingClientRect();
            if (rect.width > 220 && rect.height > 150) {
              el.remove();
            }
          }
        }
      }
    } catch(e) {}
  }

  // 5. Video ended detection for Autoplay Next Episode
  function hookVideoAutoplay() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (!v._vfAutoplayHooked) {
          v._vfAutoplayHooked = true;
          v.addEventListener('ended', function() {
            if (window.VoidflixBridge) {
              window.VoidflixBridge.postMessage('video_ended');
            }
          });
          v.addEventListener('timeupdate', function() {
            if (v.duration && v.duration > 15 && v.currentTime >= v.duration - 2) {
              if (!v._vfEndedPosted) {
                v._vfEndedPosted = true;
                if (window.VoidflixBridge) {
                  window.VoidflixBridge.postMessage('video_ended');
                }
              }
            }
          });
        }
      }
    } catch(e) {}
  }

  disarmAnchors();
  hookVideoAutoplay();
  setInterval(disarmAnchors, 1200);
  setInterval(neutralizeClickHijackers, 2000);
  setInterval(hookVideoAutoplay, 1500);
})();
''';

  bool _isAllowedUrl(String url) {
    final lowerUrl = url.toLowerCase();

    // Block non-HTTP application schemes and external redirects
    if (lowerUrl.startsWith('intent:') ||
        lowerUrl.startsWith('market:') ||
        lowerUrl.startsWith('vnd:') ||
        lowerUrl.startsWith('whatsapp:') ||
        lowerUrl.startsWith('tg:') ||
        lowerUrl.startsWith('mailto:') ||
        lowerUrl.startsWith('tel:')) {
      return false;
    }

    // Allow data, blob, and about:blank internal frames
    if (lowerUrl.startsWith('blob:') ||
        lowerUrl.startsWith('data:') ||
        lowerUrl == 'about:blank') {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();

    // Allow the current stream origin
    final currentUri = Uri.tryParse(_buildCurrentUrl());
    if (currentUri != null && (host == currentUri.host || url == _buildCurrentUrl())) {
      return true;
    }

    // Whitelist legitimate streaming servers and CDNs
    const allowedKeywords = [
      'vidlink.pro',
      'videasy.net',
      'vixsrc.to',
      'vidrock.ru',
      'vidsrc.me',
      'vidsrc.cc',
      'vidsrc.to',
      'vidsrc.in',
      'vidsrc.pro',
      'multiembed.mov',
      '2embed',
      'superembed',
      'autoembed',
      'smashystream',
      'embed.su',
      'vidplay',
      'rabbitstream',
      'megacloud',
      'filemoon',
      'streamwish',
      'dood',
      'streamtape',
      'mp4upload',
      'mixdrop',
      'cloudstream',
      'themoviedb.org',
      'tmdb.org',
      'google',
      'gstatic',
      'cloudflare',
    ];

    for (final kw in allowedKeywords) {
      if (host.contains(kw)) return true;
    }

    // Allow media files
    if (lowerUrl.contains('.m3u8') || lowerUrl.contains('.mp4') || lowerUrl.contains('.ts')) {
      return true;
    }

    return false;
  }

  void _initWebView() {
    final url = _buildCurrentUrl();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36')
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
            _webViewController.runJavaScript(_antiPopupScript);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _webViewController.runJavaScript(_antiPopupScript);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_isAllowedUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            debugPrint('VOIDFLIX: Blocked popup/ad redirect: ${request.url}');
            return NavigationDecision.prevent;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'VoidflixBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          if (msg.message == 'video_ended' && mounted && widget.mediaType == 'tv') {
            _triggerAutoplayNext();
          }
        },
      )
      ..loadRequest(Uri.parse(url));
  }

  void _reloadWithCurrentSettings() {
    final url = _buildCurrentUrl();
    _webViewController.loadRequest(Uri.parse(url));
    _recordWatchProgress();
    setState(() {});
  }

  void _toggleOrientation() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() {
        _isLandscape = false;
        _showControls = true;
      });
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      setState(() {
        _isLandscape = true;
        _showControls = true;
      });
      _startHideControlsTimer();
    }
  }

  void _goToEpisode(int episodeNum) {
    _cancelAutoplayTimer();
    setState(() {
      _currentEpisode = episodeNum;
    });
    _reloadWithCurrentSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing Season $_currentSeason • Episode $_currentEpisode'),
        backgroundColor: AppTheme.surfaceVariant,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _nextEpisode() {
    if (widget.mediaType != 'tv') return;
    _cancelAutoplayTimer();
    if (_episodes.isNotEmpty && _currentEpisode < _episodes.length) {
      _goToEpisode(_currentEpisode + 1);
    } else {
      // Check if there is another season available
      final currentSeasonIndex = _seasons.indexWhere((s) => s.seasonNumber == _currentSeason);
      if (currentSeasonIndex != -1 && currentSeasonIndex + 1 < _seasons.length) {
        final nextSeason = _seasons[currentSeasonIndex + 1];
        setState(() {
          _currentSeason = nextSeason.seasonNumber;
          _currentEpisode = 1;
        });
        _loadEpisodesForSeason(_currentSeason);
        _reloadWithCurrentSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Starting Season $_currentSeason • Episode 1'),
            backgroundColor: AppTheme.surfaceVariant,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        _goToEpisode(_currentEpisode + 1);
      }
    }
  }

  void _triggerAutoplayNext() {
    if (widget.mediaType != 'tv' || !mounted || _showAutoplayCard) return;
    _cancelAutoplayTimer();

    setState(() {
      _showAutoplayCard = true;
      _autoplayCountdown = 5;
    });

    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoplayCountdown > 1) {
        setState(() => _autoplayCountdown--);
      } else {
        timer.cancel();
        setState(() => _showAutoplayCard = false);
        _nextEpisode();
      }
    });
  }

  void _cancelAutoplayTimer() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (_showAutoplayCard && mounted) {
      setState(() => _showAutoplayCard = false);
    }
  }

  Widget _buildAutoplayNextCard() {
    final nextNum = _currentEpisode + 1;
    final nextEp = _episodes.firstWhere(
      (e) => e.episodeNumber == nextNum,
      orElse: () => TvEpisode(episodeNumber: nextNum, name: 'Episode $nextNum', overview: ''),
    );

    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEE16161E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$_autoplayCountdown',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NEXT EPISODE IN',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _cancelAutoplayTimer,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white60, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (nextEp.stillPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 70,
                    height: 42,
                    child: CachedNetworkImage(
                      imageUrl: ApiService.getImageUrl(nextEp.stillPath, size: 'w300'),
                      fit: BoxFit.cover,
                      errorWidget: (c, u, e) => Container(color: Colors.black38),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S$_currentSeason E$nextNum • ${nextEp.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nextEp.overview.isNotEmpty ? nextEp.overview : 'Playing next episode automatically',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    _cancelAutoplayTimer();
                    _nextEpisode();
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _cancelAutoplayTimer,
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _prevEpisode() {
    if (widget.mediaType != 'tv' || _currentEpisode <= 1) return;
    _goToEpisode(_currentEpisode - 1);
  }

  void _openEpisodesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Sheet Header & Handle
                    Container(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                    // Season Selector Dropdown
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_seasons.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _currentSeason,
                                  dropdownColor: AppTheme.surfaceVariant,
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  items: _seasons.map((s) {
                                    return DropdownMenuItem<int>(
                                      value: s.seasonNumber,
                                      child: Text(s.name.isEmpty ? 'Season ${s.seasonNumber}' : s.name),
                                    );
                                  }).toList(),
                                  onChanged: (newSeason) {
                                    if (newSeason != null && newSeason != _currentSeason) {
                                      setState(() {
                                        _currentSeason = newSeason;
                                        _currentEpisode = 1;
                                      });
                                      setSheetState(() {});
                                      _loadEpisodesForSeason(newSeason).then((_) {
                                        setSheetState(() {});
                                      });
                                    }
                                  },
                                ),
                              ),
                            )
                          else
                            Text(
                              'Season $_currentSeason Episodes',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),

                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: AppTheme.border, height: 1),

                    // Episode List
                    Expanded(
                      child: _isLoadingEpisodes
                          ? const Center(
                              child: CircularProgressIndicator(color: AppTheme.primaryRed),
                            )
                          : _episodes.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No episodes found for this season',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  itemCount: _episodes.length,
                                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final ep = _episodes[index];
                                    final isPlaying = ep.episodeNumber == _currentEpisode;

                                    return InkWell(
                                      onTap: () {
                                        Navigator.of(ctx).pop();
                                        _goToEpisode(ep.episodeNumber);
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isPlaying
                                              ? AppTheme.primaryRed.withValues(alpha: 0.15)
                                              : AppTheme.cardColor,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isPlaying ? AppTheme.primaryRed : Colors.transparent,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Episode Still Thumbnail
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: SizedBox(
                                                width: 110,
                                                height: 65,
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    if (ep.stillPath != null)
                                                      CachedNetworkImage(
                                                        imageUrl: ApiService.getImageUrl(ep.stillPath, size: 'w300'),
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context, url, error) => Container(
                                                          color: Colors.black26,
                                                          child: const Icon(Icons.movie, color: Colors.white38),
                                                        ),
                                                      )
                                                    else
                                                      Container(
                                                        color: Colors.black38,
                                                        child: const Icon(Icons.movie, color: Colors.white38),
                                                      ),
                                                    if (isPlaying)
                                                      Container(
                                                        color: Colors.black45,
                                                        child: const Center(
                                                          child: Icon(Icons.play_circle_fill, color: AppTheme.primaryRed, size: 28),
                                                        ),
                                                      ),
                                                    if (ep.runtime > 0)
                                                      Positioned(
                                                        bottom: 4,
                                                        right: 4,
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withValues(alpha: 0.75),
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                          child: Text(
                                                            '${ep.runtime}m',
                                                            style: const TextStyle(fontSize: 10, color: Colors.white),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Episode Info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        '${ep.episodeNumber}. ',
                                                        style: TextStyle(
                                                          color: isPlaying ? AppTheme.primaryRed : Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          ep.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            color: isPlaying ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  if (ep.overview.isNotEmpty)
                                                    Text(
                                                      ep.overview,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  if (isPlaying) ...[
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      'PLAYING NOW',
                                                      style: TextStyle(
                                                        color: AppTheme.primaryRed,
                                                        fontWeight: FontWeight.w900,
                                                        fontSize: 10,
                                                        letterSpacing: 1.0,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _openServerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Stream Server',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTheme.border),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ServerConfig.servers.length,
                  itemBuilder: (c, idx) {
                    final s = ServerConfig.servers[idx];
                    final isSelected = idx == _selectedServerIndex;
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? AppTheme.primaryRed : Colors.white54,
                      ),
                      title: Row(
                        children: [
                          Text(
                            s.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (idx == 0 || idx == 1) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.matchGreen.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'RECOMMENDED',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppTheme.matchGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        s.description,
                        style: const TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedServerIndex = idx;
                        });
                        context.read<ProfileProvider>().setSelectedServer(idx);
                        Navigator.pop(ctx);
                        _reloadWithCurrentSettings();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentServer = ServerConfig.servers[_selectedServerIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleSmoothBack();
        }
      },
      child: AnimatedOpacity(
        opacity: _isExiting ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            top: !_isLandscape,
            bottom: !_isLandscape,
            child: Column(
              children: [
                // Top Controls Bar (Portrait mode)
                if (!_isLandscape)
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: _handleSmoothBack,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.mediaTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.mediaType == 'tv')
                                Text(
                                  'Season $_currentSeason • Episode $_currentEpisode',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Reload stream button
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          tooltip: 'Reload Stream',
                          onPressed: _reloadWithCurrentSettings,
                        ),
                        // Rotate screen button
                        IconButton(
                          icon: const Icon(Icons.fullscreen, color: Colors.white, size: 28),
                          tooltip: 'Fullscreen',
                          onPressed: _toggleOrientation,
                        ),
                      ],
                    ),
                  ),

                // Video Player Area with Landscape Overlay
                Expanded(
                  child: GestureDetector(
                    onTap: _isLandscape ? _toggleControls : null,
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      children: [
                        WebViewWidget(controller: _webViewController),

                        // Loading indicator
                        if (_isLoading)
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: AppTheme.primaryRed),
                                  SizedBox(height: 16),
                                  Text(
                                    'Connecting to stream...',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Landscape Fullscreen Controls Overlay
                        if (_isLandscape && _showControls)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.8),
                                    Colors.transparent,
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.85),
                                  ],
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Top Bar Landscape
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                                          onPressed: _handleSmoothBack,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                widget.mediaTitle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (widget.mediaType == 'tv')
                                                Text(
                                                  'Season $_currentSeason • Episode $_currentEpisode',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.refresh, color: Colors.white),
                                          tooltip: 'Reload',
                                          onPressed: _reloadWithCurrentSettings,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 28),
                                          tooltip: 'Exit Fullscreen',
                                          onPressed: _toggleOrientation,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Bottom Bar Landscape
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Row(
                                      children: [
                                        // Server Switcher
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Colors.white38),
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: _openServerPicker,
                                          icon: const Icon(Icons.dns, size: 16, color: AppTheme.primaryRed),
                                          label: Text(currentServer.name),
                                        ),
                                        const SizedBox(width: 12),

                                        // Episode Picker Button (TV)
                                        if (widget.mediaType == 'tv')
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.primaryRed,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: _openEpisodesSheet,
                                            icon: const Icon(Icons.video_library_rounded, size: 16),
                                            label: const Text('Episodes'),
                                          ),

                                        const Spacer(),

                                        // Prev & Next Buttons (TV)
                                        if (widget.mediaType == 'tv') ...[
                                          IconButton(
                                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 30),
                                            tooltip: 'Previous Episode',
                                            onPressed: _currentEpisode > 1 ? _prevEpisode : null,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                                            tooltip: 'Next Episode',
                                            onPressed: _nextEpisode,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Autoplay Next Episode Countdown Overlay Card
                        if (_showAutoplayCard)
                          Positioned(
                            bottom: _isLandscape ? 24 : 16,
                            right: 16,
                            child: _buildAutoplayNextCard(),
                          ),
                      ],
                    ),
                  ),
                ),

                // Bottom Action Bar (Portrait mode)
                if (!_isLandscape)
                  Container(
                    color: AppTheme.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        // Server Picker Button
                        OutlinedButton.icon(
                          onPressed: _openServerPicker,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.border),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.dns, size: 16, color: AppTheme.primaryRed),
                          label: Text(
                            currentServer.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),

                        const Spacer(),

                        // TV Episode Quick Controls & Episodes Sheet Button
                        if (widget.mediaType == 'tv') ...[
                          // Episodes Button
                          OutlinedButton.icon(
                            onPressed: _openEpisodesSheet,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.border),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(Icons.video_library_rounded, size: 16, color: Colors.white70),
                            label: const Text(
                              'Episodes',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),

                          IconButton(
                            icon: const Icon(Icons.skip_previous, color: Colors.white),
                            tooltip: 'Previous Episode',
                            onPressed: _currentEpisode > 1 ? _prevEpisode : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(
                              'E$_currentEpisode',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, color: Colors.white),
                            tooltip: 'Next Episode',
                            onPressed: _nextEpisode,
                          ),
                        ],
                      ],
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
