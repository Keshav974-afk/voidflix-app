import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import '../core/utils/platform_utils.dart';
import '../models/live_channel.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  String _selectedCategory = "All";
  int _focusedChannelIndex = 0;
  final ScrollController _channelScrollController = ScrollController();

  List<LiveChannel> get _filteredChannels {
    if (_selectedCategory == "All") return LiveData.channels;
    return LiveData.channels.where((c) => c.category == _selectedCategory).toList();
  }

  void _watchChannel(LiveChannel channel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveChannelPlayerScreen(
          channel: channel,
          allChannels: _filteredChannels,
          initialIndex: _filteredChannels.indexOf(channel),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channelScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvModeService().isTvMode;
    final canPop = Navigator.of(context).canPop();

    return TvScreenWrapper(
      onBack: canPop ? () => Navigator.of(context).pop() : null,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D12),
        body: isTv ? _buildIptvTvLayout(canPop) : _buildStandardLayout(canPop),
      ),
    );
  }

  // =========================================================================
  // 10-FOOT IPTV TV MODE LAYOUT (3-PANEL: CATEGORIES | CHANNELS | PREVIEW)
  // =========================================================================
  Widget _buildIptvTvLayout(bool canPop) {
    final channels = _filteredChannels;
    final selectedChannel = channels.isNotEmpty && _focusedChannelIndex < channels.length
        ? channels[_focusedChannelIndex]
        : (channels.isNotEmpty ? channels.first : null);

    return SafeArea(
      child: Column(
        children: [
          // Top IPTV Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                if (canPop) ...[
                  const TvBackButton(),
                  const SizedBox(width: 14),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'LIVE IPTV',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'VOIDFLIX TELEVISION NETWORK',
                  style: GoogleFonts.bebasNeue(
                    fontSize: 30,
                    letterSpacing: 1.6,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Text(
                  'D-Pad: Navigate • OK: Watch Fullscreen',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Main 3-Column IPTV Layout
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Category Rail
                  SizedBox(
                    width: 220,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF14141B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(
                              'CATEGORIES',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: LiveData.categories.length,
                              itemBuilder: (context, index) {
                                final cat = LiveData.categories[index];
                                final isSelected = cat == _selectedCategory;
                                final count = cat == "All"
                                    ? LiveData.channels.length
                                    : LiveData.channels.where((c) => c.category == cat).length;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  child: TvFocusable(
                                    autofocus: index == 0,
                                    glowColor: AppTheme.primaryRed,
                                    borderRadius: BorderRadius.circular(8),
                                    onPressed: () {
                                      setState(() {
                                        _selectedCategory = cat;
                                        _focusedChannelIndex = 0;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF232330) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _getCategoryIcon(cat),
                                            color: isSelected ? Colors.white : Colors.white60,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              cat,
                                              style: TextStyle(
                                                color: isSelected ? Colors.white : Colors.white70,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black26,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$count',
                                              style: const TextStyle(color: Colors.white54, fontSize: 10),
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
                  ),
                  const SizedBox(width: 16),

                  // Center Column: Channels Guide List
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF14141B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$_selectedCategory CHANNELS (${channels.length})',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Text(
                                  'Press OK to Watch Fullscreen',
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: channels.isEmpty
                                ? const Center(
                                    child: Text('No channels found in this category', style: TextStyle(color: Colors.white54)),
                                  )
                                : ListView.builder(
                                    controller: _channelScrollController,
                                    itemCount: channels.length,
                                    itemBuilder: (context, index) {
                                      final ch = channels[index];
                                      final isFocused = index == _focusedChannelIndex;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        child: TvFocusable(
                                          glowColor: AppTheme.primaryRed,
                                          borderRadius: BorderRadius.circular(8),
                                          onPressed: () {
                                            setState(() => _focusedChannelIndex = index);
                                            _watchChannel(ch);
                                          },
                                          onFocusChange: (focused) {
                                            if (focused && _focusedChannelIndex != index) {
                                              setState(() => _focusedChannelIndex = index);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: isFocused ? const Color(0xFF2A2A38) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isFocused ? AppTheme.primaryRed : Colors.transparent,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                // Channel Number
                                                Container(
                                                  width: 38,
                                                  height: 24,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'CH ${(index + 1).toString().padLeft(2, '0')}',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                // Channel Logo / Icon
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1E1E28),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      _getCategoryIcon(ch.category),
                                                      color: isFocused ? AppTheme.primaryRed : Colors.white70,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                // Channel Info
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        ch.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                          fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        ch.category,
                                                        style: const TextStyle(
                                                          color: AppTheme.textMuted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Live Indicator
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 8),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'LIVE',
                                                        style: TextStyle(
                                                          color: Colors.redAccent,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: isFocused ? AppTheme.primaryRed : Colors.white30,
                                                  size: 22,
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
                  ),
                  const SizedBox(width: 16),

                  // Right Column: Channel Preview & Program Info Pane
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF14141B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: selectedChannel == null
                          ? const Center(child: Text('Select a channel', style: TextStyle(color: Colors.white54)))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Mini Video Preview Box
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Background gradient / artwork
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: RadialGradient(
                                              colors: [
                                                AppTheme.primaryRed.withValues(alpha: 0.25),
                                                Colors.black,
                                              ],
                                            ),
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.live_tv_rounded, color: AppTheme.primaryRed, size: 48),
                                            const SizedBox(height: 8),
                                            Text(
                                              selectedChannel.name,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Positioned(
                                          top: 8,
                                          left: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryRed,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              '1080p FHD',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Channel Metadata
                                Text(
                                  selectedChannel.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        selectedChannel.category,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('• 24/7 Live Stream • English', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  selectedChannel.description ?? 'Broadcasting high definition television network streams live inside Voidflix.',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                ),
                                const Spacer(),

                                // Big Fullscreen Action Button
                                TvFocusable(
                                  glowColor: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  onPressed: () => _watchChannel(selectedChannel),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryRed,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'WATCH FULLSCREEN',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STANDARD MOBILE & DESKTOP GRID LAYOUT
  // =========================================================================
  Widget _buildStandardLayout(bool canPop) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (canPop) ...[
                      const TvBackButton(),
                      const SizedBox(width: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'IPTV & SPORTS CHANNELS',
                      style: GoogleFonts.bebasNeue(
                        fontSize: 32,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Stream 24/7 global sports, news broadcasts, entertainment, and movie networks.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),

          // Category Chips
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: LiveData.categories.length,
              itemBuilder: (context, index) {
                final cat = LiveData.categories[index];
                final isSel = cat == _selectedCategory;

                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppTheme.primaryRed : const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? AppTheme.primaryRed : Colors.white24,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isSel ? Colors.white : Colors.white70,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Channels Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final count = (constraints.maxWidth / 200).floor().clamp(2, 6);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  childAspectRatio: 1.45,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _filteredChannels.length,
                itemBuilder: (context, index) {
                  final ch = _filteredChannels[index];

                  return GestureDetector(
                    onTap: () => _watchChannel(ch),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E2E2E)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(Icons.play_circle_outline, color: Colors.white70, size: 22),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ch.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ch.category,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'news':
        return Icons.newspaper_rounded;
      case 'movies':
        return Icons.movie_creation_rounded;
      case 'entertainment':
        return Icons.tv_rounded;
      case 'kids':
        return Icons.child_care_rounded;
      case 'documentary':
        return Icons.public_rounded;
      default:
        return Icons.live_tv_rounded;
    }
  }
}

// =========================================================================
// IN-APP NATIVE LIVE CHANNEL VIDEO PLAYER SCREEN
// =========================================================================
class LiveChannelPlayerScreen extends StatefulWidget {
  final LiveChannel channel;
  final List<LiveChannel> allChannels;
  final int initialIndex;

  const LiveChannelPlayerScreen({
    super.key,
    required this.channel,
    this.allChannels = const [],
    this.initialIndex = 0,
  });

  @override
  State<LiveChannelPlayerScreen> createState() => _LiveChannelPlayerScreenState();
}

class _LiveChannelPlayerScreenState extends State<LiveChannelPlayerScreen> {
  late LiveChannel _currentChannel;
  late int _currentIndex;
  VideoPlayerController? _videoPlayerController;
  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  double _volume = 1.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _currentIndex = widget.initialIndex >= 0 ? widget.initialIndex : 0;
    _initChannelStream();
  }

  Future<void> _initChannelStream() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _webViewController = null;

    final streamUrl = _currentChannel.playbackUrl;

    // 1. Direct native HLS stream playback
    if (_currentChannel.isDirectHls || !PlatformUtils.isWebViewSupported) {
      try {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _videoPlayerController = controller;

        await controller.initialize();
        await controller.play();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = false;
          });
          _startHideControlsTimer();
        }
      } catch (e) {
        debugPrint('Live TV stream init error: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = 'Stream buffer timed out. Press retry or select another channel.';
          });
        }
      }
    }
    // 2. Mobile web embed fallback (when supported)
    else {
      try {
        _webViewController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (url) {
                if (mounted) setState(() => _isLoading = false);
              },
              onWebResourceError: (error) {
                if (mounted) setState(() => _isLoading = false);
              },
            ),
          )
          ..loadRequest(Uri.parse(streamUrl));
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _switchChannel(int direction) {
    if (widget.allChannels.isEmpty) return;
    int nextIdx = _currentIndex + direction;
    if (nextIdx < 0) nextIdx = widget.allChannels.length - 1;
    if (nextIdx >= widget.allChannels.length) nextIdx = 0;

    setState(() {
      _currentIndex = nextIdx;
      _currentChannel = widget.allChannels[nextIdx];
    });
    _initChannelStream();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: TvScreenWrapper(
        onBack: () => Navigator.of(context).pop(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Native Video Player or WebView
              if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoPlayerController!.value.aspectRatio,
                    child: VideoPlayer(_videoPlayerController!),
                  ),
                )
              else if (_webViewController != null)
                WebViewWidget(controller: _webViewController!)
              else if (!_isLoading && _hasError)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 56, color: AppTheme.primaryRed),
                        const SizedBox(height: 14),
                        Text(
                          _currentChannel.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ?? 'Unable to connect to live broadcast stream.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                              onPressed: _initChannelStream,
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                              label: const Text('Retry Stream', style: TextStyle(color: Colors.white)),
                            ),
                            if (widget.allChannels.length > 1) ...[
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white38),
                                ),
                                onPressed: () => _switchChannel(1),
                                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                label: const Text('Next Channel', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // 2. Loading Spinner
              if (_isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.primaryRed),
                        const SizedBox(height: 16),
                        Text(
                          'Connecting to ${_currentChannel.name}…',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Player Controls Overlay (Top Bar & Bottom Controls)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Header Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryRed,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
                                      SizedBox(width: 4),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _currentChannel.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        _currentChannel.category,
                                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.allChannels.length > 1) ...[
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                                    tooltip: 'Previous Channel (D-Pad Up)',
                                    onPressed: () => _switchChannel(-1),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                                    tooltip: 'Next Channel (D-Pad Down)',
                                    onPressed: () => _switchChannel(1),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Center Play / Pause Indicator
                          if (_videoPlayerController != null)
                            Center(
                              child: IconButton(
                                iconSize: 56,
                                icon: Icon(
                                  _videoPlayerController!.value.isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                onPressed: () {
                                  if (_videoPlayerController!.value.isPlaying) {
                                    _videoPlayerController!.pause();
                                  } else {
                                    _videoPlayerController!.play();
                                  }
                                  setState(() {});
                                  _startHideControlsTimer();
                                },
                              ),
                            ),

                          // Bottom Controls Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                // Mute / Volume Button
                                IconButton(
                                  icon: Icon(
                                    _isMuted || _volume == 0
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isMuted = !_isMuted;
                                      _videoPlayerController?.setVolume(_isMuted ? 0.0 : _volume);
                                    });
                                  },
                                ),
                                SizedBox(
                                  width: 100,
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      activeTrackColor: AppTheme.primaryRed,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: Colors.white,
                                    ),
                                    child: Slider(
                                      value: _isMuted ? 0.0 : _volume,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: (val) {
                                        setState(() {
                                          _volume = val;
                                          _isMuted = val == 0.0;
                                          _videoPlayerController?.setVolume(val);
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '1080p FHD • Voidflix Edge Stream',
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
