import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/cast_service.dart';
import '../core/services/voidcast_service.dart';
import 'voidcast_remote_sheet.dart';

class CastDialog extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? posterUrl;
  final Duration currentPosition;
  final Map<String, String>? headers;
  final String? tmdbId;
  final String? mediaType;
  final int season;
  final int episode;
  final String? audioLanguage;
  final int? audioIndex;
  final String? subtitleUrl;
  final String? subtitleLanguage;
  final String? subtitleLabel;
  final int? serverIndex;
  final int? qualityIndex;
  final VoidCallback? onVoidCastBeamed;

  const CastDialog({
    super.key,
    required this.videoUrl,
    required this.title,
    this.posterUrl,
    this.currentPosition = Duration.zero,
    this.headers,
    this.tmdbId,
    this.mediaType,
    this.season = 1,
    this.episode = 1,
    this.audioLanguage,
    this.audioIndex,
    this.subtitleUrl,
    this.subtitleLanguage,
    this.subtitleLabel,
    this.serverIndex,
    this.qualityIndex,
    this.onVoidCastBeamed,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
    String? posterUrl,
    Duration currentPosition = Duration.zero,
    Map<String, String>? headers,
    String? tmdbId,
    String? mediaType,
    int season = 1,
    int episode = 1,
    String? audioLanguage,
    int? audioIndex,
    String? subtitleUrl,
    String? subtitleLanguage,
    String? subtitleLabel,
    int? serverIndex,
    int? qualityIndex,
    VoidCallback? onVoidCastBeamed,
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
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        audioLanguage: audioLanguage,
        audioIndex: audioIndex,
        subtitleUrl: subtitleUrl,
        subtitleLanguage: subtitleLanguage,
        subtitleLabel: subtitleLabel,
        serverIndex: serverIndex,
        qualityIndex: qualityIndex,
        onVoidCastBeamed: onVoidCastBeamed,
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

    await _castService.castMedia(
      device: device,
      videoUrl: widget.videoUrl,
      title: widget.title,
      posterUrl: widget.posterUrl,
      startPosition: widget.currentPosition,
      headers: widget.headers,
    );

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _connectingDeviceName = null;
      });
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
        color: Color(0xFF191919),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Netflix clean drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header (Netflix: "Connect to a device")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
                    color: isCasting ? AppTheme.primaryRed : Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isCasting ? 'Connected to ${device?.friendlyName ?? "TV"}' : 'Connect to a device',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isCasting)
                    IconButton(
                      icon: _castService.isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            )
                          : const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Rescan',
                      onPressed: _castService.isScanning ? null : () => _castService.startDiscovery(),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2B2B2B), height: 1),

            // Content
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

  Widget _buildActiveRemoteControl() {
    final status = _castService.status;
    final isPlaying = status == CastPlaybackStatus.playing;
    final pos = _castService.position;
    final dur = _castService.duration;
    final maxSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 100.0;
    final curSec = pos.inSeconds.toDouble().clamp(0.0, maxSec);

    return Column(
      children: [
        // Media Overview Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: widget.posterUrl!,
                    width: 44,
                    height: 64,
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
                            color: Color(0xFF46D369),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'NOW CASTING',
                          style: TextStyle(
                            color: Color(0xFF46D369),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
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

        // Scrubber
        Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.primaryRed,
                inactiveTrackColor: Colors.white24,
                thumbColor: AppTheme.primaryRed,
                trackHeight: 3.0,
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

        // Controls: -10s, Play/Pause, +10s
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
              onPressed: () => _castService.seekRelative(-10),
            ),
            const SizedBox(width: 28),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 36,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                ),
                onPressed: () => _castService.togglePlayPause(),
              ),
            ),
            const SizedBox(width: 28),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
              onPressed: () => _castService.seekRelative(10),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Actions: Disconnect & Switch TV
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Switch Device', style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () => _castService.startDiscovery(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B1417),
                  foregroundColor: const Color(0xFFFF4D4D),
                  side: const BorderSide(color: Color(0xFF6B2228)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async => await _castService.disconnect(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoidCastSection() {
    final voidCast = VoidCastService();
    final isVoidCastConnected = voidCast.isConnected;
    final hasTmdbId = widget.tmdbId != null && widget.tmdbId!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isVoidCastConnected ? AppTheme.primaryRed.withValues(alpha: 0.6) : Colors.white12,
          width: isVoidCastConnected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isVoidCastConnected
                  ? AppTheme.primaryRed.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tv_rounded,
                  color: isVoidCastConnected ? AppTheme.primaryRed : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isVoidCastConnected ? 'VOIDCAST CONNECTED TV' : 'VOIDFLIX ANDROID TV',
                  style: TextStyle(
                    color: isVoidCastConnected ? AppTheme.primaryRed : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                if (isVoidCastConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LINKED',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: isVoidCastConnected
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  voidCast.connectedTvName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Resumes at ${_formatDuration(widget.currentPosition)} • Audio: ${widget.audioLanguage ?? "Default"} • Sub: ${widget.subtitleLabel ?? "Off"}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.cast_connected_rounded, size: 16),
                            label: const Text('Cast to TV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: () {
                              if (!hasTmdbId) return;
                              voidCast.playOnTv(
                                tmdbId: widget.tmdbId!,
                                type: widget.mediaType ?? 'movie',
                                title: widget.title,
                                poster: widget.posterUrl,
                                season: widget.season,
                                episode: widget.episode,
                                position: widget.currentPosition.inSeconds.toDouble(),
                                audioLanguage: widget.audioLanguage,
                                audioIndex: widget.audioIndex,
                                subtitleUrl: widget.subtitleUrl,
                                subtitleLanguage: widget.subtitleLanguage,
                                subtitleLabel: widget.subtitleLabel,
                                serverIndex: widget.serverIndex,
                                qualityIndex: widget.qualityIndex,
                              );
                              widget.onVoidCastBeamed?.call();
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF1E1E2C),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  content: Row(
                                    children: [
                                      const Icon(Icons.cast_connected_rounded, color: Color(0xFF00E676)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Beamed "${widget.title}" to ${voidCast.connectedTvName} at ${_formatDuration(widget.currentPosition)}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Watching on Android TV? Pair with your TV to cast movies with exact subtitles, audio & timestamp.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          VoidCastRemoteSheet.show(context);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pin_rounded, color: AppTheme.primaryRed, size: 16),
                              SizedBox(width: 6),
                              Text('Pair TV via 6-Digit Code / Wi-Fi', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    final devices = _castService.devices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVoidCastSection(),
        // Available Devices Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AVAILABLE DEVICES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
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
                    Text('Searching...', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
            ],
          ),
        ),

        // Device Items (Clean Netflix style)
        if (devices.isNotEmpty)
          ...devices.map((dev) {
            final isCurrentConnecting = _isConnecting && _connectingDeviceName == dev.friendlyName;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: const Icon(Icons.tv_rounded, color: Colors.white70, size: 24),
                title: Text(
                  dev.friendlyName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  dev.manufacturer.isNotEmpty ? dev.manufacturer : 'Smart TV',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: isCurrentConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryRed),
                      )
                    : const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                onTap: isCurrentConnecting ? null : () => _handleDeviceSelected(dev),
              ),
            );
          })
        else if (!_castService.isScanning)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(Icons.tv_off_rounded, color: Colors.white38, size: 36),
                const SizedBox(height: 10),
                const Text(
                  'No devices found',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Make sure your Smart TV or streaming device is on the same Wi-Fi network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                  label: const Text('Search again', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  onPressed: () => _castService.startDiscovery(),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            alignment: Alignment.center,
            child: const Column(
              children: [
                CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryRed),
                SizedBox(height: 12),
                Text(
                  'Searching for devices on Wi-Fi...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2B2B2B), height: 1),
        const SizedBox(height: 8),

        // External Player fallback (Clean & muted)
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: const Icon(Icons.open_in_new_rounded, color: Colors.white60, size: 20),
          title: const Text(
            'Play in external app',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: const Text(
            'VLC, BubbleUPnP, Web Video Caster',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          onTap: _handleExternalPlayer,
        ),
      ],
    );
  }
}
