import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'dart:io';

import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/stream_extractor.dart';
import '../core/services/subtitle_service.dart';
import '../models/media_detail.dart';
import '../models/server_config.dart';
import '../models/watch_progress.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/netflix_season_picker.dart';

class PlayerScreen extends StatefulWidget {
  final int mediaId;
  final String mediaTitle;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? posterPath;
  final String? backdropPath;
  final String? localFilePath;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.mediaTitle,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    this.posterPath,
    this.backdropPath,
    this.localFilePath,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Navigation & playback state
  late int _currentSeason;
  late int _currentEpisode;
  late int _selectedServerIndex;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isExiting = false;

  // Screen lock system (Netflix feature)
  bool _isLocked = false;
  bool _showLockPill = false;
  Timer? _lockPillTimer;

  // Screen brightness system (Netflix feature)
  double _brightness = 1.0; // 0.2 min to 1.0 max
  bool _showBrightnessHud = false;
  Timer? _brightnessHudTimer;

  // Playback speed system (Netflix feature)
  double _playbackSpeed = 1.0;

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

  // Subtitles & Audio system (Netflix 2-column feature)
  final SubtitleService _subtitleService = SubtitleService();
  List<SubtitleTrack> _subtitles = [];
  SubtitleTrack? _selectedSubtitle;
  List<SubtitleCue> _currentCues = [];
  String? _activeCueText;

  // Qualities system (Netflix feature)
  List<StreamQuality> _availableQualities = [];
  int _selectedQualityIndex = 0;

  // Web fallback player state
  WebViewController? _webViewController;
  bool _isWebViewLoading = true;

  // General loading & errors
  bool _isLoading = true;

  // Double tap seek ripple indicator
  int? _doubleTapSeekSeconds;
  Timer? _doubleTapTimer;

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

    // Lock firmly to immersive fullscreen landscape mode
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
    _lockPillTimer?.cancel();
    _brightnessHudTimer?.cancel();
    _doubleTapTimer?.cancel();
    _autoplayTimer?.cancel();
    _disposeVideoController();

    // Restore portrait orientation and standard edge-to-edge UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
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

    // Check if playing an offline in-app download
    if (widget.localFilePath != null && File(widget.localFilePath!).existsSync()) {
      await _loadLocalFile(widget.localFilePath!);
      return;
    }

    final server = ServerConfig.servers[_selectedServerIndex];

