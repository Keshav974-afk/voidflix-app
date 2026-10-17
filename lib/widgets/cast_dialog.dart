import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/cast_service.dart';

class CastDialog extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? posterUrl;
  final Duration currentPosition;
  final Map<String, String>? headers;

  const CastDialog({
    super.key,
    required this.videoUrl,
    required this.title,
    this.posterUrl,
    this.currentPosition = Duration.zero,
    this.headers,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
    String? posterUrl,
    Duration currentPosition = Duration.zero,
    Map<String, String>? headers,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CastDialog(
        videoUrl: videoUrl,
        title: title,
        posterUrl: posterUrl,
        currentPosition: currentPosition,
        headers: headers,
      ),
    );
  }

  @override
  State<CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<CastDialog> {
  final CastService _castService = CastService();
  bool _isConnecting = false;
  String? _connectingDeviceName;

  @override
  void initState() {
    super.initState();
    _castService.addListener(_onCastServiceUpdate);
    if (!_castService.isCasting) {
      _castService.startDiscovery();
    }
  }

  @override
  void dispose() {
    _castService.removeListener(_onCastServiceUpdate);
    super.dispose();
  }

  void _onCastServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _handleDeviceSelected(CastDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingDeviceName = device.friendlyName;
    });

    final success = await _castService.castMedia(
      device: device,
      videoUrl: widget.videoUrl,
      title: widget.title,
      posterUrl: widget.posterUrl,
      startPosition: widget.currentPosition,
    );

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectingDeviceName = null;
      });
      if (success) {
        // Stay in modal to allow immediate playback control!
      }
    }
  }

  Future<void> _handleExternalPlayer() async {
    await CastService.launchExternalPlayer(
      videoUrl: widget.videoUrl,
      title: widget.title,
      headers: widget.headers,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCasting = _castService.isCasting;
    final device = _castService.connectedDevice;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCasting ? const Color(0xFF00D2FF).withValues(alpha: 0.15) : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                      color: isCasting ? const Color(0xFF00D2FF) : Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCasting ? 'Casting to ${device?.friendlyName ?? "TV"}' : 'Cast to TV',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isCasting
                              ? 'Active Playback Control'
                              : 'Select your Smart TV or Streaming Device',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCasting)
                    IconButton(
                      icon: _castService.isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryRed),
                            )
                          : const Icon(Icons.refresh_rounded, color: Colors.white70),
                      tooltip: 'Scan for Devices',
                      onPressed: _castService.isScanning
                          ? null
                          : () => _castService.startDiscovery(),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF262638), height: 1),

            // Body: Active Cast Remote vs Device List
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: isCasting ? _buildActiveRemoteControl() : _buildDeviceList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIVE REMOTE CONTROL VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActiveRemoteControl() {
    final status = _castService.status;
    final isPlaying = status == CastPlaybackStatus.playing;
    final pos = _castService.position;
    final dur = _castService.duration;
    final maxSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 100.0;
    final curSec = pos.inSeconds.toDouble().clamp(0.0, maxSec);

    return Column(
      children: [
        // Media Overview Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E2E42)),
          ),
          child: Row(
            children: [
              if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: widget.posterUrl!,
                    width: 50,
                    height: 72,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black26),
                    errorWidget: (_, __, ___) => Container(color: Colors.black26),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'CASTING LIVE',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _castService.currentTitle.isNotEmpty
                          ? _castService.currentTitle
                          : widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _castService.connectedDevice?.friendlyName ?? 'Smart TV',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Scrubbing Bar
        Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.primaryRed,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppTheme.primaryRed,
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: curSec,
                min: 0.0,
                max: maxSec,
                onChanged: (val) {
                  _castService.seekTo(Duration(seconds: val.toInt()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(pos), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(dur > Duration.zero ? _formatDuration(dur) : '--:--',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Remote Controls: -10s, Play/Pause, +10s
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 38,
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
              onPressed: () => _castService.seekRelative(-10),
            ),
            const SizedBox(width: 24),
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.primaryRed,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 42,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () => _castService.togglePlayPause(),
              ),
            ),
            const SizedBox(width: 24),
            IconButton(
              iconSize: 38,
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
              onPressed: () => _castService.seekRelative(10),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Volume Slider (RenderingControl)
        if (_castService.connectedDevice?.renderingControlUrl != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 20),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF00D2FF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF00D2FF),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    ),
                    child: Slider(
                      value: _castService.volume.toDouble(),
                      min: 0.0,
                      max: 100.0,
                      onChanged: (val) => _castService.setVolume(val.toInt()),
                    ),
                  ),
                ),
                const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 20),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Disconnect & Switch TV Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF38384E)),
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.tv_rounded, size: 18),
                label: const Text('Switch TV'),
                onPressed: () {
                  _castService.startDiscovery();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF281418),
                  foregroundColor: const Color(0xFFFF5252),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF5A1A22)),
                  ),
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Stop Cast'),
                onPressed: () async {
                  await _castService.disconnect();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DEVICE DISCOVERY & PICKER VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDeviceList() {
    final devices = _castService.devices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. External Player Caster Card (100% Guaranteed Compatibility)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E2838), Color(0xFF161E2C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2B3A52)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _handleExternalPlayer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0071eb).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.open_in_new_rounded,
                        color: Color(0xFF3897FF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Cast via External App',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'UNIVERSAL',
                                style: TextStyle(
                                  color: Color(0xFF00D2FF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Web Video Caster, BubbleUPnP, VLC, MX Player',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Section Title: Available Smart TVs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DISCOVERED SMART TVS & RENDERERS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (_castService.isScanning)
                const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Scanning Wi-Fi...',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Device Items
        if (devices.isNotEmpty)
          ...devices.map((dev) {
            final isCurrentConnecting = _isConnecting && _connectingDeviceName == dev.friendlyName;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF262638)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tv_rounded, color: Colors.white, size: 22),
                ),
                title: Text(
                  dev.friendlyName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${dev.manufacturer} • ${dev.host}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: isCurrentConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryRed),
                      )
                    : const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF00D2FF), size: 24),
                onTap: isCurrentConnecting ? null : () => _handleDeviceSelected(dev),
              ),
            );
          })
        else if (!_castService.isScanning)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181824),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF242436)),
            ),
            child: Column(
              children: [
                const Icon(Icons.tv_off_rounded, color: Colors.white38, size: 36),
                const SizedBox(height: 8),
                const Text(
                  'No Smart TVs Found on this Wi-Fi',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ensure your TV (Samsung, LG, Sony, Roku, Fire TV) is on the same Wi-Fi network with DLNA/Media Sharing enabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38384E)),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Rescan Network'),
                  onPressed: () => _castService.startDiscovery(),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryRed),
                SizedBox(height: 12),
                Text(
                  'Searching for Smart TVs & Media Renderers...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
