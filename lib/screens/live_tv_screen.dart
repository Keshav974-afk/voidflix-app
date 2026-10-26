import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import '../core/utils/platform_utils.dart';
import '../models/live_channel.dart';
import '../models/sports_match.dart';
import '../core/services/sports_service.dart';
import '../core/services/sports_reminder_service.dart';
import '../providers/notification_provider.dart';
import 'package:provider/provider.dart';
import '../core/utils/embed_shield.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key});

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  static const List<String> sportsCategories = [
    "Cricket",
    "Football",
    "Basketball",
    "Motorsport",
    "All Sports",
    "24/7 Channels",
  ];

  String _selectedCategory = "Cricket";
  int _focusedChannelIndex = 0;
  final ScrollController _channelScrollController = ScrollController();

  List<SportsMatch> _matches = [];
  bool _isLoadingMatches = false;
  String? _matchesError;

  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _loadMatches(_selectedCategory);
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _selectedCategory != "24/7 Channels") {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _channelScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMatches(String category, {bool forceRefresh = false}) async {
    if (category == "24/7 Channels") return;
    if (_isLoadingMatches) return;
    setState(() {
      _isLoadingMatches = true;
      _matchesError = null;
    });

    final apiCat = category == "All Sports"
        ? "all"
        : category.toLowerCase().replaceAll(" ", "-");

    try {
      final matches = await SportsService().fetchMatches(
        category: apiCat,
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _matches = matches;
          _isLoadingMatches = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMatches = false;
          _matchesError = e.toString();
        });
      }
    }
  }

  Widget _buildTeamLogo(String url, String teamName, {double size = 42}) {
    final cleanName = teamName.trim();
    final monogram = cleanName.length >= 3
        ? cleanName.substring(0, 3).toUpperCase()
        : (cleanName.isNotEmpty ? cleanName.toUpperCase() : "TM");

    if (url.isEmpty || !url.startsWith("http")) {
      return _buildMonogramBadge(monogram, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildMonogramBadge(monogram, size: size),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: size * 0.35,
                height: size * 0.35,
                child: const CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white30,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMonogramBadge(String monogram, {double size = 42}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C2C3D), Color(0xFF14141E)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12, width: 1.2),
      ),
      child: Center(
        child: Text(
          monogram,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: (size * 0.28).clamp(9.0, 13.0),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  List<LiveChannel> get _sportsChannels {
    final list = <LiveChannel>[];
    for (final match in _matches) {
      if (match.streams.isEmpty) continue;
      final primaryStream = match.streams.firstWhere(
        (s) => s.isDirect && s.type == 'hls',
        orElse: () => match.streams.first,
      );
      list.add(LiveChannel(
        id: match.id,
        name: match.title,
        category: match.category,
        streamUrl: primaryStream.url,
        directStreamUrl: primaryStream.isDirect ? primaryStream.url : null,
        description: '${match.category} • ${match.formattedStatus} • ${match.streams.length} stream(s)',
        httpHeaders: primaryStream.headers,
      ));
    }
    return list;
  }

  List<LiveChannel> get _filteredChannels {
    if (_selectedCategory == "24/7 Channels") return LiveData.channels;
    return _sportsChannels;
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

  void _watchMatchStream(SportsMatch match, SportsStream s) {
    final matchChannels = match.streams.map((stream) {
      return LiveChannel(
        id: '${match.id}_${stream.id}',
        name: '${match.title} (${stream.label})',
        category: match.category,
        streamUrl: stream.url,
        directStreamUrl: stream.isDirect ? stream.url : null,
        description: '${match.category} • ${match.formattedStatus}',
        httpHeaders: stream.headers,
      );
    }).toList();

    final selectedChannel = matchChannels.firstWhere(
      (c) => c.id == '${match.id}_${s.id}',
      orElse: () => matchChannels.first,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveChannelPlayerScreen(
          channel: selectedChannel,
          allChannels: matchChannels,
          initialIndex: matchChannels.indexOf(selectedChannel),
        ),
      ),
    );
  }

  void _showStreamPickerModal(SportsMatch match) {
    if (match.streams.isEmpty) return;

    final hasStarted = match.hasStarted || match.isLive;

    // PRE-MATCH GATE: If the match has not started yet, do not attempt to play!
    // Show pre-match countdown studio so the user sees time left and playback unlocks at start time.
    if (!hasStarted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF14141B),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded, color: Colors.amber, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'PRE-MATCH COUNTDOWN',
                          style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Team Logos & Names
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildTeamLogo(match.homeTeamLogo, match.homeTeam, size: 54),
                            const SizedBox(height: 8),
                            Text(
                              match.homeTeam.isNotEmpty ? match.homeTeam : match.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232332),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text('VS', style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w900)),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            _buildTeamLogo(match.awayTeamLogo, match.awayTeam, size: 54),
                            const SizedBox(height: 8),
                            Text(
                              match.awayTeam.isNotEmpty ? match.awayTeam : 'Opponent',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  Text(
                    '${match.category} • Scheduled Kickoff',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.amber.withValues(alpha: 0.08)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'BROADCAST STARTS IN',
                          style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          match.formattedStatus.replaceFirst('Starts in ', ''),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Streams are locked until kickoff. Playback unlocks automatically once live coverage begins.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  StatefulBuilder(
                    builder: (modalCtx, setModalState) {
                      final isReminded = SportsReminderService().isReminded(match.id);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              final notif = Provider.of<NotificationProvider>(context, listen: false);
                              HapticFeedback.lightImpact();
                              await SportsReminderService().toggleReminder(
                                context: context,
                                match: match,
                                notifProvider: notif,
                              );
                              setModalState(() {});
                              if (mounted) setState(() {});
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isReminded ? const Color(0xFF2E2413) : const Color(0xFF1C1C26),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isReminded ? Colors.amber.withValues(alpha: 0.6) : Colors.white24,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isReminded ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                                    color: isReminded ? Colors.amber : Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isReminded ? 'Reminder Active • Alert at Kickoff' : 'Notify Me When Match Starts',
                                    style: TextStyle(
                                      color: isReminded ? Colors.amber : Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    if (match.streams.length == 1) {
      _watchMatchStream(match, match.streams.first);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildTeamLogo(match.homeTeamLogo, match.homeTeam, size: 36),
                    const SizedBox(width: 6),
                    _buildTeamLogo(match.awayTeamLogo, match.awayTeam, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${match.category} • Select Streaming Feed',
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${match.category} • ${match.formattedStatus}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SELECT SERVER / STREAM',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 8),
                ...match.streams.map((s) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: s.isDirect ? AppTheme.primaryRed.withValues(alpha: 0.2) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        s.isDirect ? Icons.hd_rounded : Icons.link_rounded,
                        color: s.isDirect ? AppTheme.primaryRed : Colors.white70,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      s.label,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      s.isDirect ? 'Direct High-Bitrate Native Feed' : 'Mirror Feed',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.play_arrow_rounded, color: Colors.white70),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _watchMatchStream(match, s);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
                              SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
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
                          'LIVE SPORTS & CHANNELS',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 28,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: _isLoadingMatches ? AppTheme.primaryRed : Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Refresh Fixtures',
                      onPressed: () => _loadMatches(_selectedCategory, forceRefresh: true),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Real-time tournaments, fixtures, and direct CDN broadcasts in 1080p.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
              itemCount: sportsCategories.length,
              itemBuilder: (context, index) {
                final cat = sportsCategories[index];
                final isSel = cat == _selectedCategory;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = cat);
                    if (cat != "24/7 Channels") {
                      _loadMatches(cat);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? Colors.white : const Color(0xFF1E1E28),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white12,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isSel ? Colors.black : Colors.white70,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Matches Grid or 24/7 Channels Grid
          if (_selectedCategory != "24/7 Channels") ...[
            if (_isLoadingMatches) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppTheme.primaryRed),
                      SizedBox(height: 12),
                      Text(
                        'Fetching live match fixtures & CDN manifests…',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_matches.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(_getCategoryIcon(_selectedCategory), size: 48, color: Colors.white38),
                      const SizedBox(height: 12),
                      Text(
                        _matchesError != null
                            ? 'Failed to load fixtures: $_matchesError'
                            : 'No $_selectedCategory matches broadcasting right now',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                        onPressed: () => _loadMatches(_selectedCategory, forceRefresh: true),
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                        label: const Text('Refresh Fixtures', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = (constraints.maxWidth / 320).floor().clamp(1, 4);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      childAspectRatio: 1.32,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _matches.length,
                    itemBuilder: (context, index) {
                      final match = _matches[index];
                      return GestureDetector(
                        onTap: () => _showStreamPickerModal(match),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF1B1B26),
                                match.isLive ? const Color(0xFF281418) : const Color(0xFF13131C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: match.isLive
                                  ? const Color(0xFFE50914).withValues(alpha: 0.6)
                                  : Colors.white12,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Top Row: Sport tag + Live/Timer Status + Silent Bell
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      match.category.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: match.isLive
                                          ? const Color(0xFFE50914)
                                          : (match.hasStarted ? Colors.white10 : Colors.amber.withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(4),
                                      border: (!match.isLive && !match.hasStarted)
                                          ? Border.all(color: Colors.amber.withValues(alpha: 0.35))
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (match.isLive) ...[
                                          const Icon(Icons.fiber_manual_record, color: Colors.white, size: 7),
                                          const SizedBox(width: 4),
                                        ] else if (!match.hasStarted) ...[
                                          const Icon(Icons.schedule_rounded, color: Colors.amber, size: 9),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          match.formattedStatus,
                                          style: TextStyle(
                                            color: match.isLive ? Colors.white : (match.hasStarted ? Colors.white70 : Colors.amber),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!match.hasStarted) ...[
                                    const SizedBox(width: 6),
                                    Builder(
                                      builder: (cardCtx) {
                                        final isReminded = SportsReminderService().isReminded(match.id);
                                        return GestureDetector(
                                          onTap: () async {
                                            final notif = Provider.of<NotificationProvider>(context, listen: false);
                                            HapticFeedback.lightImpact();
                                            await SportsReminderService().toggleReminder(
                                              context: context,
                                              match: match,
                                              notifProvider: notif,
                                            );
                                            if (mounted) setState(() {});
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: isReminded ? Colors.amber.withValues(alpha: 0.2) : Colors.white10,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isReminded ? Colors.amber.withValues(alpha: 0.6) : Colors.white12,
                                              ),
                                            ),
                                            child: Icon(
                                              isReminded ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                                              color: isReminded ? Colors.amber : Colors.white70,
                                              size: 13,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 6),

                              // CENTER HERO: Team Logos & Names
                              Row(
                                children: [
                                  // Home Team
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _buildTeamLogo(match.homeTeamLogo, match.homeTeam, size: 40),
                                        const SizedBox(height: 4),
                                        Text(
                                          match.homeTeam.isNotEmpty ? match.homeTeam : match.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // VS Divider
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      'VS',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),

                                  // Away Team
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _buildTeamLogo(match.awayTeamLogo, match.awayTeam, size: 40),
                                        const SizedBox(height: 4),
                                        Text(
                                          match.awayTeam.isNotEmpty ? match.awayTeam : 'Opponent',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              // Bottom Action Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${match.streams.length} Feed${match.streams.length == 1 ? '' : 's'}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (match.isLive || match.hasStarted) ? const Color(0xFFE50914) : Colors.amber.shade700,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (match.isLive || match.hasStarted)
                                              ? const Color(0xFFE50914).withValues(alpha: 0.4)
                                              : Colors.amber.withValues(alpha: 0.3),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (match.isLive || match.hasStarted) ? Icons.play_arrow_rounded : Icons.schedule_rounded,
                                          color: Colors.white,
                                          size: 13,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          (match.isLive || match.hasStarted) ? 'Watch Live' : 'Pre-Match',
                                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                                        ),
                                      ],
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
            ],
          ] else ...[
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
          ],
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'cricket':
      case 'cricket (live)':
        return Icons.sports_cricket_rounded;
      case 'football':
      case 'soccer':
        return Icons.sports_soccer_rounded;
      case 'basketball':
        return Icons.sports_basketball_rounded;
      case 'motorsport':
      case 'racing':
        return Icons.sports_motorsports_rounded;
      case 'all sports':
      case 'sports':
        return Icons.emoji_events_rounded;
      case '24/7 channels':
      case 'live tv':
        return Icons.live_tv_rounded;
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
  bool _isLandscape = true;
  bool _isDesktopWebStream = false;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _currentIndex = widget.initialIndex >= 0 ? widget.initialIndex : 0;

    // Default to fullscreen landscape and immersive sticky UI for match streams
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
    if (_currentChannel.isDirectHls) {
      try {
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          httpHeaders: _currentChannel.httpHeaders ?? const {},
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
    // 2. Mobile web embed & DASH fallback (Android / iOS / macOS with WebView)
    else if (PlatformUtils.isWebViewSupported) {
      try {
        var playUrl = streamUrl;
        // Direct resolution for golf stream wrapper to eliminate sandbox detection overlay
        if (playUrl.contains('embed.st/embed/golf/')) {
          final parts = playUrl.split('embed/golf/')[1].split('/');
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            playUrl = 'https://rockyembed.st/source/streamed1.php?hd=33&id=${parts[0]}&no=1';
          }
        }

        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setUserAgent(EmbedShield.userAgent)
          ..setBackgroundColor(Colors.black);

        EmbedShield.configureAndroid(controller);

        controller.setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              controller.runJavaScript(EmbedShield.antiPopupScript);
            },
            onPageFinished: (url) {
              if (mounted) setState(() => _isLoading = false);
              controller.runJavaScript(EmbedShield.antiPopupScript);
            },
            onWebResourceError: (error) {
              if (mounted) setState(() => _isLoading = false);
            },
            onNavigationRequest: (request) {
              if (EmbedShield.shouldBlockNavigation(request.url)) {
                debugPrint('[LiveTV EmbedShield] Silently absorbed redirect: ${request.url}');
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

        controller.loadRequest(Uri.parse(playUrl));
        _webViewController = controller;
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
    // 3. Desktop (Windows / Linux) DASH & Web Stream Studio
    else {
      setState(() {
        _isLoading = false;
        _hasError = false;
        _isDesktopWebStream = true;
      });
      _launchDesktopPlayer(streamUrl);
    }
  }

  Future<void> _launchDesktopPlayer(String streamUrl, {bool forceBrowser = false}) async {
    try {
      if (!forceBrowser && !kIsWeb && Platform.isWindows) {
        // Try Edge App Mode (Dedicated, borderless 1080p window)
        try {
          final res = await Process.run('cmd', ['/c', 'start', '""', 'msedge', '--app=$streamUrl']);
          if (res.exitCode == 0) return;
        } catch (_) {}

        // Try Chrome App Mode
        try {
          final res = await Process.run('cmd', ['/c', 'start', '""', 'chrome', '--app=$streamUrl']);
          if (res.exitCode == 0) return;
        } catch (_) {}
      }

      // Default browser launch via url_launcher
      final uri = Uri.parse(streamUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Desktop stream launch error: $e');
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

  Widget _buildDesktopStreamStudio() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            Color(0xFF1B1B28),
            Color(0xFF0E0E15),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Live Glowing Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'LIVE BROADCAST ACTIVE • 1080p 60FPS',
                        style: TextStyle(
                          color: AppTheme.primaryRed,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Match / Channel Title
                Text(
                  _currentChannel.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  _currentChannel.description ?? 'ClearKey DRM Hardware-Accelerated Broadcast',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 26),

                // Main Launch Button (Glow Effect)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 8,
                    shadowColor: AppTheme.primaryRed.withValues(alpha: 0.6),
                  ),
                  onPressed: () => _launchDesktopPlayer(_currentChannel.playbackUrl),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text(
                    'Launch 1080p Live Player Window',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(height: 12),

                // Secondary Browser Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _launchDesktopPlayer(_currentChannel.playbackUrl, forceBrowser: true),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('Open in Web Browser (voidflix.org/sports)'),
                ),

                const SizedBox(height: 24),

                // Helpful Info Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161622),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Windows Desktop uses hardware-accelerated Shaka ClearKey DRM. The stream opens in a dedicated frameless player window with full volume & fullscreen controls.',
                          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                // Feeds Switcher Row if multiple channels available
                if (widget.allChannels.length > 1) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'SWITCH AVAILABLE MATCH FEEDS',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: List.generate(widget.allChannels.length, (idx) {
                      final ch = widget.allChannels[idx];
                      final isCurrent = idx == _currentIndex;
                      return ChoiceChip(
                        label: Text(
                          ch.name,
                          style: TextStyle(
                            color: isCurrent ? Colors.white : Colors.white70,
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isCurrent,
                        selectedColor: AppTheme.primaryRed,
                        backgroundColor: const Color(0xFF1C1C2A),
                        side: BorderSide(
                          color: isCurrent ? AppTheme.primaryRed : Colors.white12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _currentIndex = idx;
                              _currentChannel = widget.allChannels[idx];
                            });
                            _initChannelStream();
                          }
                        },
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _videoPlayerController?.dispose();
    // Restore orientation and system chrome on exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
              else if (_isDesktopWebStream)
                _buildDesktopStreamStudio()
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
                                IconButton(
                                  icon: Icon(
                                    _isLandscape ? Icons.screen_lock_landscape_rounded : Icons.screen_lock_portrait_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                  tooltip: 'Rotate Screen',
                                  onPressed: _toggleOrientation,
                                ),
                                const SizedBox(width: 8),
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
