import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../models/media_item.dart';
import '../providers/media_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/detail_modal.dart';
import 'player_screen.dart';

class ClipsScreen extends StatefulWidget {
  const ClipsScreen({super.key});

  @override
  State<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends State<ClipsScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isMuted = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaProvider = context.watch<MediaProvider>();
    final clips = mediaProvider.trending;

    if (clips.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryRed)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: clips.length,
        onPageChanged: (index) {
          setState(() => _currentPage = index);
        },
        itemBuilder: (context, index) {
          final item = clips[index];
          final isCurrent = index == _currentPage;

          return ClipPlayerTile(
            key: ValueKey('clip_${item.id}'),
            item: item,
            isActive: isCurrent,
            isMuted: _isMuted,
            onToggleMute: () {
              setState(() => _isMuted = !_isMuted);
            },
          );
        },
      ),
    );
  }
}

class ClipPlayerTile extends StatefulWidget {
  final MediaItem item;
  final bool isActive;
  final bool isMuted;
  final VoidCallback onToggleMute;

  const ClipPlayerTile({
    super.key,
    required this.item,
    required this.isActive,
    required this.isMuted,
    required this.onToggleMute,
  });

  @override
  State<ClipPlayerTile> createState() => _ClipPlayerTileState();
}

class _ClipPlayerTileState extends State<ClipPlayerTile> {
  final ApiService _apiService = ApiService();
  String? _trailerKey;
  WebViewController? _webController;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _fetchTrailer();
  }

  @override
  void didUpdateWidget(covariant ClipPlayerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive || oldWidget.isMuted != widget.isMuted) {
      if (widget.isActive && _trailerKey != null) {
        _initWebController(_trailerKey!);
      }
    }
  }

  Future<void> _fetchTrailer() async {
    try {
      final detail = await _apiService.getDetails(widget.item.mediaType, widget.item.id);
      if (!mounted) return;

      final trailer = detail.videos.where((v) =>
          v.site.toLowerCase() == 'youtube' &&
          v.type.toLowerCase() == 'trailer').firstOrNull ??
          detail.videos.where((v) => v.site.toLowerCase() == 'youtube').firstOrNull;

      if (trailer != null && trailer.key.isNotEmpty) {
        _trailerKey = trailer.key;
        if (widget.isActive) {
          _initWebController(trailer.key);
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  void _initWebController(String key) {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString('''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; background-color: #000; overflow: hidden; }
            html, body { width: 100%; height: 100%; }
            iframe { width: 100%; height: 100%; border: 0; pointer-events: auto; }
          </style>
        </head>
        <body>
          <iframe
            src="https://www.youtube-nocookie.com/embed/$key?autoplay=1&mute=${widget.isMuted ? 1 : 0}&controls=1&modestbranding=1&rel=0&playsinline=1&loop=1&playlist=$key"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen>
          </iframe>
        </body>
        </html>
      ''');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = context.watch<WatchlistProvider>();
    final isInWatchlist = watchlistProvider.isInWatchlist(widget.item.id);

    final backdropUrl = ApiService.getImageUrl(
      widget.item.backdropPath ?? widget.item.posterPath,
      size: 'original',
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Trailer Video Player or High-Res Backdrop Fallback
        if (widget.isActive && _webController != null && _trailerKey != null)
          Positioned.fill(
            child: WebViewWidget(controller: _webController!),
          )
        else
          CachedNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            placeholder: (c, u) => Container(color: Colors.black),
            errorWidget: (c, u, e) => Container(color: Colors.black),
          ),

        // 2. Subtle Gradient Overlay for readable UI
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x77000000),
                    Colors.transparent,
                    Color(0x99000000),
                    Color(0xF0000000),
                  ],
                  stops: [0.0, 0.35, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 3. Top Sound & Trailer Badge
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryRed, width: 1.2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.movie_filter_outlined, color: AppTheme.primaryRed, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'OFFICIAL TRAILER CLIP',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onToggleMute,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4. Right Side Actions (Reels / Netflix style vertical icons)
        Positioned(
          right: 14,
          bottom: 110,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Like / Rate
              _buildRightAction(
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                label: 'Like',
                color: _isLiked ? AppTheme.primaryRed : Colors.white,
                onTap: () {
                  setState(() => _isLiked = !_isLiked);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isLiked ? 'Added to your likes' : 'Removed from likes'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // My List
              _buildRightAction(
                icon: isInWatchlist ? Icons.check : Icons.add,
                label: 'My List',
                color: isInWatchlist ? AppTheme.primaryRed : Colors.white,
                onTap: () => watchlistProvider.toggleWatchlist(widget.item),
              ),
              const SizedBox(height: 18),

              // Native Share
              _buildRightAction(
                icon: Icons.share_outlined,
                label: 'Share',
                color: Colors.white,
                onTap: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Watch "${widget.item.title}" trailer on Voidflix!\nhttps://voidflix.org/${widget.item.mediaType}/${widget.item.id}',
                      subject: 'Watch ${widget.item.title} on Voidflix',
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // Info
              _buildRightAction(
                icon: Icons.info_outline,
                label: 'Details',
                color: Colors.white,
                onTap: () => DetailModal.show(context, widget.item),
              ),
            ],
          ),
        ),

        // 5. Bottom Metadata & "Watch Full Movie / Show" Button
        Positioned(
          left: 16,
          right: 80,
          bottom: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (widget.item.overview.isNotEmpty)
                Text(
                  widget.item.overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 8),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                label: Text(
                  widget.item.mediaType == 'tv' ? 'Watch Full Series' : 'Watch Full Movie',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        mediaId: widget.item.id,
                        mediaTitle: widget.item.title,
                        mediaType: widget.item.mediaType,
                        posterPath: widget.item.posterPath,
                        backdropPath: widget.item.backdropPath,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
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
    );
  }
}
