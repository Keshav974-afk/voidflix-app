import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/stream_extractor.dart';
import '../core/services/subtitle_service.dart';
import '../core/utils/language_utils.dart';
import '../core/services/tv_mode_service.dart';
import '../providers/download_provider.dart';
import 'tv_focusable.dart';

class _ExtractedQualityItem {
  final String label;
  final int height;
  final String url;
  final Map<String, String> headers;
  final bool isHls;
  final String serverName;
  int? fileSizeBytes;
  bool isProbingSize;

  _ExtractedQualityItem({
    required this.label,
    required this.height,
    required this.url,
    required this.headers,
    required this.isHls,
    required this.serverName,
    this.isProbingSize = false,
  });

  String get formattedSize {
    if (fileSizeBytes != null && fileSizeBytes! > 0) {
      final mb = fileSizeBytes! / (1024 * 1024);
      if (mb >= 1024) {
        return '${(mb / 1024).toStringAsFixed(2)} GB';
      }
      return '${mb.toStringAsFixed(0)} MB';
    }
    if (isProbingSize) return 'Checking size…';
    return isHls ? 'HLS Stream' : 'Direct MP4';
  }
}

class _ExtractedAudioGroup {
  final String key;
  final String languageLabel;
  final String serverName;
  final List<_ExtractedQualityItem> qualities;

  _ExtractedAudioGroup({
    required this.key,
    required this.languageLabel,
    required this.serverName,
    required this.qualities,
  });
}

class DownloadQualityPicker {
  static void show(
    BuildContext context, {
    required int mediaId,
    required String title,
    required String mediaType,
    int season = 1,
    int episode = 1,
    String? episodeTitle,
    String? episodeDescription,
    String? posterPath,
    String? backdropPath,
    String? stillPath,
    int runtime = 0,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return _DownloadOptionsSheetContent(
          parentContext: context,
          mediaId: mediaId,
          title: title,
          mediaType: mediaType,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
          episodeDescription: episodeDescription,
          posterPath: posterPath,
          backdropPath: backdropPath,
          stillPath: stillPath,
          runtime: runtime,
        );
      },
    );
  }
}

class _DownloadOptionsSheetContent extends StatefulWidget {
  final BuildContext parentContext;
  final int mediaId;
  final String title;
  final String mediaType;
  final int season;
  final int episode;
  final String? episodeTitle;
  final String? episodeDescription;
  final String? posterPath;
  final String? backdropPath;
  final String? stillPath;
  final int runtime;

  const _DownloadOptionsSheetContent({
    required this.parentContext,
    required this.mediaId,
    required this.title,
    required this.mediaType,
    required this.season,
    required this.episode,
    this.episodeTitle,
    this.episodeDescription,
    this.posterPath,
    this.backdropPath,
    this.stillPath,
    required this.runtime,
  });

  @override
  State<_DownloadOptionsSheetContent> createState() =>
      _DownloadOptionsSheetContentState();
}

