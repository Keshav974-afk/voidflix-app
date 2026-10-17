import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/clip_export_service.dart';
import '../core/services/stream_extractor.dart';
import '../core/services/subtitle_service.dart';
import '../core/services/watch_party_service.dart';
import '../core/utils/language_utils.dart';
import '../core/utils/platform_utils.dart';
import '../models/media_detail.dart';
import '../models/server_config.dart';
import '../models/watch_progress.dart';
import '../providers/history_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/netflix_season_picker.dart';
import '../widgets/cast_dialog.dart';
import '../core/services/cast_service.dart';
import 'package:share_plus/share_plus.dart';

class PlayerScreen extends StatefulWidget {
  final int mediaId;
  final String mediaTitle;
  final String mediaType; // 'movie' or 'tv'
  final int season;
  final int episode;
  final String? posterPath;
  final String? backdropPath;
  final String? localFilePath;
  final String? localSubtitlePath;

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
    this.localSubtitlePath,
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
  final Set<int> _triedNativeServerIndices = {};
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
  bool _isDeveloperMode = false;
  bool _isStreamUnavailable = false;

  // Double tap seek ripple indicator
  int? _doubleTapSeekSeconds;
  Timer? _doubleTapTimer;
  int _cumulativeSeekSeconds = 0;
  DateTime? _lastDoubleTapTime;

  // Full-screen Zoom to fill system
  bool _isZoomedToFill = false;
  bool _showZoomHud = false;
  Timer? _zoomHudTimer;

  // Clip a Moment system (Netflix feature)
  bool _isClippingMoment = false;
  double _clipStartSeconds = 0.0;
  double _clipEndSeconds = 41.0;
  bool _isExportingClip = false;
  double _exportProgress = 0.0;

  // Autoplay Next Episode system
  bool _showAutoplayCard = false;
  int _autoplayCountdown = 5;
  Timer? _autoplayTimer;

  // TV show series data
  List<TvSeason> _seasons = [];
  List<TvEpisode> _episodes = [];
  bool _isLoadingEpisodes = false;

  // Picture-in-Picture mode
  bool _isInPipMode = false;

  // Hold to 2x speed system
  bool _isHolding2xSpeed = false;
  double _savedSpeedBeforeHold = 1.0;

  // Skip Intro system (Netflix feature)
  bool _showSkipIntro = false;
  bool _hasSkippedIntroForThisEp = false;
  bool _hasCancelledAutoplayForThisEp = false;

  // Watch Party / Sync Play system (Native Player Exclusive)
  final WatchPartyService _partyService = WatchPartyService();
  WatchPartyRoom? _partyRoom;
  bool _isInParty = false;
  Timer? _partySyncTimer;
  late final String _partyMemberId;
  String _partyMemberName = 'You';
  final List<WatchPartyMessage> _floatingPartyMessages = [];
  Timer? _floatingMsgTimer;
  int _lastProcessedMsgTimestamp = 0;
  String? _partyHudMessage;
  IconData _partyHudIcon = Icons.group_rounded;
  Color _partyHudAccent = const Color(0xFFE50914);
  Timer? _partyHudTimer;
  bool _isSyncSeeking = false;

  // Android TV / Remote Control support
  final FocusNode _playerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    final savedServer = context.read<ProfileProvider>().selectedServerIndex;
    _selectedServerIndex = (savedServer >= 0 && savedServer < ServerConfig.servers.length)
        ? savedServer
        : 0;

    _partyMemberId = 'usr_${DateTime.now().millisecondsSinceEpoch % 100000}';
    final activeProfile = context.read<ProfileProvider>().activeProfileOrNull;
    if (activeProfile != null && activeProfile.name.isNotEmpty) {
      _partyMemberName = activeProfile.name;
    }

    // Lock firmly to immersive fullscreen landscape mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Keep screen awake while watching video
    WakelockPlus.enable();

