import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/services/voidcast_service.dart';

class VoidCastRemoteSheet extends StatefulWidget {
  const VoidCastRemoteSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoidCastRemoteSheet(),
    );
  }

  @override
  State<VoidCastRemoteSheet> createState() => _VoidCastRemoteSheetState();
}

class _VoidCastRemoteSheetState extends State<VoidCastRemoteSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isConnecting = false;
  String? _errorMessage;

  static const Color netflixRed = Color(0xFFE50914);
  static const Color netflixDark = Color(0xFF0F0F12);
  static const Color netflixCard = Color(0xFF18181F);
  static const Color netflixBorder = Color(0xFF27272A);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final cast = VoidCastService();
    if (cast.roomCode != null && cast.roomCode!.length == 6) {
      _codeController.text = cast.roomCode!;
    }

    // Automatically scan local Wi-Fi for TVs
    if (!cast.isConnected) {
      cast.startLocalDiscovery();
    }
  }

  @override
  void dispose() {
    VoidCastService().stopLocalDiscovery();
    _tabController.dispose();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleConnectWithCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit TV code');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final success = await VoidCastService().connectToTv(code);

    if (mounted) {
      setState(() {
        _isConnecting = false;
        if (!success) {
          _errorMessage = 'Could not find TV. Make sure Voidflix is open on your TV.';
        }
      });
    }
  }

  Future<void> _handleConnectLocalTv(DiscoveredTv tv) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final success = await VoidCastService().connectToLocalTv(tv);

    if (mounted) {
      setState(() {
        _isConnecting = false;
        if (!success) {
          _errorMessage = 'Could not connect directly to ${tv.name}.';
        }
      });
    }
  }

  String _formatDuration(double seconds) {
    final s = seconds.toInt();
    final m = (s ~/ 60);
    final h = (m ~/ 60);
    final remSec = s % 60;
    final remMin = m % 60;
    if (h > 0) {
      return '$h:${remMin.toString().padLeft(2, '0')}:${remSec.toString().padLeft(2, '0')}';
    }
    return '$remMin:${remSec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Consumer<VoidCastService>(
      builder: (context, cast, _) {
        final isConnected = cast.isConnected;
        final tvState = cast.tvState;
        final isPlaying = tvState['isPlaying'] == true;
        final title = tvState['title']?.toString() ?? '';
        final poster = tvState['poster']?.toString() ?? '';
        final currentTime = (tvState['currentTime'] as num?)?.toDouble() ?? 0.0;
        final duration = (tvState['duration'] as num?)?.toDouble() ?? 0.0;
        final volume = (tvState['volume'] as num?)?.toDouble() ?? 1.0;
        final discoveredTvs = cast.discoveredTvs;

        return Container(
          decoration: const BoxDecoration(
            color: netflixDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: netflixBorder, width: 1),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black87, blurRadius: 30, spreadRadius: 6),
            ],
          ),
          padding: EdgeInsets.only(bottom: keyboardHeight > 0 ? keyboardHeight : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? netflixRed.withValues(alpha: 0.15)
                            : Colors.white10,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isConnected ? netflixRed.withValues(alpha: 0.4) : Colors.transparent,
                        ),
                      ),
                      child: Icon(
                        isConnected ? Icons.cast_connected_rounded : Icons.cast_rounded,
                        color: isConnected ? netflixRed : Colors.white70,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected ? cast.connectedTvName : 'Connect to TV (VoidCast)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: isConnected ? const Color(0xFF00E676) : Colors.white38,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Text(
                                isConnected
                                    ? (cast.isLocalConnection ? 'Direct Local Wi-Fi' : 'Linked via Code (${cast.roomCode})')
                                    : 'Wi-Fi Direct & Wireless Remote',
                                style: TextStyle(
                                  color: isConnected ? const Color(0xFF00E676) : Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isConnected)
                      TextButton(
                        onPressed: () {
                          cast.disconnect();
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                        child: const Text(
                          'Disconnect',
                          style: TextStyle(
                            color: netflixRed,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
              ),
              const Divider(color: netflixBorder, height: 16),

              // Body: Not connected vs Connected
              if (!isConnected)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. NEARBY TVS ON WI-FI (LOCAL NETWORK SIGNALS)
                      Row(
                        children: [
                          const Icon(Icons.wifi_tethering_rounded, color: netflixRed, size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'NEARBY TVS ON WI-FI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          if (cast.isScanningLocal)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: netflixRed),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (discoveredTvs.isNotEmpty) ...[
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: discoveredTvs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            final tv = discoveredTvs[idx];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: netflixCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: netflixBorder),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.tv_rounded, color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tv.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.bolt_rounded, color: Colors.greenAccent, size: 12),
                                            const SizedBox(width: 2),
                                            Text(
                                              'Local Wi-Fi (${tv.ip})',
                                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: _isConnecting ? null : () => _handleConnectLocalTv(tv),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: netflixRed,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      elevation: 0,
                                    ),
                                    child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: netflixCard.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: netflixBorder),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.wifi_rounded, color: Colors.white38, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Scanning Wi-Fi... Make sure Voidflix is running on your TV connected to the same Wi-Fi.',
                                  style: TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 2. OR LINK WITH TV CODE
                      const Text(
                        'OR LINK WITH TV CODE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Container(
                        decoration: BoxDecoration(
                          color: netflixCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _errorMessage != null
                                ? Colors.redAccent.withValues(alpha: 0.8)
                                : netflixBorder,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.dialpad_rounded, color: netflixRed, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '000000',
                                  hintStyle: TextStyle(color: Colors.white24, letterSpacing: 4),
                                  border: InputBorder.none,
                                  counterText: '',
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _isConnecting ? null : _handleConnectWithCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: netflixRed,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: _isConnecting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                )
              else ...[
                // Tabs: Now Playing & Remote Control D-Pad
                TabBar(
                  controller: _tabController,
                  indicatorColor: netflixRed,
                  indicatorWeight: 3,
                  labelColor: netflixRed,
                  unselectedLabelColor: Colors.white60,
                  tabs: const [
                    Tab(icon: Icon(Icons.play_circle_outline, size: 20), text: 'Now Playing'),
                    Tab(icon: Icon(Icons.gamepad_rounded, size: 20), text: 'TV Remote Control'),
                  ],
                ),

                SizedBox(
                  height: 380,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: Now Playing Controls
                      _buildNowPlayingTab(cast, isPlaying, title, poster, currentTime, duration, volume),

                      // TAB 2: TV Remote D-Pad
                      _buildDpadTab(cast),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNowPlayingTab(
    VoidCastService cast,
    bool isPlaying,
    String title,
    String poster,
    double currentTime,
    double duration,
    double volume,
  ) {
    if (title.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off_rounded, size: 48, color: Colors.white24),
              const SizedBox(height: 12),
              const Text(
                'TV is on Home Screen',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Browse movies on your phone and tap "Play on TV", or use the TV Remote Control tab to navigate.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _tabController.animateTo(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: netflixRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.gamepad_rounded, size: 18),
                label: const Text('Open Remote D-Pad', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          // Media Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: netflixCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: netflixBorder),
            ),
            child: Row(
              children: [
                if (poster.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: poster.startsWith('http') ? poster : 'https://image.tmdb.org/t/p/w185$poster',
                      width: 48,
                      height: 72,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(width: 48, height: 72, color: Colors.white10),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PLAYING ON TV',
                        style: TextStyle(color: netflixRed, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDuration(currentTime)} / ${_formatDuration(duration)}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Seekbar
          if (duration > 0) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: netflixRed,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: currentTime.clamp(0.0, duration),
                max: duration,
                onChanged: (val) => cast.seekTv(val),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(currentTime), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Playback Control Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 28),
                onPressed: () => cast.skipTv(-10),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: cast.togglePlayPauseTv,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: netflixRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x66E50914), blurRadius: 16, spreadRadius: 2),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 28),
                onPressed: () => cast.skipTv(10),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Volume & Exit Row
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: netflixRed,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: volume,
                    onChanged: (val) => cast.setVolume(val),
                  ),
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 18),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.white60, size: 22),
                tooltip: 'Exit Player on TV',
                onPressed: cast.exitPlayerOnTv,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDpadTab(VoidCastService cast) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          children: [
            // Netflix Obsidian D-Pad Controller
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Circle Background
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: netflixCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: netflixBorder),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 16),
                      ],
                    ),
                  ),

                  // UP Button
                  Positioned(
                    top: 8,
                    child: _buildDpadButton(
                      icon: Icons.keyboard_arrow_up_rounded,
                      onTap: () => cast.sendDpadKey('up'),
                    ),
                  ),

                  // DOWN Button
                  Positioned(
                    bottom: 8,
                    child: _buildDpadButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      onTap: () => cast.sendDpadKey('down'),
                    ),
                  ),

                  // LEFT Button
                  Positioned(
                    left: 8,
                    child: _buildDpadButton(
                      icon: Icons.keyboard_arrow_left_rounded,
                      onTap: () => cast.sendDpadKey('left'),
                    ),
                  ),

                  // RIGHT Button
                  Positioned(
                    right: 8,
                    child: _buildDpadButton(
                      icon: Icons.keyboard_arrow_right_rounded,
                      onTap: () => cast.sendDpadKey('right'),
                    ),
                  ),

                  // CENTER OK BUTTON (Signature Netflix Red)
                  GestureDetector(
                    onTap: () => cast.sendDpadKey('select'),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: netflixRed,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x66E50914), blurRadius: 12, spreadRadius: 1),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'OK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Navigation Auxiliary Buttons: Back, Search Keyboard, Home
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAuxButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: () => cast.sendDpadKey('back'),
                ),
                _buildAuxButton(
                  icon: Icons.search_rounded,
                  label: 'Search TV',
                  onTap: () => _showSearchInputDialog(cast),
                ),
                _buildAuxButton(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => cast.sendDpadKey('home'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDpadButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildAuxButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: netflixCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: netflixBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: netflixRed, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showSearchInputDialog(VoidCastService cast) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: netflixDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Type on TV', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search title (e.g. Genius 2018)...',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: netflixRed)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: netflixRed, width: 2)),
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              cast.sendSearchText(val.trim());
              Navigator.of(dialogCtx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (_searchController.text.trim().isNotEmpty) {
                cast.sendSearchText(_searchController.text.trim());
                Navigator.of(dialogCtx).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: netflixRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send to TV'),
          ),
        ],
      ),
    );
  }
}