class _DownloadOptionsSheetContentState
    extends State<_DownloadOptionsSheetContent> {
  bool _isExtracting = true;
  String _statusMessage = 'Scanning high-speed servers…';
  String? _errorMessage;

  final List<_ExtractedAudioGroup> _audioGroups = [];
  final List<SubtitleTrack> _subtitles = [];

  int _selectedAudioIndex = 0;
  int _selectedQualityIndex = 0;
  String _selectedSubLanguage = 'Off';

  @override
  void initState() {
    super.initState();
    _extractRealStreams();
  }

  Future<void> _extractRealStreams() async {
    setState(() {
      _isExtracting = true;
      _errorMessage = null;
      _statusMessage = 'Extracting available audio, quality & subtitles…';
      _audioGroups.clear();
      _subtitles.clear();
    });

    final seenSubLangs = <String>{};
    final seenSubUrls = <String>{};

    void addSubtitles(List<SubtitleTrack> tracks) {
      for (final s in tracks) {
        final url = s.url.trim();
        if (url.isEmpty || seenSubUrls.contains(url)) continue;
        final cleanLang = LanguageUtils.cleanLanguageName(
          s.label.isNotEmpty ? s.label : s.language,
        );
        final langKey = cleanLang.toLowerCase();
        if (seenSubLangs.contains(langKey)) continue;
        seenSubUrls.add(url);
        seenSubLangs.add(langKey);
        _subtitles.add(SubtitleTrack(
          label: cleanLang,
          language: s.language,
          url: url,
        ));
      }
    }

    int serverPriority(String sName, bool isHls) {
      if (sName == 'StellarHD') return 100; // Direct unproxied high-speed CDN MP4
      if (sName == 'Vidlink' && !isHls) return 85;
      if (!isHls) return 75;
      return 40;
    }

    void addStreamGroup(ExtractedStream s, String serverLabel) {
      final rawLang = s.language.trim().isNotEmpty ? s.language.trim() : 'Original';
      if (LanguageUtils.isSubtitleOnly(rawLang) ||
          LanguageUtils.isSubtitleOnly(s.sourceName)) {
        return;
      }

      String cleanLang = LanguageUtils.cleanLanguageName(rawLang);
      if (rawLang.toLowerCase().contains('original') &&
          !cleanLang.toLowerCase().contains('original')) {
        cleanLang = '$cleanLang (Original)';
      }

      final groupKey = cleanLang.toLowerCase();

      final items = <_ExtractedQualityItem>[];
      if (s.qualities.isNotEmpty) {
        for (final q in s.qualities) {
          if (q.url.isEmpty) continue;
          final isHls = q.url.contains('.m3u8') || s.type == 'hls';
          final h = q.height > 0 ? q.height : _inferHeight(q.label);
          items.add(_ExtractedQualityItem(
            label: h > 0 ? '${h}p' : q.label,
            height: h,
            url: q.url,
            headers: s.headers,
            isHls: isHls,
            serverName: serverLabel,
            isProbingSize: !isHls,
          ));
        }
      } else if (s.url.isNotEmpty) {
        final isHls = s.url.contains('.m3u8') || s.type == 'hls';
        final label = s.qualityLabel ?? '1080p';
        final h = _inferHeight(label);
        items.add(_ExtractedQualityItem(
          label: h > 0 ? '${h}p' : label,
          height: h,
          url: s.url,
          headers: s.headers,
          isHls: isHls,
          serverName: serverLabel,
          isProbingSize: !isHls,
        ));
      }

      if (items.isEmpty) return;

      final existingGroupIdx = _audioGroups.indexWhere((g) => g.key == groupKey);
      if (existingGroupIdx != -1) {
        final group = _audioGroups[existingGroupIdx];
        for (final item in items) {
          final existingQIdx = group.qualities.indexWhere((q) => q.height == item.height);
          if (existingQIdx == -1) {
            group.qualities.add(item);
          } else {
            final current = group.qualities[existingQIdx];
            if (serverPriority(item.serverName, item.isHls) >
                serverPriority(current.serverName, current.isHls)) {
              group.qualities[existingQIdx] = item;
            }
          }
        }
        group.qualities.sort((a, b) => b.height.compareTo(a.height));
      } else {
        final deduped = <_ExtractedQualityItem>[];
        final seenHeights = <int>{};
        for (final item in items) {
          if (!seenHeights.contains(item.height)) {
            seenHeights.add(item.height);
            deduped.add(item);
          }
        }
        deduped.sort((a, b) => b.height.compareTo(a.height));
        _audioGroups.add(_ExtractedAudioGroup(
          key: groupKey,
          languageLabel: cleanLang,
          serverName: serverLabel,
          qualities: deduped,
        ));
      }
    }

    try {
      await Future.wait([
        // 1. NetMirror / StellarHD (Multi-Dub + Direct High-Speed CDN MP4s)
        () async {
          try {
            final streams = await StreamExtractor.extractNetMirror(
              type: widget.mediaType,
              tmdbId: widget.mediaId,
              season: widget.season,
              episode: widget.episode,
            ).timeout(const Duration(seconds: 9));
            if (!mounted) return;
            for (final s in streams) {
              addSubtitles(s.subtitles);
              addStreamGroup(s, 'StellarHD');
            }
            if (_audioGroups.isNotEmpty && mounted) {
              setState(() => _isExtracting = false);
            }
          } catch (_) {}
        }(),

        // 2. Vidlink Direct
        () async {
          try {
            final s = await StreamExtractor.extractVidlink(
              type: widget.mediaType,
              tmdbId: widget.mediaId,
              season: widget.season,
              episode: widget.episode,
            ).timeout(const Duration(seconds: 9));
            if (!mounted || s == null) return;
            addSubtitles(s.subtitles);
            addStreamGroup(s, 'Vidlink');
            if (_audioGroups.isNotEmpty && mounted) {
              setState(() => _isExtracting = false);
            }
          } catch (_) {}
        }(),

        // 3. Voidflix Backend
        () async {
          try {
            final s = await StreamExtractor.extractVoidflixBackend(
              type: widget.mediaType,
              tmdbId: widget.mediaId,
              season: widget.season,
              episode: widget.episode,
            ).timeout(const Duration(seconds: 9));
            if (!mounted || s == null) return;
            addSubtitles(s.subtitles);
            addStreamGroup(s, 'Voidflix');
            if (_audioGroups.isNotEmpty && mounted) {
              setState(() => _isExtracting = false);
            }
          } catch (_) {}
        }(),

        // 4. Cinejoy / NebulaHD
        () async {
          try {
            final streams = await StreamExtractor.extractCinejoy(
              type: widget.mediaType,
              tmdbId: widget.mediaId,
              season: widget.season,
              episode: widget.episode,
              title: widget.title,
            ).timeout(const Duration(seconds: 9));
            if (!mounted) return;
            for (final s in streams) {
              addSubtitles(s.subtitles);
              addStreamGroup(s, 'NebulaHD');
            }
            if (_audioGroups.isNotEmpty && mounted) {
              setState(() => _isExtracting = false);
            }
          } catch (_) {}
        }(),

        // 5. Shared cached subtitles
        () async {
          try {
            final extSubs = await StreamExtractor.getSharedSubtitles(
              widget.mediaType,
              widget.mediaId,
              widget.season,
              widget.episode,
            ).timeout(const Duration(seconds: 5));
            if (!mounted) return;
            addSubtitles(extSubs);
          } catch (_) {}
        }(),
      ]);
    } catch (_) {}

    if (!mounted) return;

    if (_audioGroups.isEmpty) {
      setState(() {
        _isExtracting = false;
        _errorMessage =
            'No downloadable streams could be extracted right now. Please try again.';
      });
      return;
    }

    await _applySavedPreferences();

    setState(() {
      _isExtracting = false;
    });

    _probeCurrentGroupSizes();
  }

  int _inferHeight(String label) {
    final l = label.toLowerCase();
    if (l.contains('2160') || l.contains('4k')) return 2160;
    if (l.contains('1080') || l.contains('fhd') || l.contains('full')) return 1080;
    if (l.contains('720') || l == 'hd') return 720;
    if (l.contains('480')) return 480;
    if (l.contains('360')) return 360;
    return 1080;
  }

  Future<void> _applySavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAudio = prefs.getString('voidflix_preferred_audio_lang');
      final savedSub = prefs.getString('voidflix_preferred_sub_lang');
      final savedQ = prefs.getString('voidflix_download_quality');

      if (savedAudio != null && savedAudio.isNotEmpty) {
        final idx = _audioGroups.indexWhere(
          (g) => LanguageUtils.matches(g.languageLabel, savedAudio),
        );
        if (idx != -1) _selectedAudioIndex = idx;
      }

      if (_selectedAudioIndex < _audioGroups.length && savedQ != null) {
        final targetH = _inferHeight(savedQ);
        final qList = _audioGroups[_selectedAudioIndex].qualities;
        final qIdx = qList.indexWhere((q) => q.height == targetH);
        if (qIdx != -1) _selectedQualityIndex = qIdx;
      }

      if (savedSub != null && savedSub.isNotEmpty) {
        if (savedSub.toLowerCase().contains('off') ||
            savedSub.toLowerCase().contains('none')) {
          _selectedSubLanguage = 'Off';
        } else {
          final match = _subtitles.where(
            (s) =>
                LanguageUtils.matches(s.label, savedSub) ||
                LanguageUtils.matches(s.language, savedSub),
          );
          if (match.isNotEmpty) {
            _selectedSubLanguage = match.first.label;
          }
        }
      } else if (_subtitles.isNotEmpty) {
        final en = _subtitles.where(
          (s) =>
              LanguageUtils.matches(s.label, 'English') ||
              LanguageUtils.matches(s.language, 'en'),
        );
        if (en.isNotEmpty) {
          _selectedSubLanguage = en.first.label;
        }
      }
    } catch (_) {}
  }

  void _probeCurrentGroupSizes() {
    if (_selectedAudioIndex >= _audioGroups.length) return;
    final group = _audioGroups[_selectedAudioIndex];
    for (final q in group.qualities) {
      if (!q.isHls && q.fileSizeBytes == null) {
        _probeFileSize(q);
      }
    }
  }

  Future<void> _probeFileSize(_ExtractedQualityItem item) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(item.url);
      final reqHeaders = {
        ...item.headers,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

      final headRes = await client
          .head(uri, headers: reqHeaders)
          .timeout(const Duration(seconds: 4));
      final cl = int.tryParse(headRes.headers['content-length'] ?? '');
      if (cl != null && cl > 100000) {
        if (mounted) {
          setState(() {
            item.fileSizeBytes = cl;
            item.isProbingSize = false;
          });
        }
        return;
      }

      final req = http.Request('GET', uri);
      req.headers.addAll(reqHeaders);
      req.headers['Range'] = 'bytes=0-0';
      final streamRes =
          await client.send(req).timeout(const Duration(seconds: 4));
      final contentRange = streamRes.headers['content-range'] ?? '';
      if (contentRange.contains('/')) {
        final totalStr = contentRange.split('/').last.trim();
        final totalBytes = int.tryParse(totalStr);
        if (totalBytes != null && totalBytes > 100000) {
          if (mounted) {
            setState(() {
              item.fileSizeBytes = totalBytes;
              item.isProbingSize = false;
            });
          }
          return;
        }
      }
    } catch (_) {
    } finally {
      // Immediately close the probe client so no background TCP connection stays open!
      client.close();
      if (mounted && item.isProbingSize) {
        setState(() {
          item.isProbingSize = false;
        });
      }
    }
  }

  Future<void> _triggerExtractedDownload() async {
    if (_selectedAudioIndex >= _audioGroups.length) return;
    final group = _audioGroups[_selectedAudioIndex];
    if (group.qualities.isEmpty) return;
    final qIdx = _selectedQualityIndex.clamp(0, group.qualities.length - 1);
    final chosenQuality = group.qualities[qIdx];
    final downloadProvider = widget.parentContext.read<DownloadProvider>();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voidflix_download_quality', chosenQuality.label);
      await prefs.setString(
          'voidflix_preferred_audio_lang', group.languageLabel);
      await prefs.setString(
        'voidflix_preferred_sub_lang',
        _selectedSubLanguage == 'Off' ? 'Off / None' : _selectedSubLanguage,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pop();

    downloadProvider.startDownload(
          mediaId: widget.mediaId,
          title: widget.title,
          mediaType: widget.mediaType,
          season: widget.season,
          episode: widget.episode,
          episodeTitle: widget.episodeTitle,
          episodeDescription: widget.episodeDescription,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
          stillPath: widget.stillPath,
          runtime: widget.runtime,
          preferredQuality: chosenQuality.label,
          preferredAudio: group.languageLabel,
          preferredSubtitle: _selectedSubLanguage == 'Off'
              ? 'Off / None'
              : _selectedSubLanguage,
          directStreamUrl: chosenQuality.url,
          directHeaders: chosenQuality.headers,
          directIsHls: chosenQuality.isHls,
          directSubtitles: _subtitles,
        );
  }

  Widget _wrapTv({
    required bool isTv,
    required VoidCallback onTap,
    required Widget child,
    BorderRadius? borderRadius,
  }) {
    if (!isTv) return child;
    return TvFocusable(
      autofocus: false,
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      onPressed: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvModeService().isTvMode || TvModeService().isHardwareTv;
    final episodeTag =
        widget.mediaType == 'tv' ? 'S${widget.season}:E${widget.episode}' : 'Movie';

    final currentGroup = _audioGroups.isNotEmpty &&
            _selectedAudioIndex < _audioGroups.length
        ? _audioGroups[_selectedAudioIndex]
        : null;

    final currentQualities = currentGroup?.qualities ?? [];
    final safeQualityIdx = currentQualities.isEmpty
        ? 0
        : _selectedQualityIndex.clamp(0, currentQualities.length - 1);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Download Options',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.title} • $episodeTag',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E8E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E1E),
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFAAAAAA),
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF222222), height: 1),
            const SizedBox(height: 14),

            if (_isExtracting && _audioGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 38),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFFB81D24),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Color(0xFFAAAAAA),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_errorMessage != null && _audioGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _extractRealStreams,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF222222),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Retry Scan'),
                    ),
                  ],
                ),
              )
            else ...[
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. AUDIO TRACKS
                      const Text(
                        'AUDIO TRACK',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _audioGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (ctx, idx) {
                            final g = _audioGroups[idx];
                            final selected = idx == _selectedAudioIndex;
                            void selectAudio() {
                              setState(() {
                                _selectedAudioIndex = idx;
                                _selectedQualityIndex = 0;
                              });
                              _probeCurrentGroupSizes();
                            }

                            return _wrapTv(
                              isTv: isTv,
                              onTap: selectAudio,
                              child: GestureDetector(
                                onTap: selectAudio,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFB81D24)
                                        : const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFFE50914)
                                          : const Color(0xFF2C2C2C),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    g.languageLabel,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFFB5B5B5),
                                      fontSize: 12.5,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 2. VIDEO QUALITY
                      const Text(
                        'VIDEO RESOLUTION',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(currentQualities.length, (idx) {
                        final q = currentQualities[idx];
                        final selected = idx == safeQualityIdx;
                        void selectQ() =>
                            setState(() => _selectedQualityIndex = idx);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _wrapTv(
                            isTv: isTv,
                            onTap: selectQ,
                            child: GestureDetector(
                              onTap: selectQ,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 11),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF1E1415)
                                      : const Color(0xFF181818),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFFB81D24)
                                        : const Color(0xFF282828),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: selected
                                            ? const Color(0xFFB81D24)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: selected
                                              ? const Color(0xFFE50914)
                                              : const Color(0xFF555555),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(
                                              Icons.check,
                                              size: 11,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        q.label,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFFD0D0D0),
                                          fontSize: 13.5,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      q.formattedSize,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : const Color(0xFF8E8E8E),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 12),

                      // 3. SUBTITLES
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SUBTITLES',
                            style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.9,
                            ),
                          ),
                          Text(
                            _subtitles.isEmpty
                                ? 'None found'
                                : '${_subtitles.length} available',
                            style: const TextStyle(
                              color: Color(0xFF6E6E6E),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _subtitles.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(width: 7),
                          itemBuilder: (ctx, idx) {
                            final label =
                                idx == 0 ? 'Off' : _subtitles[idx - 1].label;
                            final selected = _selectedSubLanguage == label;
                            void selectSub() =>
                                setState(() => _selectedSubLanguage = label);

                            return _wrapTv(
                              isTv: isTv,
                              onTap: selectSub,
                              child: GestureDetector(
                                onTap: selectSub,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 13),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFB81D24)
                                        : const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFFE50914)
                                          : const Color(0xFF2C2C2C),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : const Color(0xFFB0B0B0),
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action Button
              _wrapTv(
                isTv: isTv,
                onTap: _triggerExtractedDownload,
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _triggerExtractedDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB81D24),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: Text(
                      currentQualities.isNotEmpty
                          ? 'Download ${currentQualities[safeQualityIdx].label} • ${currentGroup?.languageLabel ?? ""}'
                          : 'Start Download',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
