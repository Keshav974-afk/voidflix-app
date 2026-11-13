import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/tv_mode_service.dart';
import '../core/utils/platform_utils.dart';
import '../models/media_item.dart';
import '../providers/history_provider.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import '../widgets/detail_modal.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _firstFilterChipFocusNode = FocusNode();
  final FocusNode _firstResultFocusNode = FocusNode();
  final ApiService _apiService = ApiService();
  Timer? _debounce;
  List<MediaItem> _results = [];
  List<MediaItem> _recommendations = [];
  SmartSearchResult? _smartResult;
  bool _isLoading = false;
  String _selectedQuickFilter = 'All';

  static const List<String> _quickFilters = [
    'All',
    'Anime',
    'Bollywood',
    'South Indian',
    'K-Drama',
    'Hollywood',
    'Action',
    'Sci-Fi',
    'Horror',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    try {
      List<MediaItem> items = [];
      switch (_selectedQuickFilter) {
        case 'Anime':
          final tv = await _apiService.getAnime();
          final mov = await _apiService.getAnimeMovies();
          items = [...tv, ...mov];
          break;
        case 'Bollywood':
          final mov = await _apiService.getBollywoodMovies();
          final tv = await _apiService.getIndianSeries();
          items = [...mov, ...tv];
          break;
        case 'South Indian':
          items = await _apiService.getSouthIndianMovies();
          break;
        case 'K-Drama':
          items = await _apiService.getAsianDrama();
          break;
        case 'Hollywood':
          items = await _apiService.getPopularMovies();
          break;
        case 'Action':
          items = await _apiService.getActionMovies();
          break;
        case 'Sci-Fi':
          items = await _apiService.getSciFiMovies();
          break;
        case 'Horror':
          items = await _apiService.getHorrorMovies();
          break;
        case 'All':
        default:
          final batch = await Future.wait([
            _apiService.getTrendingAll().catchError((_) => <MediaItem>[]),
            _apiService.getBollywoodMovies().catchError((_) => <MediaItem>[]),
            _apiService.getAnime().catchError((_) => <MediaItem>[]),
            _apiService.getSouthIndianMovies().catchError((_) => <MediaItem>[]),
            _apiService.getAsianDrama().catchError((_) => <MediaItem>[]),
          ]);
          final seen = <String>{};
          for (int i = 0; i < 15; i++) {
            for (final list in batch) {
              if (i < list.length) {
                final it = list[i];
                if (seen.add('${it.mediaType}_${it.id}')) {
                  items.add(it);
                }
              }
            }
          }
          break;
      }
      if (mounted) {
        setState(() {
          _recommendations = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _smartResult = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final smart = await _apiService.smartSearch(query);
      if (mounted) {
        setState(() {
          _smartResult = smart;
          _results = smart.results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startVoiceSearch() async {
    if (PlatformUtils.isWindows || PlatformUtils.isDesktop) {
      _showVoiceSearchDialog();
      return;
    }

    const channel = MethodChannel('org.voidflix/notifications');
    try {
      final spoken = await channel.invokeMethod<String>('startVoiceSearch');
      if (spoken != null && spoken.trim().isNotEmpty && mounted) {
        setState(() {
          _controller.text = spoken.trim();
        });
        _performSearch(spoken.trim());
      }
    } catch (e) {
      debugPrint('Voice search platform error: $e');
      if (mounted) {
        _showVoiceSearchDialog();
      }
    }
  }

  void _showVoiceSearchDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => _VoiceSearchDialog(
        onRecognized: (text) {
          if (mounted && text.trim().isNotEmpty) {
            setState(() {
              _controller.text = text.trim();
            });
            _performSearch(text.trim());
          }
        },
      ),
    );
  }

  void _openDetail(MediaItem item) {
    FocusScope.of(context).unfocus();
    if (TvModeService().isTvMode) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            mediaId: item.id,
            mediaType: item.mediaType,
          ),
        ),
      );
    } else {
      DetailModal.show(context, item);
    }
  }

  void _playItem(MediaItem item) {
    FocusScope.of(context).unfocus();
    final saved = context.read<HistoryProvider>().getProgress(item.id);
    final posSec = (saved != null && saved.positionSeconds > 0)
        ? saved.positionSeconds.toDouble()
        : (saved != null && saved.progress > 0 && saved.durationSeconds > 0
            ? (saved.progress * saved.durationSeconds).toDouble()
            : null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.id,
          mediaTitle: item.title,
          mediaType: item.mediaType,
          season: saved?.season ?? 1,
          episode: saved?.episode ?? 1,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
          startPositionSeconds: posSec,
        ),
      ),
    );
  }

  String _resolveRegionBadge(MediaItem item) {
    final lang = item.originalLanguage.toLowerCase();
    if (lang == 'ja' && item.genreIds.contains(16)) return 'ANIME';
    if (lang == 'hi') return 'HINDI';
    if (lang == 'te' || lang == 'ta' || lang == 'ml' || lang == 'kn') return 'SOUTH';
    if (lang == 'ko') return 'K-DRAMA';
    return item.mediaType == 'tv' ? 'SERIES' : 'MOVIE';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _controller.text.trim().isNotEmpty;
    final displayList = isSearching ? _results : _recommendations;
    final canPop = Navigator.of(context).canPop();
    final isTv = TvModeService().isTvMode || TvModeService().isHardwareTv;

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: canPop ? const TvBackButton() : null,
          automaticallyImplyLeading: false,
          titleSpacing: canPop ? 0 : 16,
          title: Padding(
            padding: EdgeInsets.only(right: canPop ? 16 : 0),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1,
                ),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (isTv && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    if (!isSearching) {
                      _firstFilterChipFocusNode.requestFocus();
                    } else {
                      _firstResultFocusNode.requestFocus();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _controller,
                  cursorColor: AppTheme.primaryRed,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) {
                    _performSearch(query);
                    FocusScope.of(context).unfocus();
                    if (isTv) {
                      _firstResultFocusNode.requestFocus();
                    }
                  },
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search movies, anime, Bollywood, series...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70, size: 21),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 19),
                            onPressed: () {
                              _controller.clear();
                              _performSearch('');
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.mic_none_rounded, color: Colors.white70, size: 21),
                            tooltip: 'Voice Search',
                            onPressed: _startVoiceSearch,
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Horizontal Quick Filter Chips (All, Anime, Bollywood, South Indian, K-Drama, etc.)
            if (!isSearching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _quickFilters.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final label = _quickFilters[idx];
                      final isSelected = _selectedQuickFilter == label;
                      return TvFocusable(
                        focusNode: idx == 0 ? _firstFilterChipFocusNode : null,
                        borderRadius: BorderRadius.circular(18),
                        glowColor: Colors.white,
                        onPressed: () {
                          if (_selectedQuickFilter != label) {
                            setState(() => _selectedQuickFilter = label);
                            _loadRecommendations();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white70,
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Section Title & Smart Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      isSearching
                          ? 'Search Results'
                          : (_selectedQuickFilter == 'All'
                              ? 'Recommended Across All Categories'
                              : 'Top $_selectedQuickFilter Picks'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isSearching && _smartResult?.detectedYear != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryRed, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            '${_smartResult!.detectedYear}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  if (isSearching && _smartResult?.detectedCategory != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_movies_rounded, color: AppTheme.primaryRed, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            _smartResult!.detectedCategory!,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Auto-correction suggestion banner (Matte Carbon & Dark Red)
            if (isSearching && _smartResult?.wasAutoCorrected == true && _smartResult?.correctedQuery != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_fix_high_rounded, color: AppTheme.primaryRed, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                            children: [
                              const TextSpan(text: 'Showing results for '),
                              TextSpan(
                                text: _smartResult!.correctedQuery!,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: '  •  "${_smartResult!.originalQuery}"',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // List of Items
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryRed),
                    )
                  : displayList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.movie_filter_outlined, color: Colors.white24, size: 42),
                              const SizedBox(height: 10),
                              Text(
                                isSearching
                                    ? 'No titles found for "${_controller.text}".'
                                    : 'Loading recommendations...',
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96, left: 16, right: 16, top: 2),
                          itemCount: displayList.length,
                          separatorBuilder: (c, i) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = displayList[index];
                            final imageUrl = ApiConstants.getImageUrl(
                              item.backdropPath ?? item.posterPath,
                              size: 'w342',
                            );
                            final regionBadge = _resolveRegionBadge(item);

                            return RepaintBoundary(
                              child: TvFocusable(
                                focusNode: index == 0 ? _firstResultFocusNode : null,
                                scaleFactor: 1.02,
                                glowColor: AppTheme.primaryRed,
                                borderRadius: BorderRadius.circular(10),
                                onPressed: () => _openDetail(item),
                                child: Container(
                                  height: 86,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF121212),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Landscape Thumbnail
                                      Container(
                                        width: 132,
                                        height: 74,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(7),
                                          color: const Color(0xFF1A1A1A),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            imageUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: imageUrl,
                                                    fit: BoxFit.cover,
                                                    memCacheWidth: 264,
                                                    memCacheHeight: 148,
                                                    filterQuality: FilterQuality.low,
                                                    placeholder: (c, u) => Container(color: const Color(0xFF1A1A1A)),
                                                    errorWidget: (c, u, e) => Container(color: const Color(0xFF1A1A1A)),
                                                  )
                                              : Container(color: const Color(0xFF1A1A1A)),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black.withValues(alpha: 0.55),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: 6,
                                            bottom: 5,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.78),
                                                borderRadius: BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: Colors.white.withValues(alpha: 0.18),
                                                  width: 0.6,
                                                ),
                                              ),
                                              child: Text(
                                                regionBadge,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.6,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Title, Type, Year & Rating (Pure Matte Carbon, White & Dark Red)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: item.mediaType == 'tv'
                                                      ? const Color(0xFF1E1E1E)
                                                      : AppTheme.darkRed.withValues(alpha: 0.22),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: item.mediaType == 'tv'
                                                        ? Colors.white24
                                                        : AppTheme.primaryRed.withValues(alpha: 0.45),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Text(
                                                  item.mediaType == 'tv' ? 'SERIES' : 'MOVIE',
                                                  style: TextStyle(
                                                    color: item.mediaType == 'tv' ? Colors.white70 : Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                              if (item.year.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  item.year,
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                              if (item.voteAverage > 0) ...[
                                                const SizedBox(width: 8),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.star_rounded,
                                                      color: AppTheme.primaryRed,
                                                      size: 13,
                                                    ),
                                                    const SizedBox(width: 2.5),
                                                    Text(
                                                      item.voteAverage.toStringAsFixed(1),
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Clean Matte Play Button
                                    GestureDetector(
                                      onTap: () => _playItem(item),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF1C1C1C),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.22),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 20,
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
          ],
        ),
      ),
    );
  }
}

class _VoiceSearchDialog extends StatefulWidget {
  final ValueChanged<String> onRecognized;

  const _VoiceSearchDialog({required this.onRecognized});

  @override
  State<_VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<_VoiceSearchDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;
  bool _isListening = true;
  String _statusText = 'Listening… Speak into your microphone now.';
  String? _recognizedText;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.25).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _startWindowsListening();
  }

  Future<void> _startWindowsListening() async {
    if (!PlatformUtils.isWindows) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusText = 'Say a movie title or choose from suggestions below.';
        });
      }
      return;
    }

    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Add-Type -AssemblyName System.Speech; \$rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine; \$rec.SetInputToDefaultAudioDevice(); \$rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar)); \$res = \$rec.Recognize([TimeSpan]::FromSeconds(5)); if (\$res) { Write-Output \$res.Text }',
        ],
      ).timeout(const Duration(seconds: 7));

      final spoken = result.stdout.toString().trim();
      if (spoken.isNotEmpty && mounted) {
        setState(() {
          _isListening = false;
          _recognizedText = spoken;
          _statusText = 'Recognized: "$spoken"';
        });
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.of(context).pop();
          widget.onRecognized(spoken);
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isListening = false;
        _statusText = 'Didn\'t catch that. Tap below or type to search.';
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      'Stranger Things',
      'Jujutsu Kaisen',
      'Jawan',
      'Kalki 2898 AD',
      'Squid Game',
      'Inception',
    ];

    return Dialog(
      backgroundColor: const Color(0xFF121212),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VOICE SEARCH',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Pulsing Mic Icon
            ScaleTransition(
              scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryRed.withValues(alpha: 0.15),
                  border: Border.all(
                    color: _isListening ? AppTheme.primaryRed : Colors.white24,
                    width: 2.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: _isListening ? AppTheme.primaryRed : Colors.white70,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Status Text
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _recognizedText != null ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),

            // Windows Hint
            if (PlatformUtils.isWindows)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Tip: Press Windows Key + H anytime to dictate text anywhere',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 20),

            // Popular Suggestions
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'POPULAR SEARCHES',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((s) {
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onRecognized(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
