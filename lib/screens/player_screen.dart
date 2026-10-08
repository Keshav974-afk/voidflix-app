import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/stream_extractor.dart';
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
  // Navigation & playback state
  late int _currentSeason;
  late int _currentEpisode;
  late int _selectedServerIndex;
  bool _isLandscape = true;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isExiting = false;

  // Native Video Player state
  VideoPlayerController? _videoPlayerController;
  bool _isNativeMode = true;
  bool _isExtracting = true;
  List<ExtractedStream> _directStreams = [];
  int _selectedStreamIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isDraggingSeekbar = false;
  double _dragPositionSec = 0.0;

  // Web fallback player state
  WebViewController? _webViewController;
  bool _isWebViewLoading = true;

  // General loading & errors
  bool _isLoading = true;

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

    // Always start in full screen landscape
    _isLandscape = true;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadMedia();
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
    _disposeVideoController();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _disposeVideoController() {
    final controller = _videoPlayerController;
    _videoPlayerController = null;
    controller?.removeListener(_videoPlayerListener);
    controller?.dispose();
  }

  // ---------------------------------------------------------------------------
  // Media Loading Pipeline
  // ---------------------------------------------------------------------------

  Future<void> _loadMedia() async {
    _cancelAutoplayTimer();
    final server = ServerConfig.servers[_selectedServerIndex];

    if (server.isDirectPlay) {
      await _loadDirectStream();
    } else {
      _loadWebEmbed();
    }
  }

  Future<void> _loadDirectStream() async {
    setState(() {
      _isNativeMode = true;
      _isExtracting = true;
      _isLoading = true;
    });

    _disposeVideoController();

    try {
      final streams = await StreamExtractor.extractAll(
        type: widget.mediaType,
        tmdbId: widget.mediaId,
        season: _currentSeason,
        episode: _currentEpisode,
      );

      if (!mounted) return;

      if (streams.isNotEmpty) {
        _directStreams = streams;
        _selectedStreamIndex = 0;
        await _initNativePlayer(streams[0]);
      } else {
        // No direct streams returned; fall back smoothly to web embed
        debugPrint('Direct extraction returned 0 streams. Falling back to web embed.');
        _switchToEmbedFallback();
      }
    } catch (e) {
      debugPrint('Direct extraction error: $e');
      if (mounted) {
        _switchToEmbedFallback();
      }
    }
  }

  Future<void> _initNativePlayer(ExtractedStream stream) async {
    _disposeVideoController();

    setState(() {
      _isExtracting = false;
      _isLoading = true;
      _isNativeMode = true;
    });

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(stream.url),
        httpHeaders: stream.headers,
      );

      _videoPlayerController = controller;
      await controller.initialize();

      if (!mounted) return;

      controller.addListener(_videoPlayerListener);
      await controller.play();

      setState(() {
        _isLoading = false;
        _isPlaying = true;
        _totalDuration = controller.value.duration;
        _currentPosition = controller.value.position;
      });
      _startHideControlsTimer();
    } catch (e) {
      debugPrint('Native player initialization failed for ${stream.sourceName}: $e');
      // If another direct stream exists, try next stream in list
      if (_selectedStreamIndex + 1 < _directStreams.length) {
        _selectedStreamIndex++;
        await _initNativePlayer(_directStreams[_selectedStreamIndex]);
      } else {
        // Fall back to web embed player
        _switchToEmbedFallback();
      }
    }
  }

  void _videoPlayerListener() {
    final controller = _videoPlayerController;
    if (controller == null || !mounted) return;

    final val = controller.value;
    if (!_isDraggingSeekbar) {
      setState(() {
        _currentPosition = val.position;
        _totalDuration = val.duration;
        _isPlaying = val.isPlaying;
        _isBuffering = val.isBuffering;
      });
    }

    // Auto-detect stream completion for TV episode autoplay
    if (val.isInitialized && val.duration > const Duration(seconds: 15)) {
      final remaining = val.duration - val.position;
      if (remaining <= const Duration(seconds: 2) && !_showAutoplayCard && widget.mediaType == 'tv') {
        _triggerAutoplayNext();
      }
    }
  }

  void _switchToEmbedFallback() {
    if (!mounted) return;
    setState(() {
      _isNativeMode = false;
      _isExtracting = false;
    });
    // Pick first embed server if current was native
    if (ServerConfig.servers[_selectedServerIndex].isDirectPlay) {
      _selectedServerIndex = 1;
    }
    _loadWebEmbed();
  }

  void _loadWebEmbed() {
    _disposeVideoController();
    setState(() {
      _isNativeMode = false;
      _isExtracting = false;
      _isLoading = true;
      _isWebViewLoading = true;
    });
    _initWebView();
  }

  String _buildCurrentEmbedUrl() {
    final server = ServerConfig.servers[_selectedServerIndex];
    return ServerConfig.getEmbedUrl(
      server: server,
      type: widget.mediaType,
      id: widget.mediaId,
      season: _currentSeason,
      episode: _currentEpisode,
    );
  }

  void _initWebView() {
    final url = _buildCurrentEmbedUrl();

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setBackgroundColor(Colors.black);

    // Android-specific optimizations for video streaming
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setMixedContentMode(MixedContentMode.alwaysAllow);
      androidController.setAllowContentAccess(true);
      androidController.setAllowFileAccess(true);
    }

    controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _isWebViewLoading = true;
              });
            }
            _webViewController?.runJavaScript(_cleanAntiPopupScript);
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isWebViewLoading = false;
              });
            }
            _webViewController?.runJavaScript(_cleanAntiPopupScript);
          },
          onProgress: (int progress) {
            if (progress >= 70 && _isWebViewLoading && mounted) {
              setState(() {
                _isLoading = false;
                _isWebViewLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_shouldBlockNavigation(request.url)) {
              debugPrint('VOIDFLIX: Blocked popup/ad request: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
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
          } else if (msg.message == 'screen_tapped' && mounted) {
            _revealControls();
          }
        },
      )
      ..loadRequest(Uri.parse(url));

    _webViewController = controller;
  }

  bool _shouldBlockNavigation(String url) {
    final lower = url.toLowerCase();

    // 1. Block external intent schemes
    if (lower.startsWith('intent:') ||
        lower.startsWith('market:') ||
        lower.startsWith('vnd:') ||
        lower.startsWith('whatsapp:') ||
        lower.startsWith('tg:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('tel:') ||
        lower.startsWith('sms:') ||
        lower.endsWith('.apk')) {
      return true;
    }

    // 2. Block aggressive ad networks
    const blockedAdDomains = [
      'adsterra',
      'popads',
      'propellerads',
      'exoclick',
      'bet365',
      '1xbet',
      'betway',
      'casino',
      'adcash',
      'trafficjunky',
      'onclickmega',
      'doubleclick',
      'adnxs',
      'popcash',
      'hilltopads',
      'monetag',
    ];

    for (final ad in blockedAdDomains) {
      if (lower.contains(ad)) return true;
    }

    return false;
  }

  static const String _cleanAntiPopupScript = '''
(function() {
  try {
    // 1. Neutralize window.open popups
    window.open = function() { return null; };
    Object.defineProperty(window, 'open', {
      value: function() { return null; },
      writable: false,
      configurable: false
    });
  } catch(e) {}

  try {
    // 2. Suppress dialog popups
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
  } catch(e) {}

  // 3. Remove target="_blank"
  try {
    var links = document.querySelectorAll('a[target="_blank"]');
    for (var i = 0; i < links.length; i++) {
      links[i].removeAttribute('target');
    }
  } catch(e) {}

  // 4. Tap notifier to Flutter
  function notifyTap() {
    try {
      if (window.VoidflixBridge) {
        window.VoidflixBridge.postMessage('screen_tapped');
      }
    } catch(e) {}
  }
  window.addEventListener('click', notifyTap, true);
  window.addEventListener('touchend', notifyTap, true);

  // 5. Video ended hook
  function hookVideo() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (!v._vfHooked) {
          v._vfHooked = true;
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

  // 6. Iframe postMessage hook (vidlink, videasy)
  window.addEventListener('message', function(ev) {
    try {
      var data = ev.data;
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch(err) {}
      }
      if (data && typeof data === 'object') {
        var p = (data.data && typeof data.data === 'object') ? data.data : data;
        var event = String(p.event || p.status || data.event || data.status || '').toLowerCase();
        var dur = Number(p.duration);
        var cur = Number(p.currentTime || p.timestamp || p.watched);
        if (event === 'ended' || data.type === 'ended' || (dur > 0 && cur > 0 && (dur - cur) <= 2)) {
          if (window.VoidflixBridge) {
            window.VoidflixBridge.postMessage('video_ended');
          }
        }
      }
    } catch(e) {}
  });

  hookVideo();
  setInterval(hookVideo, 3000);
})();
''';

  // ---------------------------------------------------------------------------
  // Controls & Gestures
  // ---------------------------------------------------------------------------

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isLandscape) {
      _hideControlsTimer = Timer(const Duration(seconds: 7), () {
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
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _revealControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  void _togglePlayPause() {
    _startHideControlsTimer();
    final controller = _videoPlayerController;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      controller.pause();
      setState(() => _isPlaying = false);
    } else {
      controller.play();
      setState(() => _isPlaying = true);
    }
  }

  void _seekRelative(int seconds) {
    _startHideControlsTimer();
    final controller = _videoPlayerController;
    if (controller == null) return;

    final newPos = controller.value.position + Duration(seconds: seconds);
    final clamped = Duration(
      seconds: newPos.inSeconds.clamp(0, controller.value.duration.inSeconds),
    );
    controller.seekTo(clamped);
  }

  Future<void> _handleSmoothBack() async {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _cancelAutoplayTimer();
    _hideControlsTimer?.cancel();
    _disposeVideoController();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await Future.delayed(const Duration(milliseconds: 140));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _toggleOrientation() {
    _startHideControlsTimer();
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

  // ---------------------------------------------------------------------------
  // Episodes & Watch Progress
  // ---------------------------------------------------------------------------

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

  void _goToEpisode(int episodeNum) {
    _cancelAutoplayTimer();
    setState(() {
      _currentEpisode = episodeNum;
    });
    _loadMedia();
    _recordWatchProgress();

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
      final currentSeasonIndex =
          _seasons.indexWhere((s) => s.seasonNumber == _currentSeason);
      if (currentSeasonIndex != -1 && currentSeasonIndex + 1 < _seasons.length) {
        final nextSeason = _seasons[currentSeasonIndex + 1];
        setState(() {
          _currentSeason = nextSeason.seasonNumber;
          _currentEpisode = 1;
        });
        _loadEpisodesForSeason(_currentSeason);
        _loadMedia();
        _recordWatchProgress();
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

  void _prevEpisode() {
    if (widget.mediaType != 'tv' || _currentEpisode <= 1) return;
    _goToEpisode(_currentEpisode - 1);
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

  // ---------------------------------------------------------------------------
  // Modals & Bottom Sheets
  // ---------------------------------------------------------------------------

  void _openServerPicker() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Stream Source / Server',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _startHideControlsTimer();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.border, height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Direct Extracted Streams Section
                      if (_directStreams.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
                          child: Row(
                            children: [
                              Icon(Icons.bolt, color: AppTheme.primaryRed, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'DIRECT NATIVE STREAMS (EXOPLAYER)',
                                style: TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...List.generate(_directStreams.length, (idx) {
                          final stream = _directStreams[idx];
                          final isSelected = _isNativeMode && _selectedStreamIndex == idx;
                          return ListTile(
                            leading: Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isSelected ? AppTheme.primaryRed : Colors.white54,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  '${stream.sourceName} (Direct HLS)',
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.matchGreen.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'NO ADS • 60FPS',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppTheme.matchGreen,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: const Text(
                              'Fast buffer-free native playback',
                              style: TextStyle(fontSize: 12, color: Colors.white38),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _selectedStreamIndex = idx;
                              });
                              _initNativePlayer(stream);
                            },
                          );
                        }),
                        const Divider(color: AppTheme.border, height: 20),
                      ],

                      // Web Embed Providers Section
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                        child: Text(
                          'ALTERNATIVE EMBED SERVERS',
                          style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      ...List.generate(ServerConfig.servers.length, (idx) {
                        final s = ServerConfig.servers[idx];
                        if (s.isDirectPlay) return const SizedBox.shrink();
                        final isSelected = !_isNativeMode && idx == _selectedServerIndex;
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
                              if (idx == 1 || idx == 2) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'POPULAR',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white70,
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
                            Navigator.pop(ctx);
                            setState(() {
                              _selectedServerIndex = idx;
                              _isNativeMode = false;
                            });
                            context.read<ProfileProvider>().setSelectedServer(idx);
                            _loadWebEmbed();
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openEpisodesSheet() {
    _hideControlsTimer?.cancel();
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
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _startHideControlsTimer();
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoadingEpisodes
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _episodes.length,
                              itemBuilder: (c, idx) {
                                final ep = _episodes[idx];
                                final isPlaying = ep.episodeNumber == _currentEpisode;
                                return InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _goToEpisode(ep.episodeNumber);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    color: isPlaying ? AppTheme.primaryRed.withValues(alpha: 0.15) : null,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              ep.stillPath != null
                                                  ? CachedNetworkImage(
                                                      imageUrl: ApiService.getImageUrl(ep.stillPath, size: 'w300'),
                                                      width: 100,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                      errorWidget: (cx, u, e) => Container(
                                                        width: 100,
                                                        height: 60,
                                                        color: const Color(0xFF1E1E28),
                                                        child: const Icon(Icons.movie, color: Colors.white24),
                                                      ),
                                                    )
                                                  : Container(
                                                      width: 100,
                                                      height: 60,
                                                      color: const Color(0xFF1E1E28),
                                                      child: const Icon(Icons.movie, color: Colors.white24),
                                                    ),
                                              if (isPlaying)
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryRed.withValues(alpha: 0.9),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
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
                                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
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

  // ---------------------------------------------------------------------------
  // Build Methods & UI
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final minPad = minutes.toString().padLeft(2, '0');
    final secPad = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minPad:$secPad';
    }
    return '$minPad:$secPad';
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

  /// Persistent floating quick pill: always renders when full controls fade out
  Widget _buildFloatingQuickPill() {
    final serverName = _isNativeMode
        ? (_directStreams.isNotEmpty
            ? _directStreams[_selectedStreamIndex].sourceName
            : 'Direct')
        : ServerConfig.servers[_selectedServerIndex].name;

    return AnimatedOpacity(
      opacity: _showControls ? 0.0 : 0.65,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: _showControls,
        child: Container(
          margin: const EdgeInsets.only(top: 14, right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xDD121218),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Change Server button
              InkWell(
                onTap: _openServerPicker,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_rounded, size: 14, color: AppTheme.primaryRed),
                      const SizedBox(width: 4),
                      Text(
                        serverName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.mediaType == 'tv') ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 14, color: Colors.white24),
                const SizedBox(width: 6),
                // Next Episode button
                InkWell(
                  onTap: _nextEpisode,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          'Next',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.skip_next_rounded, size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Container(width: 1, height: 14, color: Colors.white24),
              const SizedBox(width: 6),
              // Expand controls button
              InkWell(
                onTap: _revealControls,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.tune_rounded, size: 15, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentServer = ServerConfig.servers[_selectedServerIndex];
    final activeServerLabel = _isNativeMode
        ? (_directStreams.isNotEmpty
            ? '${_directStreams[_selectedStreamIndex].sourceName} (Direct)'
            : 'VoidDirect')
        : currentServer.name;

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
                // Top bar for Portrait mode
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
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          tooltip: 'Reload Stream',
                          onPressed: _loadMedia,
                        ),
                        IconButton(
                          icon: const Icon(Icons.fullscreen, color: Colors.white, size: 28),
                          tooltip: 'Fullscreen',
                          onPressed: _toggleOrientation,
                        ),
                      ],
                    ),
                  ),

                // Video Display Area
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Layer 1: The Active Video Player (Native or WebView)
                      if (_isNativeMode &&
                          _videoPlayerController != null &&
                          _videoPlayerController!.value.isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: _videoPlayerController!.value.aspectRatio,
                            child: VideoPlayer(_videoPlayerController!),
                          ),
                        )
                      else if (!_isNativeMode && _webViewController != null)
                        WebViewWidget(controller: _webViewController!)
                      else
                        Container(color: Colors.black),

                      // Layer 2: Universal tap interceptor for screen taps
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _toggleControls,
                          onDoubleTapDown: (details) {
                            final width = MediaQuery.of(context).size.width;
                            if (details.localPosition.dx < width / 2) {
                              _seekRelative(-10);
                            } else {
                              _seekRelative(10);
                            }
                          },
                        ),
                      ),

                      // Layer 3: Loading / Extracting Overlay
                      if (_isLoading)
                        Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: AppTheme.primaryRed),
                                const SizedBox(height: 16),
                                Text(
                                  _isExtracting
                                      ? 'Extracting high-speed direct stream...'
                                      : 'Connecting to stream...',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(color: Colors.white24),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  ),
                                  icon: const Icon(Icons.dns, size: 14, color: AppTheme.primaryRed),
                                  label: const Text('Change Server', style: TextStyle(fontSize: 12)),
                                  onPressed: _openServerPicker,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Layer 4: Buffering indicator when scrubbing/buffering
                      if (!_isLoading && _isBuffering)
                        const Center(
                          child: CircularProgressIndicator(color: AppTheme.primaryRed),
                        ),

                      // Layer 5: Persistent Floating Quick Pill (visible when controls hide)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: _buildFloatingQuickPill(),
                      ),

                      // Layer 6: Full Controls Overlay (Landscape or Portrait)
                      if (_showControls)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.82),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.88),
                                ],
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Top App Bar
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
                                            Row(
                                              children: [
                                                if (widget.mediaType == 'tv')
                                                  Text(
                                                    'Season $_currentSeason • Episode $_currentEpisode  •  ',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryRed.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    activeServerLabel,
                                                    style: const TextStyle(
                                                      color: AppTheme.primaryRed,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.refresh, color: Colors.white),
                                        tooltip: 'Reload',
                                        onPressed: () {
                                          _startHideControlsTimer();
                                          _loadMedia();
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          _isLandscape ? Icons.fullscreen_exit : Icons.fullscreen,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        tooltip: _isLandscape ? 'Exit Fullscreen' : 'Fullscreen',
                                        onPressed: _toggleOrientation,
                                      ),
                                    ],
                                  ),
                                ),

                                // Center Quick Action Buttons (Native mode)
                                if (_isNativeMode)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        iconSize: 42,
                                        icon: const Icon(Icons.replay_10, color: Colors.white),
                                        tooltip: 'Rewind 10s',
                                        onPressed: () => _seekRelative(-10),
                                      ),
                                      const SizedBox(width: 32),
                                      GestureDetector(
                                        onTap: _togglePlayPause,
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryRed,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppTheme.primaryRed.withValues(alpha: 0.5),
                                                blurRadius: 20,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            _isPlaying ? Icons.pause : Icons.play_arrow,
                                            size: 38,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 32),
                                      IconButton(
                                        iconSize: 42,
                                        icon: const Icon(Icons.forward_10, color: Colors.white),
                                        tooltip: 'Forward 10s',
                                        onPressed: () => _seekRelative(10),
                                      ),
                                    ],
                                  )
                                else
                                  const SizedBox.shrink(),

                                // Bottom Controls Section
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Timeline Scrubber (Native mode)
                                      if (_isNativeMode && _totalDuration > Duration.zero) ...[
                                        Row(
                                          children: [
                                            Text(
                                              _formatDuration(_isDraggingSeekbar
                                                  ? Duration(seconds: _dragPositionSec.toInt())
                                                  : _currentPosition),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Expanded(
                                              child: SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  activeTrackColor: AppTheme.primaryRed,
                                                  inactiveTrackColor: Colors.white24,
                                                  thumbColor: AppTheme.primaryRed,
                                                  trackHeight: 3.5,
                                                  thumbShape: const RoundSliderThumbShape(
                                                    enabledThumbRadius: 6,
                                                  ),
                                                ),
                                                child: Slider(
                                                  value: (_isDraggingSeekbar
                                                          ? _dragPositionSec
                                                          : _currentPosition.inSeconds.toDouble())
                                                      .clamp(0.0, _totalDuration.inSeconds.toDouble()),
                                                  min: 0.0,
                                                  max: _totalDuration.inSeconds.toDouble(),
                                                  onChangeStart: (val) {
                                                    _hideControlsTimer?.cancel();
                                                    setState(() {
                                                      _isDraggingSeekbar = true;
                                                      _dragPositionSec = val;
                                                    });
                                                  },
                                                  onChanged: (val) {
                                                    setState(() {
                                                      _dragPositionSec = val;
                                                    });
                                                  },
                                                  onChangeEnd: (val) {
                                                    setState(() {
                                                      _isDraggingSeekbar = false;
                                                    });
                                                    _videoPlayerController?.seekTo(Duration(seconds: val.toInt()));
                                                    _startHideControlsTimer();
                                                  },
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatDuration(_totalDuration),
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],

                                      // Bottom Actions: Server, Episodes, Prev & Next
                                      Row(
                                        children: [
                                          // Change Server Button
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: Colors.white38),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            onPressed: _openServerPicker,
                                            icon: const Icon(Icons.dns, size: 16, color: AppTheme.primaryRed),
                                            label: Text(
                                              activeServerLabel,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 10),

                                          // Episode Drawer Button (TV)
                                          if (widget.mediaType == 'tv')
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primaryRed,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              ),
                                              onPressed: _openEpisodesSheet,
                                              icon: const Icon(Icons.video_library_rounded, size: 16),
                                              label: const Text('Episodes', style: TextStyle(fontSize: 12)),
                                            ),

                                          const Spacer(),

                                          // Prev & Next Episode Buttons (TV)
                                          if (widget.mediaType == 'tv') ...[
                                            IconButton(
                                              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 30),
                                              tooltip: 'Previous Episode',
                                              onPressed: _currentEpisode > 1 ? _prevEpisode : null,
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white12,
                                                borderRadius: BorderRadius.circular(4),
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
                                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                                              tooltip: 'Next Episode',
                                              onPressed: _nextEpisode,
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
                        ),

                      // Layer 7: Autoplay Countdown Card
                      if (_showAutoplayCard)
                        Positioned(
                          bottom: _isLandscape ? 24 : 16,
                          right: 16,
                          child: _buildAutoplayNextCard(),
                        ),
                    ],
                  ),
                ),

                // Bottom Bar in Portrait mode
                if (!_isLandscape)
                  Container(
                    color: AppTheme.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openServerPicker,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.border),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.dns, size: 16, color: AppTheme.primaryRed),
                          label: Text(
                            activeServerLabel,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Spacer(),
                        if (widget.mediaType == 'tv') ...[
                          OutlinedButton.icon(
                            onPressed: _openEpisodesSheet,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.border),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(Icons.video_library_rounded, size: 16, color: Colors.white70),
                            label: const Text('Episodes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