    // Listen for Picture-in-Picture mode transitions from Android OS
    const MethodChannel('org.voidflix/notifications').setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        final bool inPip = call.arguments == true;
        if (mounted) {
          setState(() {
            _isInPipMode = inPip;
            if (inPip) {
              _showControls = false;
            }
          });
        }
      }
    });

    _loadMedia();

    if (widget.mediaType == 'tv') {
      _fetchTvDetailsAndEpisodes();
    }

    _startHideControlsTimer();
  }

  @override
  void dispose() {
    const MethodChannel('org.voidflix/notifications').setMethodCallHandler(null);
    _partySyncTimer?.cancel();
    _floatingMsgTimer?.cancel();
    _partyHudTimer?.cancel();
    _playerFocusNode.dispose();
    if (_isInParty && _partyRoom != null) {
      _partyService.leaveRoom(_partyRoom!.roomCode, _partyMemberId);
    }
    _recordWatchProgress(force: true);
    _hideControlsTimer?.cancel();
    _lockPillTimer?.cancel();
    _brightnessHudTimer?.cancel();
    _doubleTapTimer?.cancel();
    _zoomHudTimer?.cancel();
    _autoplayTimer?.cancel();
    _disposeVideoController();

    // Release screen wakelock
    WakelockPlus.disable();

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

  Future<void> _loadLocalFile(String filePath) async {
    _disposeVideoController();
    setState(() {
      _isExtracting = false;
      _isLoading = true;
      _isNativeMode = true;
      _availableQualities = [
        StreamQuality(label: 'Offline (Downloaded)', height: 1080, url: filePath),
      ];
      _selectedQualityIndex = 0;
    });

    try {
      final controller = VideoPlayerController.file(File(filePath));
      _videoPlayerController = controller;
      await controller.initialize();

      if (!mounted) return;

      controller.addListener(_videoPlayerListener);

      Duration? resumePos;
      final saved = context.read<HistoryProvider>().getProgress(widget.mediaId);
      if (saved != null &&
          (widget.mediaType != 'tv' || (saved.season == _currentSeason && saved.episode == _currentEpisode)) &&
          saved.progress > 0.02 &&
          saved.progress < 0.95) {
        final totalMs = controller.value.duration.inMilliseconds;
        if (totalMs > 0) {
          resumePos = Duration(milliseconds: (saved.progress * totalMs).round());
        }
      }

      if (resumePos != null && resumePos > Duration.zero) {
        await controller.seekTo(resumePos);
      }

      await controller.setPlaybackSpeed(_playbackSpeed);
      await controller.play();

      setState(() {
        _isLoading = false;
        _isPlaying = true;
        _totalDuration = controller.value.duration;
        _currentPosition = controller.value.position;
      });

      _startHideControlsTimer();

      // Automatically discover and load offline subtitles for this video
      _loadOfflineSubtitles(filePath);
    } catch (e) {
      debugPrint('Error loading local file video: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOfflineSubtitles(String videoFilePath) async {
    try {
      final subs = <SubtitleTrack>[];
      final seenUrls = <String>{};

      void addSub(String label, String lang, String path) {
        if (!seenUrls.contains(path) && File(path).existsSync()) {
          seenUrls.add(path);
          subs.add(SubtitleTrack(
            label: label,
            language: lang,
            url: path,
          ));
        }
      }

      // 1. Direct param passed to widget
      if (widget.localSubtitlePath != null && widget.localSubtitlePath!.isNotEmpty) {
        addSub('English', 'en', widget.localSubtitlePath!);
      }

      // 2. Query DownloadProvider for matching DownloadedItem
      final downloadProvider = context.read<DownloadProvider>();
      final itemId = widget.mediaType == 'tv'
          ? 'tv_${widget.mediaId}_${_currentSeason}_$_currentEpisode'
          : 'movie_${widget.mediaId}';
      final item = downloadProvider.getItem(itemId) ??
          downloadProvider.getItemByPath(videoFilePath);

      if (item?.localSubtitlePath != null && item!.localSubtitlePath!.isNotEmpty) {
        addSub('Subtitles', 'en', item.localSubtitlePath!);
      }

      // 3. Check for manifest file: <id>_subs.json in the same folder
      final videoFile = File(videoFilePath);
      final dir = videoFile.parent;

      final manifestFiles = [
        File('${dir.path}/${itemId}_subs.json'),
        File('${videoFilePath.replaceAll(RegExp(r'\.[^.]+$'), '')}_subs.json'),
      ];

      for (final mFile in manifestFiles) {
        if (mFile.existsSync()) {
          try {
            final content = mFile.readAsStringSync();
            final parsed = jsonDecode(content);
            if (parsed is List) {
              for (final entry in parsed) {
                if (entry is Map) {
                  final label = (entry['label'] as String?) ?? 'Subtitle';
                  final lang = (entry['language'] as String?) ?? 'en';
                  final path = entry['path'] as String?;
                  if (path != null) {
                    addSub(label, lang, path);
                  }
                }
              }
            }
          } catch (_) {}
        }
      }

      // 4. Scan disk directory for any matching subtitles (.vtt or .srt)
      if (dir.existsSync()) {
        try {
          final entries = dir.listSync();
          for (final entity in entries) {
            if (entity is File) {
              final path = entity.path;
              if (path.endsWith('.vtt') || path.endsWith('.srt')) {
                final base = path.split(Platform.pathSeparator).last;
                if (base.contains(itemId) || base.contains(widget.mediaId.toString())) {
                  final parts = base.replaceAll(RegExp(r'\.(vtt|srt)$'), '').split('_sub_');
                  final langLabel = parts.length > 1 ? parts.last : 'Sub';
                  addSub(langLabel, langLabel.toLowerCase(), path);
                }
              }
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;

      if (subs.isNotEmpty) {
        setState(() {
          _subtitles = subs;
        });

        // Pick user preferred subtitle or default to first / English
        final profile = context.read<ProfileProvider>().activeProfile;
        final preferredSub = profile.preferredSubtitleLang;
        final preferredAudio = profile.preferredAudioLang;
        final preferredList = profile.preferredLanguages;

        final subPrefs = [
          if (preferredSub != null && preferredSub.isNotEmpty) preferredSub,
          if (preferredAudio != null && preferredAudio.isNotEmpty) preferredAudio,
          ...preferredList,
          'English',
          'en',
        ];

        final bestSub = LanguageUtils.pickBestSubtitle(
          subs,
          preferredLangs: subPrefs,
        );

        if (bestSub != null) {
          await _selectSubtitle(bestSub);
        } else {
          await _selectSubtitle(subs.first);
        }
      }
    } catch (e) {
      debugPrint('Error loading offline subtitles: $e');
    }
  }

  Future<void> _loadMedia() async {
    _cancelAutoplayTimer();

    // Check if playing an offline in-app download
    if (widget.localFilePath != null && File(widget.localFilePath!).existsSync()) {
      await _loadLocalFile(widget.localFilePath!);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _isDeveloperMode = prefs.getBool('voidflix_developer_mode') ?? false;

    int safeIdx = (_selectedServerIndex >= 0 && _selectedServerIndex < ServerConfig.servers.length)
        ? _selectedServerIndex
        : 0;

    // If developer mode is disabled, guarantee native direct server is chosen
    if (!_isDeveloperMode && !ServerConfig.servers[safeIdx].isDirectPlay) {
      final firstDirect = ServerConfig.servers.indexWhere((s) => s.isDirectPlay);
      safeIdx = firstDirect != -1 ? firstDirect : 0;
      _selectedServerIndex = safeIdx;
    }

    _triedNativeServerIndices.clear();
    final server = ServerConfig.servers[safeIdx];
    if (server.isDirectPlay) {
      await _loadServerDirect(safeIdx);
    } else {
      if (_isDeveloperMode) {
        _loadWebEmbed();
      } else {
        _handleAllNativeServersFailed();
      }
    }
  }

  void _fallbackToNextNativeOrEmbed({Duration? resumePosition}) {
    if (!mounted) return;

    // Search for another native direct-play server that hasn't been tried yet
    int nextNativeIdx = -1;
    for (int i = 0; i < ServerConfig.servers.length; i++) {
      if (ServerConfig.servers[i].isDirectPlay && !_triedNativeServerIndices.contains(i)) {
        nextNativeIdx = i;
        break;
      }
    }

    if (nextNativeIdx != -1) {
      final nextServer = ServerConfig.servers[nextNativeIdx];
      debugPrint('Native server failed. Trying next native server: ${nextServer.name}');
      _loadServerDirect(nextNativeIdx, startPosition: resumePosition);
      return;
    }

    // Only if ALL native direct play servers have been tried:
    debugPrint('All native direct servers exhausted.');
    if (_isDeveloperMode) {
      debugPrint('Developer mode enabled: falling back to web embed.');
      _switchToEmbedFallback();
    } else {
      debugPrint('Developer mode disabled: showing aesthetic unavailable screen.');
      _handleAllNativeServersFailed();
    }
  }

  void _handleAllNativeServersFailed() {
    _disposeVideoController();
    if (!mounted) return;
    setState(() {
      _isStreamUnavailable = true;
      _isLoading = false;
      _isExtracting = false;
    });
  }

  Future<void> _loadServerDirect(int serverIdx, {Duration? startPosition}) async {
    _triedNativeServerIndices.add(serverIdx);
    final server = ServerConfig.servers[serverIdx];
    setState(() {
      _selectedServerIndex = serverIdx;
      _isNativeMode = true;
      _isExtracting = true;
      _isLoading = true;
      _isStreamUnavailable = false;
      _activeCueText = null;
    });

    _disposeVideoController();

    try {
      List<ExtractedStream> streams = [];
      if (server.name.contains('Cine4K') || server.name.contains('Lisbon')) {
        streams = await StreamExtractor.extractCinejoy(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
          preferredServer: 'Lisbon',
        );
      } else if (server.name.contains('Nebula')) {
        streams = await StreamExtractor.extractCinejoy(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
          preferredServer: 'Nebula',
        );
      } else if (server.name.contains('OrionStream')) {
        final all = await StreamExtractor.extractVidrock(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
        streams = all.where((s) => s.sourceName.toLowerCase().contains('orion')).toList();
        if (streams.isEmpty) streams = all;
      } else if (server.name.contains('PulsarHD')) {
        streams = await StreamExtractor.extractVidrock(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
      } else if (server.name.contains('NovaStream')) {
        final all = await StreamExtractor.extractVidrock(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
        streams = all.where((s) => s.sourceName.toLowerCase() == 'nova').toList();
        if (streams.isEmpty) streams = all;
      } else if (server.name.contains('AtlasStream')) {
        final all = await StreamExtractor.extractVidrock(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
        streams = all.where((s) => s.sourceName.toLowerCase() == 'atlas').toList();
        if (streams.isEmpty) streams = all;
      } else if (server.name.contains('VoidHD')) {
        final v = await StreamExtractor.extractVidlink(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
        if (v != null) streams = [v];
      } else {
        // VoidDirect / default: multi-source extraction (Cinejoy + Vidrock in parallel)
        streams = await StreamExtractor.extractAll(
          type: widget.mediaType,
          tmdbId: widget.mediaId,
          season: _currentSeason,
          episode: _currentEpisode,
        );
      }

      if (!mounted) return;

      if (streams.isNotEmpty) {
        _directStreams = streams;

        // Retrieve active profile language preferences
        final profile = context.read<ProfileProvider>().activeProfile;
        final preferredAudio = profile.preferredAudioLang;
        final preferredSub = profile.preferredSubtitleLang;
        final preferredList = profile.preferredLanguages;

        final audioPrefs = [
          if (preferredAudio != null && preferredAudio.isNotEmpty) preferredAudio,
          ...preferredList,
        ];
        final subPrefs = [
          if (preferredSub != null && preferredSub.isNotEmpty) preferredSub,
          if (preferredAudio != null && preferredAudio.isNotEmpty) preferredAudio,
          ...preferredList,
        ];

        // 1. Pick audio stream index with user priority (profile -> English -> any)
        final chosenAudioIdx = LanguageUtils.pickBestAudioIndex(
          streams,
          preferredLangs: audioPrefs,
        );
        _selectedStreamIndex = chosenAudioIdx;

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

        // If the extracted stream cluster (e.g. NovaStream, AtlasStream, PulsarHD) has no embedded subtitles,
        // borrow cached subtitles from other providers (Vidlink, Voidflix)
        if (allSubs.isEmpty) {
          final shared = await StreamExtractor.getSharedSubtitles(
            widget.mediaType,
            widget.mediaId,
            _currentSeason,
            _currentEpisode,
          );
          for (final sub in shared) {
            if (!seenSubUrls.contains(sub.url)) {
              seenSubUrls.add(sub.url);
              allSubs.add(sub);
            }
          }
        }
        _subtitles = allSubs;

        // 2. Pick subtitle with user priority (profile -> English -> any)
        final bestSub = LanguageUtils.pickBestSubtitle(
          allSubs,
          preferredLangs: subPrefs,
        );
        if (bestSub != null) {
          _selectSubtitle(bestSub);
        }

        await _initNativePlayer(streams[chosenAudioIdx], startPosition: startPosition);
      } else {
        debugPrint('Direct extraction for ${server.name} returned 0 streams. Trying next native server.');
        _fallbackToNextNativeOrEmbed(resumePosition: startPosition);
      }
    } catch (e) {
      debugPrint('Direct extraction error for ${server.name}: $e');
      if (mounted) {
        _fallbackToNextNativeOrEmbed(resumePosition: startPosition);
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

      Duration? resumePos = startPosition;
      if (resumePos == null) {
        final saved = context.read<HistoryProvider>().getProgress(widget.mediaId);
        if (saved != null &&
            (widget.mediaType != 'tv' || (saved.season == _currentSeason && saved.episode == _currentEpisode)) &&
            saved.progress > 0.02 &&
            saved.progress < 0.95) {
          final totalMs = controller.value.duration.inMilliseconds;
          if (totalMs > 0) {
            resumePos = Duration(milliseconds: (saved.progress * totalMs).round());
          }
        }
      }

      if (resumePos != null && resumePos > Duration.zero) {
        await controller.seekTo(resumePos);
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
        _fallbackToNextNativeOrEmbed(resumePosition: startPosition);
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
    if (val.hasError) {
      debugPrint('Native playback error: ${val.errorDescription}');
      if (_selectedStreamIndex + 1 < _directStreams.length) {
        _selectedStreamIndex++;
        _initNativePlayer(_directStreams[_selectedStreamIndex], startPosition: _currentPosition, autoPlay: true);
      } else {
        _fallbackToNextNativeOrEmbed(resumePosition: _currentPosition);
      }
      return;
    }

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

      // Record real watch progress as playback progresses
      if (val.isInitialized && val.duration.inSeconds > 10) {
        final curMs = val.position.inMilliseconds;
        final totMs = val.duration.inMilliseconds;
        if (curMs > 3000 && totMs > 0) {
          _recordWatchProgress();
        }
      }
    }

    // Looping clip moment playback
    if (_isClippingMoment) {
      if (val.position.inSeconds >= _clipEndSeconds.toInt()) {
        controller.seekTo(Duration(seconds: _clipStartSeconds.toInt()));
      }
    }

    // Skip Intro button detection (seconds 12 to 95 for media longer than 5 mins)
    if (val.isInitialized && val.duration.inSeconds > 300) {
      final posSec = val.position.inSeconds;
      final shouldShowIntro = posSec >= 12 && posSec <= 95 && !_hasSkippedIntroForThisEp;
      if (shouldShowIntro != _showSkipIntro) {
        setState(() => _showSkipIntro = shouldShowIntro);
      }
    } else if (_showSkipIntro) {
      setState(() => _showSkipIntro = false);
    }

    // Auto-detect stream completion for TV episode autoplay (triggers during end credits, last 70s)
    if (val.isInitialized && val.duration > const Duration(seconds: 120)) {
      final remaining = val.duration - val.position;
      if (remaining <= const Duration(seconds: 70) &&
          remaining >= const Duration(seconds: 1) &&
          !_showAutoplayCard &&
          !_hasCancelledAutoplayForThisEp &&
          widget.mediaType == 'tv') {
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
    if (_selectedServerIndex < 0 ||
        _selectedServerIndex >= ServerConfig.servers.length ||
        ServerConfig.servers[_selectedServerIndex].isDirectPlay) {
      final firstEmbed = ServerConfig.servers.indexWhere((s) => !s.isDirectPlay);
      _selectedServerIndex = firstEmbed != -1 ? firstEmbed : 0;
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
    if (_selectedServerIndex < 0 || _selectedServerIndex >= ServerConfig.servers.length) {
      final firstEmbed = ServerConfig.servers.indexWhere((s) => !s.isDirectPlay);
      _selectedServerIndex = firstEmbed != -1 ? firstEmbed : 0;
    }
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
    if (!PlatformUtils.isWebViewSupported) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isWebViewLoading = false;
        });
      }
      return;
    }
    final url = _buildCurrentEmbedUrl();

    // Ensure webview loading screen dismisses promptly within 4 seconds
    Timer(const Duration(seconds: 4), () {
      if (mounted && _isWebViewLoading) {
        setState(() {
          _isLoading = false;
          _isWebViewLoading = false;
        });
      }
    });

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

  void _seekRelative(int seconds, {bool triggerFeedback = true}) {
    _startHideControlsTimer();
    final controller = _videoPlayerController;
    if (controller == null) return;

    final newPos = controller.value.position + Duration(seconds: seconds);
    final clamped = Duration(
      seconds: newPos.inSeconds.clamp(0, controller.value.duration.inSeconds),
    );
    controller.seekTo(clamped);

    if (triggerFeedback) {
      setState(() => _doubleTapSeekSeconds = seconds);
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _doubleTapSeekSeconds = null);
      });
    }
  }

  void _handleDoubleTapSeek(bool isForward) {
    final now = DateTime.now();
    if (_lastDoubleTapTime != null && now.difference(_lastDoubleTapTime!).inMilliseconds < 750) {
      _cumulativeSeekSeconds += isForward ? 10 : -10;
    } else {
      _cumulativeSeekSeconds = isForward ? 10 : -10;
    }
    _lastDoubleTapTime = now;

    _seekRelative(isForward ? 10 : -10, triggerFeedback: false);

    setState(() => _doubleTapSeekSeconds = _cumulativeSeekSeconds);
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _doubleTapSeekSeconds = null;
          _cumulativeSeekSeconds = 0;
        });
      }
    });
  }

  void _setZoom(bool zoomToFill) {
    if (_isZoomedToFill == zoomToFill) return;
    setState(() {
      _isZoomedToFill = zoomToFill;
      _showZoomHud = true;
    });
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showZoomHud = false);
    });
  }

  void _toggleZoom() {
    _setZoom(!_isZoomedToFill);
  }

  void _openClipMoment() {
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;

    _hideControlsTimer?.cancel();
    final totalSec = controller.value.duration.inSeconds.toDouble();
    if (totalSec <= 0) return;

    final curSec = controller.value.position.inSeconds.toDouble();
    double start = curSec;
    double end = curSec + 30.0;
    if (end > totalSec) {
      end = totalSec;
      start = (end - 30.0).clamp(0.0, totalSec);
    }
    if (end - start > 300.0) {
      end = start + 300.0;
    }

    setState(() {
      _isClippingMoment = true;
      _clipStartSeconds = start;
      _clipEndSeconds = end;
      _showControls = false;
    });

    controller.seekTo(Duration(seconds: start.toInt()));
    controller.play();
  }

  Future<void> _saveClip() async {
    if (_isExportingClip) return;

    setState(() {
      _isExportingClip = true;
      _exportProgress = 0.05;
    });

    final activeStream = _directStreams.isNotEmpty && _selectedStreamIndex < _directStreams.length
        ? _directStreams[_selectedStreamIndex]
        : null;

    final playingUrl = (_availableQualities.isNotEmpty && _selectedQualityIndex < _availableQualities.length)
        ? _availableQualities[_selectedQualityIndex].url
        : activeStream?.url;

    final hasSubtitles = _selectedSubtitle != null && _currentCues.isNotEmpty;
    final subtitleCues = <Map<String, dynamic>>[];
    if (hasSubtitles) {
      final clipStartMs = (_clipStartSeconds * 1000).toInt();
      final clipEndMs = (_clipEndSeconds * 1000).toInt();
      for (final cue in _currentCues) {
        if (cue.endMs >= clipStartMs && cue.startMs <= clipEndMs) {
          subtitleCues.add({
            'start': cue.startMs,
            'end': cue.endMs,
            'text': cue.text,
          });
        }
      }
    }

    try {
      final exportedFile = await ClipExportService.exportClip(
        title: widget.mediaTitle,
        startSeconds: _clipStartSeconds,
        endSeconds: _clipEndSeconds,
        localFilePath: widget.localFilePath,
        streamUrl: playingUrl,
        streamHeaders: activeStream?.headers,
        subtitles: subtitleCues,
        burnSubtitles: hasSubtitles,
        onProgress: (p, status) {
          if (mounted) {
            setState(() {
              _exportProgress = p;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isExportingClip = false;
          _isClippingMoment = false;
          _showControls = true;
        });
        _startHideControlsTimer();

        if (exportedFile != null) {
          SharePlus.instance.share(
            ShareParams(
              files: [XFile(exportedFile.path)],
              text: 'Watch this moment from "${widget.mediaTitle}" on Voidflix!\nhttps://voidflix.org/${widget.mediaType}/${widget.mediaId}',
              subject: 'Voidflix Moment: ${widget.mediaTitle}',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving clip: $e');
      if (mounted) {
        setState(() {
          _isExportingClip = false;
        });
      }
    }
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
    WakelockPlus.disable();

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

  DateTime? _lastProgressSaveTime;
  double _lastSavedProgress = 0.0;

  void _recordWatchProgress({double? customProgress, bool force = false}) {
    if (!mounted) return;
    final controller = _videoPlayerController;
    double prog = customProgress ?? 0.0;

    if (customProgress == null && controller != null && controller.value.isInitialized) {
      final totalMs = controller.value.duration.inMilliseconds;
      final curMs = controller.value.position.inMilliseconds;
      if (totalMs > 0) {
        prog = (curMs / totalMs).clamp(0.0, 1.0);
      }
    }

    // Do not record unplayed media (< 2%) unless forced with a positive progress
    if (prog < 0.02 && !force) return;

    final now = DateTime.now();
    // Throttle automatic progress saves to once every 5 seconds
    if (!force && _lastProgressSaveTime != null) {
      if (now.difference(_lastProgressSaveTime!).inSeconds < 5 && (prog - _lastSavedProgress).abs() < 0.03) {
        return;
      }
    }

    _lastProgressSaveTime = now;
    _lastSavedProgress = prog;

    final cleanTitle = widget.mediaTitle.replaceAll(RegExp(r':\s*S\d+.*$', caseSensitive: false), '').trim();
    final progress = WatchProgress(
      id: widget.mediaId,
      title: cleanTitle.isNotEmpty ? cleanTitle : widget.mediaTitle,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
      mediaType: widget.mediaType,
      season: _currentSeason,
      episode: _currentEpisode,
      progress: prog,
      lastWatched: now,
    );
    context.read<HistoryProvider>().saveProgress(progress);
  }

  void _goToEpisode(int episodeNum) {
    _recordWatchProgress(force: true);
    _cancelAutoplayTimer();
    setState(() {
      _currentEpisode = episodeNum;
      _showSkipIntro = false;
      _hasSkippedIntroForThisEp = false;
      _hasCancelledAutoplayForThisEp = false;
    });
    _loadMedia();
  }

  void _skipIntro() {
    HapticFeedback.mediumImpact();
    final targetSec = _currentPosition.inSeconds < 95 ? 95 : _currentPosition.inSeconds + 80;
    _videoPlayerController?.seekTo(Duration(seconds: targetSec));
    setState(() {
      _showSkipIntro = false;
      _hasSkippedIntroForThisEp = true;
    });
  }

  void _nextEpisode() {
    if (widget.mediaType != 'tv') return;
    _recordWatchProgress(force: true);
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
          _showSkipIntro = false;
          _hasSkippedIntroForThisEp = false;
          _hasCancelledAutoplayForThisEp = false;
        });
        _loadEpisodesForSeason(_currentSeason);
        _loadMedia();
      }
    }
  }

  void _triggerAutoplayNext() {
    if (widget.mediaType != 'tv' || _showAutoplayCard || _hasCancelledAutoplayForThisEp) return;
    _cancelAutoplayTimer();
    setState(() {
      _showAutoplayCard = true;
      _autoplayCountdown = 10;
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
    if (mounted) {
      setState(() {
        _showAutoplayCard = false;
        _hasCancelledAutoplayForThisEp = true;
      });
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
      isScrollControlled: true,
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
                height: MediaQuery.of(context).size.height * 0.82,
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
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Audio & Subtitles',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 8),
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
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                      final isSelected = idx == _selectedStreamIndex;
                                      final stream = _directStreams.isNotEmpty ? _directStreams[idx] : null;
                                      final langRaw = stream?.language ?? 'English';
                                      final langName = LanguageUtils.cleanLanguageName(langRaw);
                                      final sourceName = stream != null ? stream.sourceName : 'Original (Stereo)';

                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                        title: Text(
                                          langName,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.white70,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                        ),
                                        subtitle: Text(
                                          sourceName,
                                          style: const TextStyle(fontSize: 11, color: Colors.white38),
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
                          const SizedBox(width: 12),
                          // Right Column: SUBTITLES
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                      // Off Option
                                      ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
                                      if (_subtitles.isNotEmpty)
                                        ..._subtitles.map((track) {
                                          final isSelected = _selectedSubtitle?.url == track.url;
                                          final label = LanguageUtils.cleanLanguageName(
                                            track.label.isNotEmpty ? track.label : track.language,
                                          );

                                          return ListTile(
                                            dense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
                                              _selectSubtitle(track);
                                              Navigator.pop(ctx);
                                            },
                                          );
                                        })
                                      else
                                        const Padding(
                                          padding: EdgeInsets.only(top: 16, left: 8, right: 8),
                                          child: Text(
                                            'No external subtitles found for this stream',
                                            style: TextStyle(color: Colors.white38, fontSize: 12),
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
                          'DIRECT NATIVE SERVERS (EXTRACTABLE • NO ADS)',
                          style: TextStyle(color: AppTheme.primaryRed, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...List.generate(ServerConfig.servers.length, (idx) {
                        final s = ServerConfig.servers[idx];
                        if (!s.isDirectPlay) return const SizedBox.shrink();
                        final isSel = _isNativeMode && idx == _selectedServerIndex;
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
                          trailing: isSel
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryRed.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppTheme.primaryRed, width: 0.8),
                                  ),
                                  child: const Text('ACTIVE', style: TextStyle(color: AppTheme.primaryRed, fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            _triedNativeServerIndices.clear();
                            context.read<ProfileProvider>().setSelectedServer(idx);
                            _loadServerDirect(idx);
                          },
                        );
                      }),
                      if (_directStreams.isNotEmpty && _directStreams.length > 1) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(
                            'EXTRACTED AUDIO & CDN FEEDS',
                            style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...List.generate(_directStreams.length, (idx) {
                          final s = _directStreams[idx];
                          final isSel = _isNativeMode && idx == _selectedStreamIndex;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isSel ? Icons.check_circle : Icons.circle_outlined,
                              size: 18,
                              color: isSel ? AppTheme.primaryRed : Colors.white38,
                            ),
                            title: Text(
                              '${s.sourceName} • ${s.language}',
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white60,
                                fontSize: 13,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text('Direct ${s.type.toUpperCase()} stream', style: const TextStyle(fontSize: 10, color: Colors.white30)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _selectAudioSource(idx);
                            },
                          );
                        }),
                      ],
                      // Embed Fallbacks (Visible ONLY when Developer Mode is active)
                      if (_isDeveloperMode) ...[
                        const Divider(color: Colors.white12),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                          child: Row(
                            children: [
                              Text(
                                'ALTERNATIVE EMBED SERVERS',
                                style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(width: 6),
                              Text('(DEV MODE)', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w900)),
                            ],
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
                              color: isSel ? Colors.amber : Colors.white54,
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
                                _isStreamUnavailable = false;
                              });
                              context.read<ProfileProvider>().setSelectedServer(idx);
                              _loadWebEmbed();
                            },
                          );
                        }),
                      ],
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
    if (total <= Duration.zero) return '00:00';
    final diff = total - current;
    final s = diff.isNegative ? Duration.zero : diff;
    return _formatDuration(s);
  }

  String get _currentEpisodeTitle {
    if (widget.mediaType == 'tv') {
      final ep = _episodes.where((e) => e.episodeNumber == _currentEpisode).firstOrNull;
      final epName = ep != null && ep.name.isNotEmpty ? ep.name : 'Episode $_currentEpisode';
      return 'S$_currentSeason:E$_currentEpisode "$epName"';
    }
    return widget.mediaTitle;
  }

  // ---------------------------------------------------------------------------
  // Build Components
  // ---------------------------------------------------------------------------

  Widget _buildLeftBrightnessSlider() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        _adjustBrightness(-details.primaryDelta! / 140);
      },
      child: Container(
        width: 44,
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.light_mode_outlined,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 14),
            Container(
              width: 7,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 7,
                height: 120 * _brightness,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomHud() {
    return AnimatedOpacity(
      opacity: _showZoomHud ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: Text(
          _isZoomedToFill ? 'Zoomed to fill' : 'Original aspect ratio',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _startHold2xSpeed() {
    if (_isLocked || _videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    if (!_videoPlayerController!.value.isPlaying) return;
    HapticFeedback.selectionClick();
    _savedSpeedBeforeHold = _playbackSpeed;
    _videoPlayerController?.setPlaybackSpeed(2.0);
    setState(() {
      _isHolding2xSpeed = true;
      _showControls = false;
    });
  }

  void _stopHold2xSpeed() {
    if (!_isHolding2xSpeed) return;
    _videoPlayerController?.setPlaybackSpeed(_savedSpeedBeforeHold);
    setState(() {
      _isHolding2xSpeed = false;
    });
  }

  Future<void> _enterPipMode() async {
    if (_isLocked || _videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;
    try {
      setState(() {
        _showControls = false;
        _isInPipMode = true;
      });
      const channel = MethodChannel('org.voidflix/notifications');
      final bool? success = await channel.invokeMethod<bool>('enterPip');
      if (success != true && mounted) {
        setState(() => _isInPipMode = false);
      }
    } catch (e) {
      debugPrint('Error entering PiP mode: $e');
      if (mounted) setState(() => _isInPipMode = false);
    }
  }

  void _openCastDialog() {
    String? streamUrl;
    if (widget.localFilePath != null && widget.localFilePath!.isNotEmpty) {
      streamUrl = widget.localFilePath;
    } else if (_directStreams.isNotEmpty && _selectedStreamIndex < _directStreams.length) {
      streamUrl = _directStreams[_selectedStreamIndex].url;
    }
    if (streamUrl == null || streamUrl.isEmpty) {
      return;
    }

    CastDialog.show(
      context,
      videoUrl: streamUrl,
      title: _currentEpisodeTitle,
      posterUrl: widget.posterPath,
      currentPosition: _currentPosition,
      headers: _directStreams.isNotEmpty && _selectedStreamIndex < _directStreams.length
          ? _directStreams[_selectedStreamIndex].headers
          : null,
    );
  }

  Widget _build2xSpeedHud() {
    return AnimatedOpacity(
      opacity: _isHolding2xSpeed ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fast_forward_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 16,
            ),
            const SizedBox(width: 6),
            const Text(
              '2X Speed',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipMomentView() {
    final totalSec = _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds.toDouble() : 100.0;
    final curSec = _currentPosition.inSeconds.toDouble();

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar: Back, Title, Save button (Screenshot 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    onPressed: () {
                      setState(() => _isClippingMoment = false);
                      _startHideControlsTimer();
                    },
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Clip a Moment',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _isExportingClip ? null : _saveClip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isExportingClip ? const Color(0xFF2E2E2E) : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _isExportingClip
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Saving ${(_exportProgress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Center section: Start Time, 16:9 Preview card, End Time (Screenshot 2)
            Expanded(
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Start Column (Green label + Time)
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Start',
                            style: TextStyle(
                              color: Color(0xFF2ECC71),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDuration(Duration(seconds: _clipStartSeconds.toInt())),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Center Preview Card (16:9 framed video)
                    Container(
                      width: 380,
                      height: 380 * 9 / 16,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.white24, width: 1.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
                            Center(
                              child: AspectRatio(
                                aspectRatio: _videoPlayerController!.value.aspectRatio,
                                child: VideoPlayer(_videoPlayerController!),
                              ),
                            ),
                          // Live Subtitles inside preview (Screenshot 2)
                          if (_activeCueText != null && _activeCueText!.isNotEmpty)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 24,
                              child: Directionality(
                                textDirection: RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]').hasMatch(_activeCueText!)
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                child: Text(
                                  _activeCueText!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamilyFallback: [
                                      'Noto Sans Devanagari',
                                      'Noto Nastaliq Urdu',
                                      'Noto Sans Arabic',
                                      'Mangal',
                                      'Arial',
                                      'sans-serif',
                                    ],
                                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                  ),
                                ),
                              ),
                            ),
                          // Bottom controls inside preview: Pause/Play bottom-left, Replay bottom-right
                          Positioned(
                            left: 6,
                            bottom: 4,
                            child: IconButton(
                              iconSize: 26,
                              icon: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                              onPressed: _togglePlayPause,
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 4,
                            child: IconButton(
                              iconSize: 24,
                              icon: const Icon(Icons.replay_rounded, color: Colors.white),
                              onPressed: () {
                                _videoPlayerController?.seekTo(Duration(seconds: _clipStartSeconds.toInt()));
                                _videoPlayerController?.play();
                              },
                            ),
                          ),
                          // Signature Voidflix Red Watermark (Netflix-style bottom-right)
                          Positioned(
                            right: 14,
                            bottom: 12,
                            child: IgnorePointer(
                              child: Text(
                                'VOIDFLIX',
                                style: TextStyle(
                                  color: AppTheme.primaryRed,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.2,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.95),
                                      blurRadius: 6,
                                      offset: const Offset(1, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // End Column (Red label + Time)
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'End',
                            style: TextStyle(
                              color: Color(0xFFE50914),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDuration(Duration(seconds: _clipEndSeconds.toInt())),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Current Playhead Time Label & Duration Badge below preview
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (_clipEndSeconds - _clipStartSeconds) >= 300.0
                          ? AppTheme.primaryRed.withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_clipEndSeconds - _clipStartSeconds) >= 300.0
                            ? AppTheme.primaryRed
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${_formatDuration(Duration(seconds: (_clipEndSeconds - _clipStartSeconds).toInt()))} / 5:00 max',
                      style: TextStyle(
                        color: (_clipEndSeconds - _clipStartSeconds) >= 300.0
                            ? const Color(0xFFFF6B6B)
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Filmstrip & Range Trimmer with Interactive Sliding Stick
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: SizedBox(
                height: 64,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    final startFraction = (_clipStartSeconds / totalSec).clamp(0.0, 1.0);
                    final endFraction = (_clipEndSeconds / totalSec).clamp(0.0, 1.0);
                    final curFraction = (curSec / totalSec).clamp(0.0, 1.0);

                    final leftPos = startFraction * trackWidth;
                    final rightPos = endFraction * trackWidth;
                    final playheadPos = curFraction * trackWidth;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Filmstrip background with tap-to-seek
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) {
                              final tapFraction = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
                              final tapSec = (tapFraction * totalSec).clamp(_clipStartSeconds, _clipEndSeconds);
                              _videoPlayerController?.seekTo(Duration(seconds: tapSec.toInt()));
                              setState(() {
                                _currentPosition = Duration(seconds: tapSec.toInt());
                              });
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                color: const Color(0xFF1E1E1E),
                                child: Row(
                                  children: List.generate(14, (idx) {
                                    return Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(2),
                                          image: widget.backdropPath != null
                                              ? DecorationImage(
                                                  image: CachedNetworkImageProvider(
                                                    ApiService.getImageUrl(widget.backdropPath, size: 'w300'),
                                                  ),
                                                  fit: BoxFit.cover,
                                                  opacity: 0.55,
                                                )
                                              : null,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Dimmed out regions outside selection
                        if (leftPos > 0)
                          Positioned(
                            left: 0,
                            width: leftPos,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),
                        if (rightPos < trackWidth)
                          Positioned(
                            left: rightPos,
                            width: (trackWidth - rightPos).clamp(0.0, trackWidth),
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),

                        // Selection Window (connecting top and bottom white bars)
                        if (rightPos > leftPos + 10)
                          Positioned(
                            left: leftPos,
                            width: (rightPos - leftPos).clamp(10.0, trackWidth),
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Colors.white, width: 2.5),
                                    bottom: BorderSide(color: Colors.white, width: 2.5),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // -------------------------------------------------------------
                        // Green Start Handle (draggable, min 2s before end, max 5m range)
                        // -------------------------------------------------------------
                        Positioned(
                          left: leftPos.clamp(0.0, trackWidth - 36),
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              final deltaSec = (details.delta.dx / trackWidth) * totalSec;
                              final minStart = (_clipEndSeconds - 300.0).clamp(0.0, totalSec);
                              final maxStart = _clipEndSeconds - 2.0;
                              setState(() {
                                _clipStartSeconds = (_clipStartSeconds + deltaSec).clamp(minStart, maxStart);
                              });
                              _videoPlayerController?.seekTo(Duration(seconds: _clipStartSeconds.toInt()));
                            },
                            child: Container(
                              width: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C853),
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(-1, 0),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 2.5,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Container(
                                      width: 2.5,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // -------------------------------------------------------------
                        // Red End Handle (draggable, min 2s after start, max 5m range)
                        // -------------------------------------------------------------
                        Positioned(
                          left: (rightPos - 34).clamp(leftPos + 34, trackWidth - 34),
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              final deltaSec = (details.delta.dx / trackWidth) * totalSec;
                              final minEnd = _clipStartSeconds + 2.0;
                              final maxEnd = (_clipStartSeconds + 300.0).clamp(0.0, totalSec);
                              setState(() {
                                _clipEndSeconds = (_clipEndSeconds + deltaSec).clamp(minEnd, maxEnd);
                              });
                              _videoPlayerController?.seekTo(Duration(seconds: _clipEndSeconds.toInt()));
                            },
                            child: Container(
                              width: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(1, 0),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 2.5,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Container(
                                      width: 2.5,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // -------------------------------------------------------------
                        // Interactive Sliding Stick Scrubber (LAST in Stack = on TOP)
                        // -------------------------------------------------------------
                        Positioned(
                          left: (playheadPos - 24).clamp(leftPos - 12, rightPos - 20),
                          top: -8,
                          bottom: -8,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              final deltaSec = (details.delta.dx / trackWidth) * totalSec;
                              final newSec = (curSec + deltaSec).clamp(_clipStartSeconds, _clipEndSeconds);
                              _videoPlayerController?.seekTo(Duration(seconds: newSec.toInt()));
                              setState(() {
                                _currentPosition = Duration(seconds: newSec.toInt());
                              });
                            },
                            child: SizedBox(
                              width: 48,
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  // White vertical scrubber needle
                                  Container(
                                    width: 3.5,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.8),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Top draggable circular grab knob
                                  Positioned(
                                    top: 0,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.7),
                                            blurRadius: 5,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE50914),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final safeIndex = (_selectedServerIndex >= 0 && _selectedServerIndex < ServerConfig.servers.length)
        ? _selectedServerIndex
        : 0;
    final currentServer = ServerConfig.servers[safeIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isClippingMoment) {
            setState(() => _isClippingMoment = false);
            _startHideControlsTimer();
          } else {
            _handleSmoothBack();
          }
        }
      },
      child: AnimatedOpacity(
        opacity: _isExiting ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: KeyboardListener(
          focusNode: _playerFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
            fit: StackFit.expand,
            children: [
              // ---------------------------------------------------------------
              // Layer 1: The Video Player (Native ExoPlayer or Web Embed) with Smooth Zoom
              // ---------------------------------------------------------------
              if (_isNativeMode &&
                  _videoPlayerController != null &&
                  _videoPlayerController!.value.isInitialized)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _isZoomedToFill
                      ? SizedBox.expand(
                          key: const ValueKey('zoom_fill'),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _videoPlayerController!.value.size.width > 0
                                  ? _videoPlayerController!.value.size.width
                                  : 16,
                              height: _videoPlayerController!.value.size.height > 0
                                  ? _videoPlayerController!.value.size.height
                                  : 9,
                              child: VideoPlayer(_videoPlayerController!),
                            ),
                          ),
                        )
                      : Center(
                          key: const ValueKey('zoom_fit'),
                          child: AspectRatio(
                            aspectRatio: _videoPlayerController!.value.aspectRatio,
                            child: VideoPlayer(_videoPlayerController!),
                          ),
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
              // Layer 3: Gesture Detectors (Tap, Double Tap Seek/Zoom, Pinch Zoom, Left Drag Brightness)
              // Only active in Native Mode
              // ---------------------------------------------------------------
              if (_isNativeMode && !_isClippingMoment && !_isInPipMode)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onLongPressStart: (_) => _startHold2xSpeed(),
                    onLongPressEnd: (_) => _stopHold2xSpeed(),
                    onLongPressCancel: () => _stopHold2xSpeed(),
                    onScaleStart: (details) {},
                    onScaleUpdate: (details) {
                      if (_isLocked) return;
                      if (details.pointerCount == 2) {
                        if (details.scale > 1.08 && !_isZoomedToFill) {
                          _setZoom(true);
                        } else if (details.scale < 0.92 && _isZoomedToFill) {
                          _setZoom(false);
                        }
                      } else if (details.pointerCount == 1) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        if (details.focalPoint.dx < screenWidth * 0.35) {
                          _adjustBrightness(-details.focalPointDelta.dy / 200);
                        }
                      }
                    },
                    onDoubleTapDown: (details) {
                      if (_isLocked) return;
                      final width = MediaQuery.of(context).size.width;
                      final dx = details.localPosition.dx;
                      if (dx < width * 0.38) {
                        _handleDoubleTapSeek(false); // -10s
                      } else if (dx > width * 0.62) {
                        _handleDoubleTapSeek(true); // +10s
                      } else {
                        _toggleZoom(); // Center double-tap: zoom toggle
                      }
                    },
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 4: Loading & Buffering Overlays
              // ---------------------------------------------------------------
              if (_isLoading && !_isClippingMoment && !_isStreamUnavailable)
                Container(
                  color: _isNativeMode ? Colors.black : Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.primaryRed),
                        const SizedBox(height: 16),
                        Text(
                          _isExtracting
                              ? 'Extracting multi-audio direct stream...'
                              : (_isNativeMode ? 'Connecting to stream...' : 'Loading web player...'),
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

              if (!_isLoading && _isBuffering && _isNativeMode && !_isClippingMoment && !_isStreamUnavailable)
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryRed),
                ),

              // ---------------------------------------------------------------
              // Layer 5: Live Subtitles Display (Netflix Typography)
              // ---------------------------------------------------------------
              if (_isNativeMode && _activeCueText != null && _activeCueText!.isNotEmpty && !_isClippingMoment)
                Positioned(
                  left: 32,
                  right: 32,
                  bottom: _showControls ? 88 : 28,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Directionality(
                          textDirection: RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]').hasMatch(_activeCueText!)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Text(
                            _activeCueText!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamilyFallback: [
                                'Noto Sans Devanagari',
                                'Noto Nastaliq Urdu',
                                'Noto Sans Arabic',
                                'Mangal',
                                'Kokila',
                                'Arial',
                                'sans-serif',
                              ],
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 6: Double Tap Seek Feedback Ripple
              // ---------------------------------------------------------------
              if (_isNativeMode && _doubleTapSeekSeconds != null && !_isClippingMoment)
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
                              _doubleTapSeekSeconds! < 0
                                  ? '-${_doubleTapSeekSeconds!.abs()}s'
                                  : '+${_doubleTapSeekSeconds!}s',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 7: Left Vertical Brightness Slider (Matching Screenshot 1)
              // ---------------------------------------------------------------
              if (_isNativeMode && (_showControls || _showBrightnessHud) && !_isLocked && !_isClippingMoment)
                Positioned(
                  left: 28,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildLeftBrightnessSlider(),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 7.5: Zoom to Fill HUD Badge
              // ---------------------------------------------------------------
              if (_isNativeMode && _showZoomHud && !_isClippingMoment)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildZoomHud(),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 8: Screen Locked Unlock Button (Transparent Glassy Disc)
              // ---------------------------------------------------------------
              if (_isNativeMode && _isLocked && _showLockPill && !_isClippingMoment)
                Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggleScreenLock,
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lock_open_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 9: Player Chrome Controls (Matching Screenshot 1)
              // ---------------------------------------------------------------
              if (_isNativeMode && !_isClippingMoment && !_isInPipMode) ...[
                if (_showControls && !_isLocked)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleControls,
                      onLongPressStart: (_) => _startHold2xSpeed(),
                      onLongPressEnd: (_) => _stopHold2xSpeed(),
                      onLongPressCancel: () => _stopHold2xSpeed(),
                      onScaleStart: (details) {},
                      onScaleUpdate: (details) {
                        if (details.pointerCount == 2) {
                          if (details.scale > 1.08 && !_isZoomedToFill) {
                            _setZoom(true);
                          } else if (details.scale < 0.92 && _isZoomedToFill) {
                            _setZoom(false);
                          }
                        } else if (details.pointerCount == 1) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          if (details.focalPoint.dx < screenWidth * 0.35) {
                            _adjustBrightness(-details.focalPointDelta.dy / 200);
                          }
                        }
                      },
                      onDoubleTapDown: (details) {
                        final width = MediaQuery.of(context).size.width;
                        final dx = details.localPosition.dx;
                        if (dx < width * 0.38) {
                          _handleDoubleTapSeek(false);
                        } else if (dx > width * 0.62) {
                          _handleDoubleTapSeek(true);
                        } else {
                          _toggleZoom();
                        }
                      },
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
                            // --- Top Bar (Matching Screenshot 1: Back, Centered Title, PiP, Lock) ---
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {},
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                                      onPressed: _handleSmoothBack,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          _currentEpisodeTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ListenableBuilder(
                                      listenable: CastService(),
                                      builder: (context, _) {
                                        final isCasting = CastService().isCasting;
                                        return IconButton(
                                          icon: Icon(
                                            isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                                            color: isCasting ? const Color(0xFF00D2FF) : Colors.white,
                                            size: 24,
                                          ),
                                          tooltip: isCasting ? 'Casting Active' : 'Cast to TV',
                                          onPressed: _openCastDialog,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 24),
                                      tooltip: 'Picture-in-Picture',
                                      onPressed: _enterPipMode,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 24),
                                      tooltip: 'Lock',
                                      onPressed: _toggleScreenLock,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // --- Center Controls (Matching Screenshot 1: 10s Rewind, Solid White Play/Pause, 10s Forward) ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  iconSize: 44,
                                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                                  tooltip: 'Rewind 10s',
                                  onPressed: () => _seekRelative(-10),
                                ),
                                const SizedBox(width: 48),
                                IconButton(
                                  iconSize: 68,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  tooltip: _isPlaying ? 'Pause' : 'Play',
                                  onPressed: _togglePlayPause,
                                ),
                                const SizedBox(width: 48),
                                IconButton(
                                  iconSize: 44,
                                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                                  tooltip: 'Forward 10s',
                                  onPressed: () => _seekRelative(10),
                                ),
                              ],
                            ),

                            // --- Bottom Controls (Matching Screenshot 1: Seekbar with remaining time, 5 actions) ---
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {},
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Seekbar
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              activeTrackColor: AppTheme.primaryRed,
                                              inactiveTrackColor: const Color(0xFF555555),
                                              thumbColor: AppTheme.primaryRed,
                                              trackHeight: 3.5,
                                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                            ),
                                            child: Slider(
                                              value: (_isDraggingSeekbar
                                                      ? _dragPositionSec
                                                      : _currentPosition.inSeconds.toDouble())
                                                  .clamp(0.0, _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds.toDouble() : 1.0),
                                              min: 0.0,
                                              max: _totalDuration.inSeconds > 0 ? _totalDuration.inSeconds.toDouble() : 1.0,
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
                                        const SizedBox(width: 12),
                                        Text(
                                          _formatRemaining(
                                            _isDraggingSeekbar
                                                ? Duration(seconds: _dragPositionSec.toInt())
                                                : _currentPosition,
                                            _totalDuration,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Bottom Actions Row (Matching Screenshot 1: Clip, Speed, Episodes, Audio & Subtitles, Next Ep.)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        _NetflixBarButton(
                                          icon: Icons.content_cut_rounded,
                                          label: 'Clip',
                                          onTap: _openClipMoment,
                                        ),
                                        _NetflixBarButton(
                                          icon: Icons.speed_rounded,
                                          label: 'Speed (${_playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x'})',
                                          onTap: _openSpeedSheet,
                                        ),
                                        if (widget.mediaType == 'tv')
                                          _NetflixBarButton(
                                            icon: Icons.view_carousel_outlined,
                                            label: 'Episodes',
                                            onTap: _openEpisodesSheet,
                                          )
                                        else if (_availableQualities.isNotEmpty)
                                          _NetflixBarButton(
                                            icon: Icons.tune_rounded,
                                            label: 'Quality',
                                            onTap: _openQualitySheet,
                                          ),
                                        _NetflixBarButton(
                                          icon: Icons.chat_bubble_outline_rounded,
                                          label: 'Audio & Subtitles',
                                          onTap: _openAudioAndSubtitlesSheet,
                                        ),
                                        if (widget.mediaType == 'tv')
                                          _NetflixBarButton(
                                            icon: Icons.skip_next_rounded,
                                            label: 'Next Ep.',
                                            onTap: _nextEpisode,
                                          )
                                        else
                                          _NetflixBarButton(
                                            icon: Icons.dns_rounded,
                                            label: 'Server',
                                            onTap: _openServerPicker,
                                          ),
                                        if (_isNativeMode)
                                          _NetflixBarButton(
                                            icon: _isInParty ? Icons.group_rounded : Icons.group_add_rounded,
                                            label: _isInParty ? 'Sync (${_partyRoom?.members.length ?? 1})' : 'Watch Party',
                                            color: _isInParty ? const Color(0xFF4CAF50) : null,
                                            onTap: _openWatchPartySheet,
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
                    ),
                  ),
              ] else if (!_isNativeMode) ...[
                // --- WEB EMBED MODE: Completely Unobstructed Direct Web Playback ---
                if (_showControls)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.9),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
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
                                        'Season $_currentSeason • Episode $_currentEpisode • ',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 0.8),
                                      ),
                                      child: Text(
                                        'Web Player: ${currentServer.name}',
                                        style: const TextStyle(
                                          color: Colors.lightBlueAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (widget.mediaType == 'tv')
                            IconButton(
                              icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                              tooltip: 'Episodes',
                              onPressed: _openEpisodesSheet,
                            ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.dns_rounded, size: 15),
                            label: const Text('Change Server', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: _openServerPicker,
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                            tooltip: 'Reload',
                            onPressed: () {
                              _startHideControlsTimer();
                              _webViewController?.reload();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            tooltip: 'Hide Bar',
                            onPressed: () {
                              setState(() => _showControls = false);
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            padding: const EdgeInsets.all(8),
                            tooltip: 'Back',
                            onPressed: _handleSmoothBack,
                          ),
                          InkWell(
                            onTap: () {
                              setState(() => _showControls = true);
                              _startHideControlsTimer();
                            },
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                            child: const Padding(
                              padding: EdgeInsets.fromLTRB(4, 8, 12, 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune_rounded, color: Colors.white70, size: 16),
                                  SizedBox(width: 5),
                                  Text('Controls', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],

              // ---------------------------------------------------------------
              // Layer 10: Autoplay Next Countdown Card
              // ---------------------------------------------------------------
              if (_isNativeMode && _showAutoplayCard && !_isClippingMoment)
                Positioned(
                  bottom: 24,
                  right: 20,
                  child: _buildAutoplayNextCard(),
                ),

              // ---------------------------------------------------------------
              // Layer 10b: Skip Intro Floating Button (Seconds 12 to 95)
              // ---------------------------------------------------------------
              if (_isNativeMode && _showSkipIntro && !_showAutoplayCard && !_isClippingMoment)
                Positioned(
                  bottom: _showControls ? 95 : 30,
                  right: 20,
                  child: _buildSkipIntroButton(),
                ),

              // ---------------------------------------------------------------
              // Layer 14: Watch Party Floating Sync Status Pill (Top Left)
              // ---------------------------------------------------------------
              if (_isNativeMode && _isInParty && !_isClippingMoment)
                Positioned(
                  top: 16,
                  left: _showControls ? 60 : 20,
                  child: _buildPartyStatusPill(),
                ),

              // ---------------------------------------------------------------
              // Layer 15: Watch Party Floating Chat Toast Messages (Bottom Left)
              // ---------------------------------------------------------------
              if (_isNativeMode && _floatingPartyMessages.isNotEmpty)
                Positioned(
                  bottom: _showControls ? 95 : 30,
                  left: 20,
                  child: IgnorePointer(
                    child: _buildPartyFloatingMessages(),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 11: Clip a Moment Trimmer View (Matching Screenshot 2)
              // ---------------------------------------------------------------
              if (_isClippingMoment)
                Positioned.fill(
                  child: _buildClipMomentView(),
                ),

              // ---------------------------------------------------------------
              // Layer 12: Aesthetic Unavailable Overlay (Native Only Mode)
              // ---------------------------------------------------------------
              if (_isStreamUnavailable)
                _buildUnavailableOverlay(),

              // ---------------------------------------------------------------
              // Layer 13: 2X Hold Speed Floating HUD (Top Center Glassy Pill)
              // ---------------------------------------------------------------
              if (_isHolding2xSpeed)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IgnorePointer(
                      child: _build2xSpeedHud(),
                    ),
                  ),
                ),

              // ---------------------------------------------------------------
              // Layer 16: Watch Party Notification HUD Toast (Top Center Pill)
              // ---------------------------------------------------------------
              if (_partyHudMessage != null)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: IgnorePointer(
                      child: _buildPartyToastHud(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailableOverlay() {
    final title = widget.mediaType == 'tv'
        ? '${widget.mediaTitle} (S$_currentSeason E$_currentEpisode)'
        : widget.mediaTitle;

    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.backdropPath != null && widget.backdropPath!.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: CachedNetworkImage(
                    imageUrl: 'https://image.tmdb.org/t/p/w780${widget.backdropPath}',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Color(0xCC000000),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    onPressed: _handleSmoothBack,
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.cloud_off_rounded,
                          color: Colors.white70,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Stream Unavailable',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'We searched all direct streaming servers for "$title", but no active native stream could be established right now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              'Try Again',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () {
                              setState(() {
                                _isStreamUnavailable = false;
                                _isLoading = true;
                              });
                              _triedNativeServerIndices.clear();
                              _loadMedia();
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.dns_outlined, size: 18),
                            label: const Text(
                              'Switch Server',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            onPressed: _openServerPicker,
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            label: const Text(
                              'Open in External Player (VLC)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () {
                              final url = _directStreams.isNotEmpty
                                  ? _directStreams.first.url
                                  : _buildCurrentEmbedUrl();
                              CastService.launchExternalPlayer(
                                videoUrl: url,
                                title: widget.mediaTitle,
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.language_rounded, size: 18),
                            label: const Text(
                              'Watch in Browser',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () {
                              final webUrl = _buildCurrentEmbedUrl();
                              launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
                            },
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text(
                              'Go Back',
                              style: TextStyle(fontSize: 13),
                            ),
                            onPressed: _handleSmoothBack,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildSkipIntroButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white30, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _skipIntro,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fast_forward_rounded, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'Skip Intro',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Watch Party / Synchronized Play (Native Player Exclusive)
  // ---------------------------------------------------------------------------
  void _startPartySyncLoop() {
    _partySyncTimer?.cancel();
    _partySyncTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) async {
      if (!mounted || !_isInParty || _partyRoom == null) return;
      if (_videoPlayerController == null || !_videoPlayerController!.value.isInitialized) return;

      final isHost = _partyRoom!.hostId == _partyMemberId;
      final curSec = _currentPosition.inMilliseconds / 1000.0;

      if (isHost) {
        final updated = await _partyService.syncPlayback(
          roomCode: _partyRoom!.roomCode,
          memberId: _partyMemberId,
          isPlaying: _isPlaying,
          currentTime: curSec,
          season: _currentSeason,
          episode: _currentEpisode,
        );
        if (updated != null && mounted) {
          _updatePartyRoomState(updated);
        }
      } else {
        final room = await _partyService.getRoom(_partyRoom!.roomCode);
        if (room != null && mounted) {
          _updatePartyRoomState(room);

          // Auto-follow host to new episode if in TV show
          if (room.mediaId == widget.mediaId &&
              room.mediaType == 'tv' &&
              (room.season != _currentSeason || room.episode != _currentEpisode)) {
            _goToEpisode(room.episode);
            return;
          }

          final expectedSec = room.getDriftCompensatedTime(
            serverOffsetMs: _partyService.serverTimeOffsetMs,
          );
          final drift = (curSec - expectedSec).abs();

          // Only seek if drift exceeds 3.5s and we are not currently seeking
          if (!_isSyncSeeking && drift > 3.5 && expectedSec >= 0) {
            _isSyncSeeking = true;
            _videoPlayerController?.seekTo(
              Duration(milliseconds: (expectedSec * 1000).toInt()),
            ).then((_) {
              if (mounted) _isSyncSeeking = false;
            }).catchError((_) {
              if (mounted) _isSyncSeeking = false;
            });
          }

          if (room.isPlaying != _isPlaying && !_isSyncSeeking) {
            if (room.isPlaying) {
              _videoPlayerController?.play();
            } else {
              _videoPlayerController?.pause();
            }
          }
        }
      }
    });
  }

  void _updatePartyRoomState(WatchPartyRoom room) {
    _partyRoom = room;
    for (final msg in room.messages) {
      if (msg.timestamp > _lastProcessedMsgTimestamp && msg.sender != _partyMemberName && msg.sender != 'System') {
        _lastProcessedMsgTimestamp = msg.timestamp;
        _showFloatingPartyMessage(msg);
      }
    }
    if (mounted) setState(() {});
  }

  void _showFloatingPartyMessage(WatchPartyMessage msg) {
    setState(() {
      _floatingPartyMessages.add(msg);
      if (_floatingPartyMessages.length > 3) {
        _floatingPartyMessages.removeAt(0);
      }
    });
    _floatingMsgTimer?.cancel();
    _floatingMsgTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _floatingPartyMessages.clear());
      }
    });
  }

  void _showPartyHud(String message, {IconData icon = Icons.group_rounded, Color accent = const Color(0xFFE50914)}) {
    if (!mounted) return;
    setState(() {
      _partyHudMessage = message;
      _partyHudIcon = icon;
      _partyHudAccent = accent;
    });
    _partyHudTimer?.cancel();
    _partyHudTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        setState(() {
          _partyHudMessage = null;
        });
      }
    });
  }

  Widget _buildPartyToastHud() {
    return AnimatedOpacity(
      opacity: _partyHudMessage != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xEE0B0B10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _partyHudAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _partyHudAccent.withValues(alpha: 0.8), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(_partyHudIcon, color: _partyHudAccent, size: 16),
            const SizedBox(width: 8),
            Text(
              _partyHudMessage ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _leaveWatchParty() {
    if (_partyRoom != null) {
      _partyService.leaveRoom(_partyRoom!.roomCode, _partyMemberId);
    }
    _partySyncTimer?.cancel();
    _partySyncTimer = null;
    setState(() {
      _isInParty = false;
      _partyRoom = null;
      _floatingPartyMessages.clear();
    });
    _showPartyHud('Left Watch Party', icon: Icons.exit_to_app_rounded, accent: Colors.white70);
  }

  Widget _buildPartyStatusPill() {
    final count = _partyRoom?.members.length ?? 1;
    final code = _partyRoom?.roomCode ?? '';
    final isHost = _partyRoom?.hostId == _partyMemberId;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEE0B0B10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _openWatchPartySheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFF46D369),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF46D369).withValues(alpha: 0.8),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isHost ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isHost ? 'HOST' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPartyFloatingMessages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _floatingPartyMessages.map((msg) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xE60A0A0F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${msg.sender}: ',
                style: const TextStyle(
                  color: Color(0xFFE50914),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Flexible(
                child: Text(
                  msg.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _openWatchPartySheet() {
    _startHideControlsTimer();
    final joinCodeController = TextEditingController();
    final chatController = TextEditingController();

    bool copiedCode = false;
    int selectedTab = 0; // 0 = Start Party, 1 = Join Room
    bool isLoading = false;
    String? sheetError;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (_isInParty && _partyRoom != null) {
              final isHost = _partyRoom!.hostId == _partyMemberId;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                        left: 20,
                        right: 20,
                        top: 14,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Header Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF46D369).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF46D369).withValues(alpha: 0.4), width: 0.8),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF46D369),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          'SYNC PLAY ACTIVE',
                                          style: TextStyle(
                                            color: Color(0xFF46D369),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isHost ? const Color(0xFFE50914) : Colors.white12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isHost ? 'HOST' : 'GUEST',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Netflix Hero Room Code Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF171722), Color(0xFF111118)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'ROOM CODE',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    Text(
                                      '${_partyRoom!.members.length} Watching Together',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _partyRoom!.roomCode,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 3.5,
                                      ),
                                    ),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: _partyRoom!.roomCode));
                                          setSheetState(() => copiedCode = true);
                                          _showPartyHud(
                                            'Room code ${_partyRoom!.roomCode} copied',
                                            icon: Icons.check_circle_rounded,
                                            accent: const Color(0xFF46D369),
                                          );
                                          Future.delayed(const Duration(seconds: 2), () {
                                            if (ctx.mounted) {
                                              setSheetState(() => copiedCode = false);
                                            }
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: copiedCode
                                                ? const Color(0xFF46D369).withValues(alpha: 0.2)
                                                : Colors.white.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: copiedCode ? const Color(0xFF46D369) : Colors.white24,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                copiedCode ? Icons.check_circle_rounded : Icons.copy_rounded,
                                                color: copiedCode ? const Color(0xFF46D369) : Colors.white,
                                                size: 15,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                copiedCode ? 'Copied!' : 'Copy Code',
                                                style: TextStyle(
                                                  color: copiedCode ? const Color(0xFF46D369) : Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Netflix Quick Reaction Bar
                          const Text(
                            'QUICK REACTIONS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['❤️', '🔥', '😂', '🍿', '😱', '👏'].map((emoji) {
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () {
                                    _partyService.syncPlayback(
                                      roomCode: _partyRoom!.roomCode,
                                      memberId: _partyMemberId,
                                      isPlaying: _isPlaying,
                                      currentTime: _currentPosition.inMilliseconds / 1000.0,
                                      chatText: emoji,
                                      chatSender: _partyMemberName,
                                    );
                                    _showFloatingPartyMessage(
                                      WatchPartyMessage(
                                        id: '${DateTime.now().millisecondsSinceEpoch}',
                                        sender: _partyMemberName,
                                        text: emoji,
                                        timestamp: DateTime.now().millisecondsSinceEpoch,
                                      ),
                                    );
                                    _showPartyHud('Sent $emoji', icon: Icons.sentiment_satisfied_alt_rounded);
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A24),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Participants Section
                          const Text(
                            'PARTICIPANTS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _partyRoom!.members.map((m) {
                              final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : 'U';
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF181822),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: m.isHost ? const Color(0xFFE50914).withValues(alpha: 0.5) : Colors.white12,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: m.isHost ? const Color(0xFFE50914) : const Color(0xFF333344),
                                      child: Text(
                                        initial,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      m.name,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    if (m.isHost) ...[
                                      const SizedBox(width: 4),
                                      const Text('👑', style: TextStyle(fontSize: 10)),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          // Chat message row
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: chatController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Type message to party...',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFF181822),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.2),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE50914),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                  onPressed: () {
                                    final text = chatController.text.trim();
                                    if (text.isNotEmpty) {
                                      _partyService.syncPlayback(
                                        roomCode: _partyRoom!.roomCode,
                                        memberId: _partyMemberId,
                                        isPlaying: _isPlaying,
                                        currentTime: _currentPosition.inMilliseconds / 1000.0,
                                        chatText: text,
                                        chatSender: _partyMemberName,
                                      );
                                      _showFloatingPartyMessage(
                                        WatchPartyMessage(
                                          id: '${DateTime.now().millisecondsSinceEpoch}',
                                          sender: _partyMemberName,
                                          text: text,
                                          timestamp: DateTime.now().millisecondsSinceEpoch,
                                        ),
                                      );
                                      chatController.clear();
                                      Navigator.pop(ctx);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Leave Party Button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 0.9),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.exit_to_app_rounded, size: 17, color: Color(0xFFE50914)),
                              label: const Text('Leave Watch Party', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _leaveWatchParty();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            // Not currently in party: Netflix segmented UI
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                      left: 20,
                      right: 20,
                      top: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Title & Close Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.group_work_rounded, color: Color(0xFFE50914), size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Watch Together',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 22),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Stream together in real-time sync with friends directly in the Native Player.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 16),

                        // Netflix Segmented Pill Switcher
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161620),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap: () {
                                    setSheetState(() {
                                      selectedTab = 0;
                                      sheetError = null;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selectedTab == 0 ? const Color(0xFFE50914) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 15,
                                          color: selectedTab == 0 ? Colors.white : Colors.white60,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Start Party',
                                          style: TextStyle(
                                            color: selectedTab == 0 ? Colors.white : Colors.white60,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap: () {
                                    setSheetState(() {
                                      selectedTab = 1;
                                      sheetError = null;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selectedTab == 1 ? const Color(0xFFE50914) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.login_rounded,
                                          size: 15,
                                          color: selectedTab == 1 ? Colors.white : Colors.white60,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Join with Code',
                                          style: TextStyle(
                                            color: selectedTab == 1 ? Colors.white : Colors.white60,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
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
                        const SizedBox(height: 16),

                        // Error Banner (In-sheet feedback, zero SnackBars)
                        if (sheetError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1418),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.5), width: 0.8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    sheetError!,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // TAB 0: START PARTY
                        if (selectedTab == 0) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14141E),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.mediaType == 'tv'
                                      ? '${widget.mediaTitle} • S$_currentSeason E$_currentEpisode'
                                      : widget.mediaTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '• Synchronize play, pause, and seek for everyone\n'
                                  '• Microsecond drift compensation\n'
                                  '• Real-time floating chat and reaction emojis',
                                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      setSheetState(() {
                                        isLoading = true;
                                        sheetError = null;
                                      });
                                      final curSec = _currentPosition.inMilliseconds / 1000.0;
                                      final room = await _partyService.createRoom(
                                        mediaId: widget.mediaId,
                                        mediaTitle: widget.mediaTitle,
                                        mediaType: widget.mediaType,
                                        season: _currentSeason,
                                        episode: _currentEpisode,
                                        memberId: _partyMemberId,
                                        memberName: _partyMemberName,
                                        isPlaying: _isPlaying,
                                        currentTime: curSec,
                                      );

                                      if (room != null && mounted && ctx.mounted) {
                                        Navigator.pop(ctx);
                                        setState(() {
                                          _isInParty = true;
                                          _partyRoom = room;
                                        });
                                        _startPartySyncLoop();
                                        _showPartyHud(
                                          'Party Created • Code: ${room.roomCode}',
                                          icon: Icons.celebration_rounded,
                                          accent: const Color(0xFF46D369),
                                        );
                                      } else if (mounted && ctx.mounted) {
                                        setSheetState(() {
                                          isLoading = false;
                                          sheetError = 'Could not create party. Check connection and retry.';
                                        });
                                      }
                                    },
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_circle_fill_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Create Watch Party', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                            ),
                          ),
                        ],

                        // TAB 1: JOIN WITH CODE
                        if (selectedTab == 1) ...[
                          const Text(
                            'Enter Room Code',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: joinCodeController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3.0,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: 'e.g. V-7X9K',
                              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 2.0, fontSize: 16),
                              filled: true,
                              fillColor: const Color(0xFF161622),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      final code = joinCodeController.text.trim();
                                      if (code.isEmpty) {
                                        setSheetState(() => sheetError = 'Please enter a valid room code.');
                                        return;
                                      }
                                      setSheetState(() {
                                        isLoading = true;
                                        sheetError = null;
                                      });
                                      final room = await _partyService.joinRoom(
                                        roomCode: code,
                                        memberId: _partyMemberId,
                                        memberName: _partyMemberName,
                                      );

                                      if (room != null && mounted && ctx.mounted) {
                                        Navigator.pop(ctx);
                                        setState(() {
                                          _isInParty = true;
                                          _partyRoom = room;
                                        });
                                        if (room.mediaId == widget.mediaId &&
                                            room.season == _currentSeason &&
                                            room.episode != _currentEpisode) {
                                          _goToEpisode(room.episode);
                                        }
                                        final expected = room.getDriftCompensatedTime(
                                          serverOffsetMs: _partyService.serverTimeOffsetMs,
                                        );
                                        _videoPlayerController?.seekTo(
                                          Duration(milliseconds: (expected * 1000).toInt()),
                                        );
                                        if (room.isPlaying) {
                                          _videoPlayerController?.play();
                                        } else {
                                          _videoPlayerController?.pause();
                                        }
                                        _startPartySyncLoop();
                                        _showPartyHud(
                                          'Connected to Watch Party (${room.roomCode})',
                                          icon: Icons.check_circle_rounded,
                                          accent: const Color(0xFF46D369),
                                        );
                                      } else if (mounted && ctx.mounted) {
                                        setSheetState(() {
                                          isLoading = false;
                                          sheetError = 'Party room not found or expired. Verify code and retry.';
                                        });
                                      }
                                    },
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Join Watch Party', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlayPause();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _revealControls();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(10);
    } else if (event.logicalKey == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(-10);
    } else if (event.logicalKey == LogicalKeyboardKey.keyS && _showSkipIntro) {
      _skipIntro();
    } else if (event.logicalKey == LogicalKeyboardKey.keyN && widget.mediaType == 'tv') {
      _nextEpisode();
    }
  }
}

class _NetflixBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _NetflixBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: effectiveColor, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