    if (server.isDirectPlay) {
      await _loadDirectStream();
    } else {
      _loadWebEmbed();
    }
  }

  Future<void> _loadLocalFile(String path) async {
    setState(() {
      _isNativeMode = true;
      _isExtracting = false;
      _isLoading = true;
      _activeCueText = null;
      _availableQualities = [
        StreamQuality(label: 'Offline (Downloaded)', height: 1080, url: path),
      ];
      _selectedQualityIndex = 0;
    });

    _disposeVideoController();

    try {
      final controller = VideoPlayerController.file(File(path));
      _videoPlayerController = controller;
      await controller.initialize();

      if (!mounted) return;

      controller.addListener(_videoPlayerListener);
      await controller.setPlaybackSpeed(_playbackSpeed);
      await controller.play();

      setState(() {
        _isLoading = false;
        _isPlaying = true;
        _totalDuration = controller.value.duration;
        _currentPosition = controller.value.position;
      });
      _startHideControlsTimer();
    } catch (e) {
      debugPrint('Local file playback error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDirectStream() async {
    setState(() {
      _isNativeMode = true;
      _isExtracting = true;
      _isLoading = true;
      _activeCueText = null;
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

        // Aggregate subtitles from all sources
        final allSubs = <SubtitleTrack>[];
        final seenSubUrls = <String>{};
        for (final s in streams) {
          for (final sub in s.subtitles) {
            if (!seenSubUrls.contains(sub.url)) {
              seenSubUrls.add(sub.url);
              allSubs.add(sub);
            }
          }
        }
        _subtitles = allSubs;

        // Auto-select English subtitle if available
        final defaultSub = allSubs.where((s) => s.label.toLowerCase().contains('english') || s.language == 'en').firstOrNull;
        if (defaultSub != null) {
          _selectSubtitle(defaultSub);
        }

        await _initNativePlayer(streams[0]);
      } else {
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

  Future<void> _initNativePlayer(ExtractedStream stream, {Duration? startPosition, bool autoPlay = true}) async {
    _disposeVideoController();

    setState(() {
      _isExtracting = false;
      _isLoading = true;
      _isNativeMode = true;
      _availableQualities = stream.qualities.isNotEmpty
          ? stream.qualities
          : [
              StreamQuality(label: 'Auto (HLS)', height: 0, url: stream.url),
              StreamQuality(label: '1080p', height: 1080, url: stream.url),
              StreamQuality(label: '720p', height: 720, url: stream.url),
              StreamQuality(label: '480p', height: 480, url: stream.url),
            ];
      _selectedQualityIndex = 0;
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

      if (startPosition != null && startPosition > Duration.zero) {
        await controller.seekTo(startPosition);
      }

      await controller.setPlaybackSpeed(_playbackSpeed);

      if (autoPlay) {
        await controller.play();
      }

      setState(() {
        _isLoading = false;
        _isPlaying = autoPlay;
        _totalDuration = controller.value.duration;
        _currentPosition = controller.value.position;
      });
      _startHideControlsTimer();
    } catch (e) {
      debugPrint('Native player initialization failed for ${stream.sourceName}: $e');
      if (_selectedStreamIndex + 1 < _directStreams.length) {
        _selectedStreamIndex++;
        await _initNativePlayer(_directStreams[_selectedStreamIndex], startPosition: startPosition, autoPlay: autoPlay);
      } else {
        _switchToEmbedFallback();
      }
    }
  }

  Future<void> _switchVideoStream(String url, Duration startPos, bool wasPlaying) async {
    final controller = _videoPlayerController;
    if (controller == null) return;

    setState(() => _isBuffering = true);

    try {
      final headers = _directStreams.isNotEmpty
          ? _directStreams[_selectedStreamIndex].headers
          : <String, String>{};

      final newController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers,
      );

      await newController.initialize();
      if (!mounted) {
        newController.dispose();
        return;
      }

      _disposeVideoController();
      _videoPlayerController = newController;
      newController.addListener(_videoPlayerListener);

      await newController.seekTo(startPos);
      await newController.setPlaybackSpeed(_playbackSpeed);

      if (wasPlaying) {
        await newController.play();
      }

      setState(() {
        _isBuffering = false;
        _isPlaying = wasPlaying;
        _totalDuration = newController.value.duration;
        _currentPosition = newController.value.position;
      });
    } catch (e) {
      debugPrint('Error switching video stream: $e');
      setState(() => _isBuffering = false);
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

      // Synchronize live subtitle cue text
      if (_currentCues.isNotEmpty) {
        final cue = SubtitleService.getCueAt(_currentCues, val.position);
        if (cue != _activeCueText) {
          setState(() => _activeCueText = cue);
        }
      } else if (_activeCueText != null) {
        setState(() => _activeCueText = null);
      }
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
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
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

    const blocked = [
      'adsterra', 'popads', 'propellerads', 'exoclick', 'bet365', '1xbet',
      'betway', 'casino', 'adcash', 'trafficjunky', 'onclickmega', 'doubleclick',
      'adnxs', 'popcash', 'hilltopads', 'monetag'
    ];
    for (final b in blocked) {
      if (lower.contains(b)) return true;
    }
    return false;
  }

  static const String _cleanAntiPopupScript = '''
(function() {
  try {
    window.open = function() { return null; };
    Object.defineProperty(window, 'open', { value: function() { return null; }, writable: false, configurable: false });
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
  } catch(e) {}
  try {
    var links = document.querySelectorAll('a[target="_blank"]');
    for (var i = 0; i < links.length; i++) { links[i].removeAttribute('target'); }
  } catch(e) {}
  function notifyTap() {
    try { if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('screen_tapped'); } } catch(e) {}
  }
  window.addEventListener('click', notifyTap, true);
  window.addEventListener('touchend', notifyTap, true);
  function hookVideo() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (!v._vfHooked) {
          v._vfHooked = true;
          v.addEventListener('ended', function() {
            if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('video_ended'); }
          });
          v.addEventListener('timeupdate', function() {
            if (v.duration && v.duration > 15 && v.currentTime >= v.duration - 2) {
              if (!v._vfEndedPosted) {
                v._vfEndedPosted = true;
                if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('video_ended'); }
              }
            }
          });
        }
      }
    } catch(e) {}
  }
  hookVideo();
  setInterval(hookVideo, 3000);
})();
''';

  // ---------------------------------------------------------------------------
  // Controls, Gestures & Locking
  // ---------------------------------------------------------------------------

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _showControls && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showLockPill = true);
      _lockPillTimer?.cancel();
      _lockPillTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showLockPill = false);
      });
      return;
    }

    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _revealControls() {
    if (_isLocked) return;
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

    // Trigger double tap feedback badge
    setState(() => _doubleTapSeekSeconds = seconds);
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _doubleTapSeekSeconds = null);
    });
  }

  void _toggleScreenLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
        _showLockPill = true;
      } else {
        _showControls = true;
        _showLockPill = false;
      }
    });

    if (_isLocked) {
      _lockPillTimer?.cancel();
      _lockPillTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showLockPill = false);
      });
    } else {
      _startHideControlsTimer();
    }
  }

  void _adjustBrightness(double delta) {
    if (_isLocked) return;
    setState(() {
      _brightness = (_brightness + delta).clamp(0.2, 1.0);
      _showBrightnessHud = true;
    });
    _brightnessHudTimer?.cancel();
    _brightnessHudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showBrightnessHud = false);
    });
  }

  Future<void> _handleSmoothBack() async {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _cancelAutoplayTimer();
    _hideControlsTimer?.cancel();
    _disposeVideoController();

    // Cleanly restore portrait orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await Future.delayed(const Duration(milliseconds: 120));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------------
  // Episodes, Audio, Subtitles & Quality Pickers
  // ---------------------------------------------------------------------------

  Future<void> _fetchTvDetailsAndEpisodes() async {
    try {
      final detail = await ApiService().getDetails('tv', widget.mediaId);
      if (mounted) {
        setState(() => _seasons = detail.seasons);
        _loadEpisodesForSeason(_currentSeason);
      }
    } catch (e) {
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
      if (mounted) setState(() => _isLoadingEpisodes = false);
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
    setState(() => _currentEpisode = episodeNum);
    _loadMedia();
    _recordWatchProgress();
  }

  void _nextEpisode() {
    if (widget.mediaType != 'tv') return;
    _cancelAutoplayTimer();
    if (_episodes.isNotEmpty && _currentEpisode < _episodes.length) {
      _goToEpisode(_currentEpisode + 1);
    } else {
      final currentSeasonIndex = _seasons.indexWhere((s) => s.seasonNumber == _currentSeason);
      if (currentSeasonIndex != -1 && currentSeasonIndex + 1 < _seasons.length) {
        final nextSeason = _seasons[currentSeasonIndex + 1];
        setState(() {
          _currentSeason = nextSeason.seasonNumber;
          _currentEpisode = 1;
        });
        _loadEpisodesForSeason(_currentSeason);
        _loadMedia();
        _recordWatchProgress();
      }
    }
  }

  void _prevEpisode() {
    if (widget.mediaType != 'tv' || _currentEpisode <= 1) return;
    _cancelAutoplayTimer();
    _goToEpisode(_currentEpisode - 1);
  }

  void _triggerAutoplayNext() {
    if (widget.mediaType != 'tv' || _showAutoplayCard) return;
    _cancelAutoplayTimer();
    setState(() {
      _showAutoplayCard = true;
      _autoplayCountdown = 5;
    });

    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_autoplayCountdown > 1) {
        setState(() => _autoplayCountdown--);
      } else {
        _cancelAutoplayTimer();
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

  Future<void> _selectSubtitle(SubtitleTrack? track) async {
    setState(() {
      _selectedSubtitle = track;
      _activeCueText = null;
      _currentCues = [];
    });

    if (track == null) return;

    final cues = await _subtitleService.loadTrack(track.url);
    if (mounted && _selectedSubtitle == track) {
      setState(() => _currentCues = cues);
    }
  }

  Future<void> _selectAudioSource(int index) async {
    if (index >= _directStreams.length) return;
    _selectedStreamIndex = index;
    final stream = _directStreams[index];
    final currentPos = _videoPlayerController?.value.position ?? Duration.zero;
    final wasPlaying = _videoPlayerController?.value.isPlaying ?? false;
    await _switchVideoStream(stream.url, currentPos, wasPlaying);
  }

  Future<void> _selectQuality(int index) async {
    if (index >= _availableQualities.length) return;
    _selectedQualityIndex = index;
    final target = _availableQualities[index];
    final currentPos = _videoPlayerController?.value.position ?? Duration.zero;
    final wasPlaying = _videoPlayerController?.value.isPlaying ?? false;
    await _switchVideoStream(target.url, currentPos, wasPlaying);
  }

  // ---------------------------------------------------------------------------
  // Netflix Modals (Audio & Subtitles, Speed, Quality, Episodes, Servers)
  // ---------------------------------------------------------------------------

  void _openAudioAndSubtitlesSheet() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: AUDIO (Dubs / Streams)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Text(
                                    'AUDIO',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _directStreams.isNotEmpty ? _directStreams.length : 1,
                                    itemBuilder: (c, idx) {
                                      final label = _directStreams.isNotEmpty
                                          ? '${_directStreams[idx].language} (${_directStreams[idx].sourceName})'
                                          : 'Original (Stereo)';
                                      final isSelected = idx == _selectedStreamIndex;
                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                        dense: true,
                                        title: Text(
                                          label,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.white70,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? const Icon(Icons.check, color: AppTheme.primaryRed, size: 20)
                                            : null,
                                        onTap: () {
                                          setSheetState(() {});
                                          _selectAudioSource(idx);
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, color: Colors.white12),
                          const SizedBox(width: 16),
                          // Right Column: SUBTITLES
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Text(
                                    'SUBTITLES',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListView(
                                    children: [
                                      ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                        dense: true,
                                        title: Text(
                                          'Off',
                                          style: TextStyle(
                                            color: _selectedSubtitle == null ? Colors.white : Colors.white70,
                                            fontWeight: _selectedSubtitle == null ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                        ),
                                        trailing: _selectedSubtitle == null
                                            ? const Icon(Icons.check, color: AppTheme.primaryRed, size: 20)
                                            : null,
                                        onTap: () {
                                          _selectSubtitle(null);
                                          Navigator.pop(ctx);
                                        },
                                      ),
                                      ..._subtitles.map((track) {
                                        final isSelected = _selectedSubtitle?.url == track.url;
                                        return ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                          dense: true,
                                          title: Text(
                                            track.label,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white70,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 14,
                                            ),
                                          ),
                                          trailing: isSelected
                                              ? const Icon(Icons.check, color: AppTheme.primaryRed, size: 20)
                                              : null,
                                          onTap: () {
                                            _selectSubtitle(track);
                                            Navigator.pop(ctx);
                                          },
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openSpeedSheet() {
    _hideControlsTimer?.cancel();
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'PLAYBACK SPEED',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...speeds.map((sp) {
                  final isSelected = _playbackSpeed == sp;
                  final label = sp == 1.0 ? '1x (Normal)' : '${sp}x';
                  return ListTile(
                    dense: true,
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppTheme.primaryRed, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _playbackSpeed = sp);
                      _videoPlayerController?.setPlaybackSpeed(sp);
                      Navigator.pop(ctx);
                      _startHideControlsTimer();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openQualitySheet() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'STREAM QUALITY',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...List.generate(_availableQualities.length, (idx) {
                  final q = _availableQualities[idx];
                  final isSelected = idx == _selectedQualityIndex;
                  return ListTile(
                    dense: true,
                    title: Text(
                      q.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 15,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppTheme.primaryRed, size: 20)
                        : null,
                    onTap: () {
                      _selectQuality(idx);
                      Navigator.pop(ctx);
                      _startHideControlsTimer();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openEpisodesSheet() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
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
                            GestureDetector(
                              onTap: () async {
                                final newSeason = await NetflixSeasonPicker.show(
                                  context: ctx,
                                  seasons: _seasons,
                                  selectedSeason: _currentSeason,
                                );
                                if (newSeason != null && newSeason != _currentSeason && mounted) {
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
                                      'Season $_currentSeason',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                                  ],
                                ),
                              ),
                            )
                          else
                            Text('Season $_currentSeason', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoadingEpisodes
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryRed))
                          : ListView.builder(
                              itemCount: _episodes.length,
                              itemBuilder: (c, idx) {
                                final ep = _episodes[idx];
                                final isCurrent = ep.episodeNumber == _currentEpisode;
                                return InkWell(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _goToEpisode(ep.episodeNumber);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    color: isCurrent ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
                                    child: Row(
                                      children: [
                                        // 16:9 Thumbnail
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SizedBox(
                                                width: 100,
                                                height: 58,
                                                child: ep.stillPath != null
                                                    ? CachedNetworkImage(
                                                        imageUrl: ApiService.getImageUrl(ep.stillPath, size: 'w300'),
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context, url, error) => Container(color: Colors.black26),
                                                      )
                                                    : Container(color: Colors.white12),
                                              ),
                                              if (isCurrent)
                                                Container(
                                                  width: 100,
                                                  height: 58,
                                                  color: Colors.black45,
                                                  child: const Center(
                                                    child: Icon(Icons.play_arrow_rounded, color: AppTheme.primaryRed, size: 28),
                                                  ),
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
                                                  Expanded(
                                                    child: Text(
                                                      '${ep.episodeNumber}. ${ep.name}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: isCurrent ? AppTheme.primaryRed : Colors.white,
                                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  if (ep.runtime > 0)
                                                    Text(
                                                      '${ep.runtime}m',
                                                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                ep.overview.isNotEmpty ? ep.overview : 'No description available.',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                              ),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openServerPicker() {
    _hideControlsTimer?.cancel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'STREAM SERVERS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      // Direct Stream Sources
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: Text(
                          'DIRECT HIGH-SPEED (NO ADS)',
                          style: TextStyle(color: AppTheme.primaryRed, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...List.generate(_directStreams.length, (idx) {
                        final s = _directStreams[idx];
                        final isSel = _isNativeMode && idx == _selectedStreamIndex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSel ? AppTheme.primaryRed : Colors.white54,
                          ),
                          title: Text(
                            '${s.sourceName} • ${s.language}',
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text('Direct ${s.type.toUpperCase()} stream', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _selectAudioSource(idx);
                          },
                        );
                      }),
                      const Divider(color: Colors.white12),
                      // Embed Fallbacks
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                        child: Text(
                          'ALTERNATIVE EMBED SERVERS',
                          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...List.generate(ServerConfig.servers.length, (idx) {
                        final s = ServerConfig.servers[idx];
                        if (s.isDirectPlay) return const SizedBox.shrink();
                        final isSel = !_isNativeMode && idx == _selectedServerIndex;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSel ? AppTheme.primaryRed : Colors.white54,
                          ),
                          title: Text(
                            s.name,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(s.description, style: const TextStyle(fontSize: 11, color: Colors.white38)),
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
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers & Formatters
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String pad(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${pad(m)}:${pad(s)}' : '$m:${pad(s)}';
  }

  String _formatRemaining(Duration current, Duration total) {
    if (total <= Duration.zero) return '';
    final diff = total - current;
    final s = diff.isNegative ? Duration.zero : diff;
    return '-${_formatDuration(s)}';
  }

  // ---------------------------------------------------------------------------
  // Build Components
  // ---------------------------------------------------------------------------

  Widget _buildAutoplayNextCard() {
    if (_episodes.isEmpty || _currentEpisode >= _episodes.length) {
      return const SizedBox.shrink();
    }
    final nextNum = _currentEpisode + 1;
    final nextEp = _episodes.firstWhere(
      (e) => e.episodeNumber == nextNum,
      orElse: () => _episodes.first,
    );

    return Container(
      width: 290,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEA16161C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$_autoplayCountdown',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NEXT EPISODE IN',
                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _cancelAutoplayTimer,
                child: const Icon(Icons.close, color: Colors.white60, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (nextEp.stillPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 65,
                    height: 38,
                    child: CachedNetworkImage(
                      imageUrl: ApiService.getImageUrl(nextEp.stillPath, size: 'w300'),
                      fit: BoxFit.cover,
                      errorWidget: (c, u, e) => Container(color: Colors.black38),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'S$_currentSeason E$nextNum • ${nextEp.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 16),
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
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
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

  Widget _buildBrightnessHud() {
    final pct = (_brightness * 100).toInt();
    return AnimatedOpacity(
      opacity: _showBrightnessHud ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.brightness_medium_rounded, color: Colors.white, size: 28),
              const SizedBox(height: 8),
              Container(
                width: 6,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 80 * _brightness,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ---------------------------------------------------------------
              // Layer 1: The Video Player (Native ExoPlayer or Web Embed)
              // ---------------------------------------------------------------
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

              // ---------------------------------------------------------------
              // Layer 2: Netflix Dynamic Brightness Dimming Overlay
              // ---------------------------------------------------------------
              IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  color: Colors.black.withValues(alpha: (1.0 - _brightness).clamp(0.0, 0.8)),
                ),
              ),

              // ---------------------------------------------------------------
              // Layer 3: Gesture Detectors (Tap, Double Tap, Vertical Drag Brightness)
              // ---------------------------------------------------------------
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onVerticalDragUpdate: (details) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    if (details.globalPosition.dx < screenWidth * 0.3) {
                      _adjustBrightness(-details.primaryDelta! / 250);
                    }
                  },
                  onDoubleTapDown: (details) {
                    if (_isLocked) return;
                    final width = MediaQuery.of(context).size.width;
                    if (details.localPosition.dx < width / 2) {
                      _seekRelative(-10);
                    } else {
                      _seekRelative(10);
                    }
                  },
                ),
              ),

              // ---------------------------------------------------------------
              // Layer 4: Loading & Buffering Overlays
              // ---------------------------------------------------------------
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
                              ? 'Extracting multi-audio direct stream...'
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

              if (!_isLoading && _isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryRed),
                ),

              // ---------------------------------------------------------------
              // Layer 5: Live Subtitles Display (Netflix Typography)
              // ---------------------------------------------------------------
              if (_activeCueText != null && _activeCueText!.isNotEmpty)
                Positioned(
                  left: 32,
                  right: 32,
                  bottom: _showControls ? 88 : 28,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _activeCueText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 6: Double Tap Seek Feedback Ripple
              // ---------------------------------------------------------------
              if (_doubleTapSeekSeconds != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: _doubleTapSeekSeconds! < 0 ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 60),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _doubleTapSeekSeconds! < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _doubleTapSeekSeconds! < 0 ? '-10s' : '+10s',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 7: Brightness HUD
              // ---------------------------------------------------------------
              if (_showBrightnessHud)
                Positioned(
                  left: 36,
                  top: 0,
                  bottom: 0,
                  child: _buildBrightnessHud(),
                ),

              // ---------------------------------------------------------------
              // Layer 8: Screen Locked Pill
              // ---------------------------------------------------------------
              if (_isLocked && _showLockPill)
                Center(
                  child: InkWell(
                    onTap: _toggleScreenLock,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white30, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 15,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Screen Locked • Tap to Unlock',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 9: Netflix Player Chrome Controls
              // ---------------------------------------------------------------
              if (_showControls && !_isLocked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.92),
                        ],
                        stops: const [0.0, 0.42, 1.0],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // --- Top Bar ---
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
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
                                            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                              // Lock Screen button
                              IconButton(
                                icon: const Icon(Icons.lock_outline_rounded, color: Colors.white),
                                tooltip: 'Lock Screen',
                                onPressed: _toggleScreenLock,
                              ),
                              // Reload stream button
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                tooltip: 'Reload',
                                onPressed: () {
                                  _startHideControlsTimer();
                                  _loadMedia();
                                },
                              ),
                            ],
                          ),
                        ),

                        // --- Center Controls (10s Rewind, Big Play/Pause, 10s Forward) ---
                        if (_isNativeMode)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 46,
                                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                                tooltip: 'Rewind 10s',
                                onPressed: () => _seekRelative(-10),
                              ),
                              const SizedBox(width: 36),
                              GestureDetector(
                                onTap: _togglePlayPause,
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryRed,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryRed.withValues(alpha: 0.55),
                                        blurRadius: 22,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    size: 42,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 36),
                              IconButton(
                                iconSize: 46,
                                icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                                tooltip: 'Forward 10s',
                                onPressed: () => _seekRelative(10),
                              ),
                            ],
                          )
                        else
                          const SizedBox.shrink(),

                        // --- Bottom Controls (Scrubber + Netflix Action Row) ---
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Timeline Scrubber
                              if (_isNativeMode && _totalDuration > Duration.zero)
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
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
                                            setState(() => _dragPositionSec = val);
                                          },
                                          onChangeEnd: (val) {
                                            setState(() => _isDraggingSeekbar = false);
                                            _videoPlayerController?.seekTo(Duration(seconds: val.toInt()));
                                            _startHideControlsTimer();
                                          },
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatRemaining(
                                        _isDraggingSeekbar
                                            ? Duration(seconds: _dragPositionSec.toInt())
                                            : _currentPosition,
                                        _totalDuration,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),

                              // Netflix Bottom Actions Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Lock
                                  _NetflixBarButton(
                                    icon: Icons.lock_outline_rounded,
                                    label: 'Lock',
                                    onTap: _toggleScreenLock,
                                  ),

                                  // Speed
                                  _NetflixBarButton(
                                    icon: Icons.speed_rounded,
                                    label: 'Speed (${_playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x'})',
                                    onTap: _openSpeedSheet,
                                  ),

                                  // Quality
                                  if (_availableQualities.isNotEmpty)
                                    _NetflixBarButton(
                                      icon: Icons.tune_rounded,
                                      label: 'Quality (${_availableQualities[_selectedQualityIndex].label})',
                                      onTap: _openQualitySheet,
                                    ),

                                  // Audio & Subtitles
                                  _NetflixBarButton(
                                    icon: Icons.subtitles_rounded,
                                    label: 'Audio & Subtitles',
                                    onTap: _openAudioAndSubtitlesSheet,
                                  ),

                                  // Episodes (TV)
                                  if (widget.mediaType == 'tv')
                                    _NetflixBarButton(
                                      icon: Icons.grid_view_rounded,
                                      label: 'Episodes',
                                      onTap: _openEpisodesSheet,
                                    ),

                                  // Prev Ep (TV)
                                  if (widget.mediaType == 'tv' && _currentEpisode > 1)
                                    _NetflixBarButton(
                                      icon: Icons.skip_previous_rounded,
                                      label: 'Prev Ep.',
                                      onTap: _prevEpisode,
                                    ),

                                  // Next Ep (TV)
                                  if (widget.mediaType == 'tv')
                                    _NetflixBarButton(
                                      icon: Icons.skip_next_rounded,
                                      label: 'Next Ep.',
                                      onTap: _nextEpisode,
                                    ),

                                  // Server
                                  _NetflixBarButton(
                                    icon: Icons.dns_rounded,
                                    label: 'Server',
                                    onTap: _openServerPicker,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 10: Autoplay Next Countdown Card
              // ---------------------------------------------------------------
              if (_showAutoplayCard)
                Positioned(
                  bottom: 24,
                  right: 20,
                  child: _buildAutoplayNextCard(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetflixBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NetflixBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 3),
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
      ),
    );
  }
}
