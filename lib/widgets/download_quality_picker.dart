import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/stream_extractor.dart';
import '../core/services/subtitle_service.dart';
import '../core/utils/language_utils.dart';
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
    if (isProbingSize) return 'Calculating…';
    return isHls ? 'HLS' : 'MP4';
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
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
  static const Color _darkRed = Color(0xFFB81D24);
  static const Color _darkRedBorder = Color(0xFFE50914);
  static const Color _cardBg = Color(0xFF1A1A1A);
  static const Color _selectedBg = Color(0xFF221113);

  bool _isExtracting = true;
  final List<_ExtractedAudioGroup> _audioGroups = [];
  final List<SubtitleTrack> _extractedSubtitles = [];

  int _selectedAudioIndex = 0;
  int _selectedQualityIndex = 0;
  int _selectedSubtitleIndex = -1; // -1 = Off

  String? _savedPreferredQuality;
  String? _savedPreferredAudio;
  String? _savedPreferredSub;

  @override
  void initState() {
    super.initState();
    _initAndExtract();
  }

  Future<void> _initAndExtract() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedPreferredQuality = prefs.getString('voidflix_preferred_dl_quality');
      _savedPreferredAudio = prefs.getString('voidflix_preferred_audio_lang');
      _savedPreferredSub = prefs.getString('voidflix_preferred_subtitle_lang');
    } catch (_) {}

    await _extractRealStreams();
  }

  void _ingestStreams(List<ExtractedStream> streams) {
    if (!mounted || streams.isEmpty) return;

    for (final s in streams) {
      if (s.url.isEmpty && s.qualities.isEmpty) continue;

      for (final sub in s.subtitles) {
        if (sub.url.isEmpty) continue;
        final cleanLabel = LanguageUtils.cleanLanguageName(sub.label);
        final exists = _extractedSubtitles.any(
          (existing) =>
              LanguageUtils.cleanLanguageName(existing.label).toLowerCase() ==
              cleanLabel.toLowerCase(),
        );
        if (!exists) {
          _extractedSubtitles.add(
            SubtitleTrack(
              url: sub.url,
              label: cleanLabel,
              language: sub.language,
            ),
          );
        }
      }

      final langLabel = s.language.trim().isNotEmpty
          ? s.language.trim()
          : 'Original';
      final serverName = s.sourceName.trim().isNotEmpty
          ? s.sourceName.trim()
          : 'Direct';
      final groupKey = '${langLabel.toLowerCase()}_${serverName.toLowerCase()}';

      final isHlsStream = s.type == 'hls' || s.url.contains('.m3u8');
      final List<_ExtractedQualityItem> qItems = [];

      if (s.qualities.isNotEmpty) {
        for (final q in s.qualities) {
          if (q.url.isEmpty) continue;
          final qIsHls = isHlsStream || q.url.contains('.m3u8');
          final height = q.height > 0
              ? q.height
              : (int.tryParse(q.label.replaceAll(RegExp(r'\D'), '')) ?? 1080);
          final label = q.label.isNotEmpty ? q.label : '${height}p';
          qItems.add(
            _ExtractedQualityItem(
              label: label,
              height: height,
              url: q.url,
              headers: s.headers,
              isHls: qIsHls,
              serverName: serverName,
              isProbingSize: !qIsHls,
            ),
          );
        }
      } else if (s.url.isNotEmpty) {
        final height = int.tryParse(
                (s.qualityLabel ?? '1080').replaceAll(RegExp(r'\D'), '')) ??
            1080;
        qItems.add(
          _ExtractedQualityItem(
            label: s.qualityLabel ?? '${height}p',
            height: height,
            url: s.url,
            headers: s.headers,
            isHls: isHlsStream,
            serverName: serverName,
            isProbingSize: !isHlsStream,
          ),
        );
      }

      if (qItems.isEmpty) continue;
      qItems.sort((a, b) => b.height.compareTo(a.height));

      final existingGroupIdx =
          _audioGroups.indexWhere((g) => g.key == groupKey);
      if (existingGroupIdx != -1) {
        final existing = _audioGroups[existingGroupIdx];
        for (final qi in qItems) {
          if (!existing.qualities.any((eq) => eq.height == qi.height)) {
            existing.qualities.add(qi);
            if (!qi.isHls) _probeFileSize(qi);
          }
        }
        existing.qualities.sort((a, b) => b.height.compareTo(a.height));
      } else {
        final newGroup = _ExtractedAudioGroup(
          key: groupKey,
          languageLabel: langLabel,
          serverName: serverName,
          qualities: qItems,
        );
        _audioGroups.add(newGroup);
        for (final qi in qItems) {
          if (!qi.isHls) _probeFileSize(qi);
        }
      }
    }

    _applySavedSelections();
    if (mounted) setState(() {});
  }

  void _applySavedSelections() {
    if (_audioGroups.isEmpty) return;

    if (_savedPreferredAudio != null && _savedPreferredAudio!.isNotEmpty) {
      final idx = _audioGroups.indexWhere(
        (g) => LanguageUtils.matches(g.languageLabel, _savedPreferredAudio!),
      );
      if (idx != -1) {
        _selectedAudioIndex = idx;
      }
    }

    if (_selectedAudioIndex >= _audioGroups.length) {
      _selectedAudioIndex = 0;
    }

    final currentQualities = _audioGroups[_selectedAudioIndex].qualities;
    if (_savedPreferredQuality != null && currentQualities.isNotEmpty) {
      final prefH =
          int.tryParse(_savedPreferredQuality!.replaceAll(RegExp(r'\D'), '')) ??
              1080;
      final qIdx = currentQualities.indexWhere((q) => q.height == prefH);
      if (qIdx != -1) {
        _selectedQualityIndex = qIdx;
      } else {
        _selectedQualityIndex = 0;
      }
    } else {
      _selectedQualityIndex = 0;
    }

    if (_extractedSubtitles.isNotEmpty && _selectedSubtitleIndex == -1) {
      if (_savedPreferredSub != null &&
          _savedPreferredSub != 'Off / None' &&
          _savedPreferredSub!.isNotEmpty) {
        final sIdx = _extractedSubtitles.indexWhere(
          (s) => LanguageUtils.matches(s.label, _savedPreferredSub!),
        );
        if (sIdx != -1) {
          _selectedSubtitleIndex = sIdx;
        }
      } else {
        final enIdx = _extractedSubtitles.indexWhere(
          (s) => LanguageUtils.matches(s.label, 'English'),
        );
        if (enIdx != -1) {
          _selectedSubtitleIndex = enIdx;
        }
      }
    }
  }

  Future<void> _probeFileSize(_ExtractedQualityItem item) async {
    try {
      final uri = Uri.parse(item.url);
      final headRes = await http
          .head(uri, headers: item.headers)
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

      final rangeHeaders = Map<String, String>.from(item.headers);
      rangeHeaders['Range'] = 'bytes=0-0';
      final req = http.Request('GET', uri)..headers.addAll(rangeHeaders);
      final streamed = await req.send().timeout(const Duration(seconds: 4));
      final contentRange = streamed.headers['content-range'] ?? '';
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
    } catch (_) {}

    if (mounted) {
      setState(() {
        item.isProbingSize = false;
      });
    }
  }

  Future<void> _extractRealStreams() async {
    final tasks = <Future<void>>[
      () async {
        try {
          final streams = await StreamExtractor.extractNetMirror(
            type: widget.mediaType,
            tmdbId: widget.mediaId,
            season: widget.season,
            episode: widget.episode,
          ).timeout(const Duration(seconds: 8));
          _ingestStreams(streams);
        } catch (_) {}
      }(),
      () async {
        try {
          final stream = await StreamExtractor.extractVoidflixBackend(
            type: widget.mediaType,
            tmdbId: widget.mediaId,
            season: widget.season,
            episode: widget.episode,
          ).timeout(const Duration(seconds: 8));
          if (stream != null) _ingestStreams([stream]);
        } catch (_) {}
      }(),
      () async {
        try {
          final stream = await StreamExtractor.extractVidlink(
            type: widget.mediaType,
            tmdbId: widget.mediaId,
            season: widget.season,
            episode: widget.episode,
          ).timeout(const Duration(seconds: 8));
          if (stream != null) _ingestStreams([stream]);
        } catch (_) {}
      }(),
      () async {
        try {
          final streams = await StreamExtractor.extractCinejoy(
            type: widget.mediaType,
            tmdbId: widget.mediaId,
            season: widget.season,
            episode: widget.episode,
            title: widget.title,
          ).timeout(const Duration(seconds: 8));
          _ingestStreams(streams);
        } catch (_) {}
      }(),
      () async {
        try {
          final extSubs = await StreamExtractor.getSharedSubtitles(
            widget.mediaType,
            widget.mediaId,
            widget.season,
            widget.episode,
          ).timeout(const Duration(seconds: 6));
          if (!mounted) return;
          for (final sub in extSubs) {
            if (sub.url.isEmpty) continue;
            final cleanLabel = LanguageUtils.cleanLanguageName(sub.label);
            final exists = _extractedSubtitles.any(
              (existing) =>
                  LanguageUtils.cleanLanguageName(existing.label)
                      .toLowerCase() ==
                  cleanLabel.toLowerCase(),
            );
            if (!exists) {
              _extractedSubtitles.add(
                SubtitleTrack(
                  url: sub.url,
                  label: cleanLabel,
                  language: sub.language,
                ),
              );
            }
          }
          _applySavedSelections();
          if (mounted) setState(() {});
        } catch (_) {}
      }(),
    ];

    await Future.wait(tasks);
    if (mounted) {
      setState(() {
        _isExtracting = false;
      });
    }
  }

  Future<void> _startDownload() async {
    final downloadProvider = widget.parentContext.read<DownloadProvider>();
    final messenger = ScaffoldMessenger.of(widget.parentContext);

    final hasExtracted = _audioGroups.isNotEmpty;
    final selectedGroup = hasExtracted
        ? _audioGroups[_selectedAudioIndex.clamp(0, _audioGroups.length - 1)]
        : null;
    final selectedQuality = selectedGroup != null &&
            selectedGroup.qualities.isNotEmpty
        ? selectedGroup.qualities[
            _selectedQualityIndex.clamp(0, selectedGroup.qualities.length - 1)]
        : null;
    final selectedSub = _selectedSubtitleIndex >= 0 &&
            _selectedSubtitleIndex < _extractedSubtitles.length
        ? _extractedSubtitles[_selectedSubtitleIndex]
        : null;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (selectedQuality != null) {
        await prefs.setString(
            'voidflix_preferred_dl_quality', selectedQuality.label);
      }
      if (selectedGroup != null) {
        await prefs.setString(
            'voidflix_preferred_audio_lang', selectedGroup.languageLabel);
      }
      await prefs.setString(
        'voidflix_preferred_subtitle_lang',
        selectedSub?.label ?? 'Off / None',
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pop();

    final displayTitle =
        widget.mediaType == 'tv' && widget.episodeTitle != null
            ? '${widget.title} S${widget.season}:E${widget.episode}'
            : widget.title;

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
      preferredQuality: selectedQuality?.label ?? '1080p',
      preferredAudio: selectedGroup?.languageLabel ?? 'Original',
      preferredSubtitle: selectedSub?.label ?? 'Off / None',
      directStreamUrl: selectedQuality?.url,
      directHeaders: selectedQuality?.headers,
      directIsHls: selectedQuality?.isHls,
      directSubtitles: selectedSub != null ? [selectedSub] : _extractedSubtitles,
    );

    final summary = selectedQuality != null && selectedGroup != null
        ? '${selectedQuality.label} • ${selectedGroup.languageLabel}'
        : 'Standard';

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF181818),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Colors.white12),
        ),
        content: Row(
          children: [
            const Icon(Icons.downloading_rounded, color: _darkRedBorder, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Downloading $displayTitle ($summary)',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displaySubtitle = widget.mediaType == 'tv'
        ? '${widget.title} · S${widget.season}:E${widget.episode}${widget.episodeTitle != null ? ' "${widget.episodeTitle}"' : ''}'
        : widget.title;

    final currentGroup = _audioGroups.isNotEmpty
        ? _audioGroups[_selectedAudioIndex.clamp(0, _audioGroups.length - 1)]
        : null;
    final currentQualities = currentGroup?.qualities ?? [];
    final currentQuality = currentQualities.isNotEmpty
        ? currentQualities[
            _selectedQualityIndex.clamp(0, currentQualities.length - 1)]
        : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag indicator
            Center(
              child: Container(
                width: 34,
                height: 3.5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Minimal Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Download',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displaySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isExtracting && _audioGroups.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const Divider(color: Colors.white10, height: 22),

            if (_audioGroups.isEmpty && _isExtracting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: _darkRedBorder,
                          strokeWidth: 2.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Fetching available streams…',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_audioGroups.isEmpty && !_isExtracting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Text(
                      'Direct streams unavailable. Use fallback downloader below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _startDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _darkRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Download',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // 1. Audio Track (Horizontal Pill Strip)
              const Text(
                'AUDIO',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _audioGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final group = _audioGroups[idx];
                    final isSelected = _selectedAudioIndex == idx;
                    return TvFocusable(
                      autofocus: idx == 0,
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () {
                        setState(() {
                          _selectedAudioIndex = idx;
                          _selectedQualityIndex = 0;
                        });
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAudioIndex = idx;
                            _selectedQualityIndex = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? _selectedBg : _cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? _darkRedBorder : Colors.white10,
                              width: isSelected ? 1.2 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                group.languageLabel,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                group.serverName,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 2. Video Resolution (Clean Minimal List Rows)
              const Text(
                'QUALITY',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: currentQualities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, qIdx) {
                    final q = currentQualities[qIdx];
                    final isSelected = _selectedQualityIndex == qIdx;
                    return TvFocusable(
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () {
                        setState(() => _selectedQualityIndex = qIdx);
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedQualityIndex = qIdx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: isSelected ? _selectedBg : _cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? _darkRedBorder : Colors.white10,
                              width: isSelected ? 1.2 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 18,
                                color: isSelected
                                    ? _darkRedBorder
                                    : Colors.white30,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  q.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF262626),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  q.formattedSize,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // 3. Subtitles (Horizontal Pill Strip)
              const Text(
                'SUBTITLES',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _extractedSubtitles.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final isOff = idx == 0;
                    final sIdx = idx - 1;
                    final isSelected = isOff
                        ? _selectedSubtitleIndex == -1
                        : _selectedSubtitleIndex == sIdx;
                    final label =
                        isOff ? 'Off' : _extractedSubtitles[sIdx].label;

                    return TvFocusable(
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () {
                        setState(() =>
                            _selectedSubtitleIndex = isOff ? -1 : sIdx);
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() =>
                              _selectedSubtitleIndex = isOff ? -1 : sIdx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? _selectedBg : _cardBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? _darkRedBorder : Colors.white10,
                              width: isSelected ? 1.2 : 1.0,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 4. Primary Download Button
              TvFocusable(
                borderRadius: BorderRadius.circular(8),
                onPressed: _startDownload,
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _darkRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.file_download_outlined,
                        color: Colors.white, size: 20),
                    label: Text(
                      'Download · ${currentQuality?.label ?? ''} · ${currentGroup?.languageLabel ?? ''}${currentQuality?.fileSizeBytes != null ? ' (${currentQuality!.formattedSize})' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
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
