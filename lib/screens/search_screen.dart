import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../core/utils/platform_utils.dart';
import '../models/media_item.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import '../widgets/tv_back_button.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ApiService _apiService = ApiService();
  Timer? _debounce;
  List<MediaItem> _results = [];
  List<MediaItem> _recommendations = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    try {
      final trending = await _apiService.getTrendingAll();
      if (mounted) setState(() => _recommendations = trending);
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final items = await _apiService.search(query);
      if (mounted) {
        setState(() {
          _results = items;
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          mediaId: item.id,
          mediaType: item.mediaType,
        ),
      ),
    );
  }

  void _playItem(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: item.id,
          mediaTitle: item.title,
          mediaType: item.mediaType,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _controller.text.trim().isNotEmpty;
    final displayList = isSearching ? _results : _recommendations;
    final canPop = Navigator.of(context).canPop();

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: canPop ? const TvBackButton() : null,
          automaticallyImplyLeading: false,
          titleSpacing: canPop ? 0 : 14,
        title: Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF23232B),
            borderRadius: BorderRadius.circular(6),
          ),
          child: TextField(
            controller: _controller,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search shows, movies, games...',
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 22),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _performSearch('');
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.mic, color: Colors.white70, size: 22),
                      tooltip: 'Voice Search',
                      onPressed: _startVoiceSearch,
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title (Screenshot 5: "Recommended Shows & Movies")
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              isSearching ? 'Search Results' : 'Recommended Shows & Movies',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
                color: Colors.white,
              ),
            ),
          ),

          // List of Items (Screenshot 5)
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryRed),
                  )
                : displayList.isEmpty
                    ? Center(
                        child: Text(
                          isSearching ? 'No titles found for "${_controller.text}".' : 'Loading recommendations...',
                          style: const TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96, left: 14, right: 14),
                        itemCount: displayList.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = displayList[index];
                          final imageUrl = ApiConstants.getImageUrl(item.backdropPath ?? item.posterPath, size: 'w500');

                          String? badgeText;
                          if (index % 4 == 1) badgeText = 'Recently added';
                          if (index % 4 == 3) badgeText = 'New Episode';

                          return GestureDetector(
                            onTap: () => _openDetail(item),
                            child: Container(
                              height: 84,
                              color: Colors.transparent,
                              child: Row(
                                children: [
                                  // Landscape Thumbnail (Screenshot 5)
                                  Container(
                                    width: 140,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      color: AppTheme.cardColor,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        imageUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: imageUrl,
                                                fit: BoxFit.cover,
                                                placeholder: (c, u) => Container(color: AppTheme.surfaceVariant),
                                                errorWidget: (c, u, e) => Container(color: AppTheme.surfaceVariant),
                                              )
                                            : Container(color: AppTheme.surfaceVariant),

                                        // Badge overlay (Recently added / New Episode) (Screenshot 5)
                                        if (badgeText != null)
                                          Positioned(
                                            left: 6,
                                            bottom: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryRed,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                badgeText,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Title (Screenshot 5)
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),

                                  // Circular Play Outline Button (Screenshot 5)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: () => _playItem(item),
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
      'Breaking Bad',
      'Inception',
      'Action Movies',
      'Anime',
      'Comedy',
    ];

    return Dialog(
      backgroundColor: const Color(0xFF181822),
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
                    width: 2.5,
                  ),
                  boxShadow: _isListening
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryRed.withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: _isListening ? AppTheme.primaryRed : Colors.white70,
                    size: 38,
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
                color: _recognizedText != null ? const Color(0xFF2ECC71) : Colors.white,
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
                  '💡 Tip: Press Windows Key + H anytime to dictate text anywhere',
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
                      color: const Color(0xFF232330),
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

