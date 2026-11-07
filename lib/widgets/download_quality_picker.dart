import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
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
      backgroundColor: const Color(0xFF14141C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
  String _extractionStatus = 'Extracting available streams from servers…';

  final List<_ExtractedAudioGroup> _audioGroups = [];
  final List<SubtitleTrack> _extractedSubtitles = [];

  int _selectedAudioIndex = 0;
  int _selectedQualityIndex = 0;
  int _selectedSubtitleIndex = -1; // -1 = Off / None

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

      // Ingest any embedded subtitles from this stream
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
      // 1. Try HEAD request first
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

      // 2. Fallback: Range bytes=0-0 GET request to inspect Content-Range
      final rangeHeaders = Map<String, String>.from(item.headers);
      rangeHeaders['Range'] = 'bytes=0-0';
      final req = http.Request('GET', uri)..headers.addAll(rangeHeaders);
      final streamed =
          await req.send().timeout(const Duration(seconds: 4));
      final contentRange = streamed.headers['content-range'] ?? '';
      // e.g. "bytes 0-0/845921024"
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
      // 1. StellarHD / NetMirror (Multi-Audio & Multi-Quality Direct MP4)
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

      // 2. Voidflix Backend
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

      // 3. Vidlink
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

      // 4. NebulaHD & Cine4K
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

      // 5. External Subtitles (Wyzie / OpenSubtitles)
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
        if (_audioGroups.isEmpty) {
          _extractionStatus = 'No direct streams returned. Ready to use fallback downloader.';
        }
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
        : 'Best Available Quality';

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1F1F28),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.downloading_rounded,
                color: AppTheme.primaryRed, size: 20),
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
        ? '${widget.title} • S${widget.season}:E${widget.episode}${widget.episodeTitle != null ? ' "${widget.episodeTitle}"' : ''}'
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
          left: 18,
          right: 18,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.download_for_offline_rounded,
                      color: AppTheme.primaryRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Download Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displaySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
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
                          strokeWidth: 2,
                          color: AppTheme.primaryRed,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Loading state while waiting for first extracted stream
              if (_audioGroups.isEmpty && _isExtracting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: AppTheme.primaryRed,
                          strokeWidth: 2.5,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _extractionStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Fetching real resolutions, audio dubs & subtitles…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11.5,
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
                      const Icon(Icons.cloud_download_outlined,
                          color: Colors.white54, size: 36),
                      const SizedBox(height: 10),
                      Text(
                        _extractionStatus,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _startDownload,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryRed,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.file_download_rounded),
                          label: const Text('Start Auto-Fallback Download'),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // 1. Extracted Audio Tracks Section
                Row(
                  children: [
                    const Icon(Icons.graphic_eq_rounded,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Available Audio Tracks (${_audioGroups.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_audioGroups.length, (idx) {
                    final group = _audioGroups[idx];
                    final isSelected = _selectedAudioIndex == idx;
                    return TvFocusable(
                      autofocus: idx == 0,
                      borderRadius: BorderRadius.circular(20),
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0071EB)
                                : const Color(0xFF1F1F2B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF3898FF)
                                  : Colors.white12,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                group.languageLabel,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  group.serverName,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white70
                                        : Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),

                // 2. Extracted Video Resolutions for Selected Audio Track
                Row(
                  children: [
                    const Icon(Icons.hd_outlined,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Available Resolutions (${currentQualities.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.55,
                  children: List.generate(currentQualities.length, (qIdx) {
                    final q = currentQualities[qIdx];
                    final isSelected = _selectedQualityIndex == qIdx;
                    return TvFocusable(
                      borderRadius: BorderRadius.circular(10),
                      onPressed: () {
                        setState(() => _selectedQualityIndex = qIdx);
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedQualityIndex = qIdx);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryRed.withValues(alpha: 0.18)
                                : const Color(0xFF1F1F2B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryRed
                                  : Colors.white12,
                              width: isSelected ? 1.6 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                q.height >= 1080
                                    ? Icons.hd_rounded
                                    : q.height >= 720
                                        ? Icons.high_quality_rounded
                                        : Icons.sd_rounded,
                                color: isSelected
                                    ? AppTheme.primaryRed
                                    : Colors.white60,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      q.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      q.formattedSize,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: q.fileSizeBytes != null
                                            ? Colors.greenAccent
                                            : Colors.white38,
                                        fontSize: 10.5,
                                        fontWeight: q.fileSizeBytes != null
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.primaryRed,
                                  size: 16,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),

                // 3. Extracted Subtitles Section
                Row(
                  children: [
                    const Icon(Icons.subtitles_outlined,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Available Subtitles (${_extractedSubtitles.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Off / None chip
                    TvFocusable(
                      borderRadius: BorderRadius.circular(20),
                      onPressed: () {
                        setState(() => _selectedSubtitleIndex = -1);
                      },
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedSubtitleIndex = -1);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _selectedSubtitleIndex == -1
                                ? const Color(0xFF0071EB)
                                : const Color(0xFF1F1F2B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _selectedSubtitleIndex == -1
                                  ? const Color(0xFF3898FF)
                                  : Colors.white12,
                              width: _selectedSubtitleIndex == -1 ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text(
                            'Off / None',
                            style: TextStyle(
                              color: _selectedSubtitleIndex == -1
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: _selectedSubtitleIndex == -1
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Real extracted subtitles
                    ...List.generate(_extractedSubtitles.length, (sIdx) {
                      final sub = _extractedSubtitles[sIdx];
                      final isSelected = _selectedSubtitleIndex == sIdx;
                      return TvFocusable(
                        borderRadius: BorderRadius.circular(20),
                        onPressed: () {
                          setState(() => _selectedSubtitleIndex = sIdx);
                        },
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedSubtitleIndex = sIdx);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0071EB)
                                  : const Color(0xFF1F1F2B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF3898FF)
                                    : Colors.white12,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Text(
                              sub.label,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 22),

                // 4. Start Download Button
                TvFocusable(
                  borderRadius: BorderRadius.circular(10),
                  onPressed: _startDownload,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _startDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.file_download_rounded,
                          color: Colors.white, size: 22),
                      label: Text(
                        'Download • ${currentQuality?.label ?? ''} • ${currentGroup?.languageLabel ?? ''}${currentQuality?.fileSizeBytes != null ? ' (${currentQuality!.formattedSize})' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
