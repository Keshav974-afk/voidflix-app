import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/api_constants.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

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
    }
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        titleSpacing: 14,
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
    );
  }
}
