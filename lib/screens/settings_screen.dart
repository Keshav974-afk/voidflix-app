import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme_constants.dart';
import '../models/server_config.dart';
import '../providers/download_provider.dart';
import '../providers/history_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/profile_avatar.dart';
import 'downloads_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_gate_screen.dart';

enum SettingsSection { appSettings, account, help }

class SettingsScreen extends StatefulWidget {
  final SettingsSection initialSection;

  const SettingsScreen({
    super.key,
    this.initialSection = SettingsSection.appSettings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _websiteUrl = 'https://voidflix.org';

  // Persisted state
  bool _autoplayNext = true;
  bool _downloadWifiOnly = false;
  bool _smartDownloads = true;
  bool _notifNewReleases = true;
  bool _notifDownloads = true;
  String _cellularDataUsage = 'Automatic';
  double _cacheSizeMb = 0.0;
  bool _isLoadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculateCacheSize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoplayNext = prefs.getBool('voidflix_autoplay_next') ?? true;
        _downloadWifiOnly = prefs.getBool('voidflix_download_wifi_only') ?? false;
        _smartDownloads = prefs.getBool('voidflix_smart_downloads') ?? true;
        _notifNewReleases = prefs.getBool('voidflix_notif_new_releases') ?? true;
        _notifDownloads = prefs.getBool('voidflix_notif_downloads') ?? true;
        _cellularDataUsage = prefs.getString('voidflix_cellular_data') ?? 'Automatic';
      });
    }
  }

  Future<void> _calculateCacheSize() async {
    setState(() => _isLoadingCache = true);
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (tempDir.existsSync()) {
        tempDir.listSync(recursive: true, followLinks: false).forEach((entity) {
          if (entity is File) {
            try {
              totalBytes += entity.lengthSync();
            } catch (_) {}
          }
        });
      }
      if (mounted) {
        setState(() {
          _cacheSizeMb = totalBytes / (1024 * 1024);
          _isLoadingCache = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCache = false);
    }
  }

  Future<void> _clearCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync(recursive: true, followLinks: false).forEach((entity) {
          try {
            if (entity is File) entity.deleteSync();
          } catch (_) {}
        });
      }
    } catch (_) {}

    await _calculateCacheSize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cache cleared successfully.'),
          backgroundColor: AppTheme.surfaceVariant,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openTelegram(String username) async {
    final tgUri = Uri.parse('tg://resolve?domain=$username');
    final webUri = Uri.parse('https://t.me/$username');
    bool launched = false;
    try {
      launched = await launchUrl(tgUri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Telegram: https://t.me/$username')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!launched) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $url')),
      );
    }
  }

  void _showSetPinDialog(BuildContext context, UserProfile profile) {
    final pinController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF181824),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppTheme.primaryRed),
              const SizedBox(width: 10),
              Text(
                profile.isLocked ? 'Change / Remove PIN' : 'Lock Profile',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.isLocked
                    ? 'Enter a new 4-digit PIN for ${profile.name}, or leave empty to unlock.'
                    : 'Set a 4-digit PIN to restrict access to ${profile.name}.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 12, color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF222230),
                  errorText: errorText,
                  hintText: '••••',
                  hintStyle: const TextStyle(fontSize: 24, letterSpacing: 12, color: Colors.white24),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.primaryRed, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (profile.isLocked)
              TextButton(
                onPressed: () {
                  context.read<ProfileProvider>().unlockProfile(profile.id);
                  Navigator.of(dialogCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PIN removed from ${profile.name}.')),
                  );
                },
                child: const Text('Remove Lock', style: TextStyle(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final pin = pinController.text.trim();
                if (pin.length != 4 && pin.isNotEmpty) {
                  setDialogState(() => errorText = 'PIN must be exactly 4 digits');
                  return;
                }
                if (pin.isEmpty) {
                  context.read<ProfileProvider>().unlockProfile(profile.id);
                } else {
                  context.read<ProfileProvider>().lockProfile(profile.id, pin);
                }
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      pin.isEmpty ? 'Profile unlocked.' : 'Profile locked with 4-digit PIN.',
                    ),
                  ),
                );
              },
              child: const Text('Save PIN', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181824),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Reset All App Data?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'This will permanently delete all local profiles, downloads, watch history, and bookmarks. The app will return to the welcome screen.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              await context.read<ProfileProvider>().clearAllData();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const ProfileGateScreen(canPop: false)),
                  (route) => false,
                );
              }
            },
            child: const Text('Reset Everything', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showServerSelectionSheet(ProfileProvider profileProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Default Streaming Server',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const Divider(color: Color(0xFF262638)),
            Expanded(
              child: ListView.builder(
                itemCount: ServerConfig.servers.length,
                itemBuilder: (c, idx) {
                  final s = ServerConfig.servers[idx];
                  final isSel = idx == profileProvider.selectedServerIndex;
                  return ListTile(
                    leading: Icon(
                      isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSel ? AppTheme.primaryRed : Colors.white54,
                    ),
                    title: Text(
                      s.name,
                      style: TextStyle(
                        color: isSel ? Colors.white : Colors.white70,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      s.description,
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                    onTap: () {
                      profileProvider.setSelectedServer(idx);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCellularUsageSheet() {
    final options = ['Automatic', 'Wi-Fi Only', 'Save Data', 'Maximum Data'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Cellular Data Usage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const Divider(color: Color(0xFF262638)),
            ...options.map((opt) {
              final isSel = _cellularDataUsage == opt;
              return ListTile(
                leading: Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSel ? AppTheme.primaryRed : Colors.white54,
                ),
                title: Text(opt, style: TextStyle(color: isSel ? Colors.white : Colors.white70)),
                onTap: () async {
                  setState(() => _cellularDataUsage = opt);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('voidflix_cellular_data', opt);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final notifProvider = context.watch<NotificationProvider>();
    final downloadProvider = context.watch<DownloadProvider>();
    final activeProfile = profileProvider.activeProfile;
    final currentServer = ServerConfig.servers[profileProvider.selectedServerIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Settings & Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          // 1. Account & Profile Header Card
          _buildSectionHeader('ACCOUNT & PROFILES'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: ProfileAvatarTile.fromProfile(
                    profile: activeProfile,
                    size: 48,
                  ),
                  title: Text(
                    activeProfile.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text(
                    activeProfile.isKids ? 'Kids Profile' : 'Standard Profile',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(profile: activeProfile),
                        ),
                      );
                    },
                    child: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded, color: Colors.white70),
                  title: const Text('Switch / Manage Profiles', style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileGateScreen(canPop: true),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: Icon(
                    activeProfile.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: activeProfile.isLocked ? Colors.amber : Colors.white70,
                  ),
                  title: Text(
                    activeProfile.isLocked ? 'Profile PIN: Active' : 'Profile PIN: None',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    activeProfile.isLocked ? '4-digit lock enabled' : 'Protect this profile with a 4-digit PIN',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () => _showSetPinDialog(context, activeProfile),
                    child: Text(
                      activeProfile.isLocked ? 'Change / Off' : 'Set PIN',
                      style: const TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 2. Notifications Section (Full & Working!)
          _buildSectionHeader('NOTIFICATIONS'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryRed),
                  title: const Text('Push Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Allow notifications from Voidflix', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: notifProvider.notificationsEnabled,
                  onChanged: (val) => notifProvider.setNotificationsEnabled(val),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.movie_outlined, color: Colors.white70),
                  title: const Text('New Releases & Episodes', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Get alerted when new trending movies or TV episodes arrive', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  value: _notifNewReleases && notifProvider.notificationsEnabled,
                  onChanged: notifProvider.notificationsEnabled
                      ? (val) async {
                          setState(() => _notifNewReleases = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('voidflix_notif_new_releases', val);
                        }
                      : null,
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.download_done_rounded, color: Colors.white70),
                  title: const Text('Download Alerts', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Notify when offline downloads complete', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  value: _notifDownloads && notifProvider.notificationsEnabled,
                  onChanged: notifProvider.notificationsEnabled
                      ? (val) async {
                          setState(() => _notifDownloads = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('voidflix_notif_downloads', val);
                        }
                      : null,
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.inbox_outlined, color: Colors.white70),
                  title: const Text('Notification Inbox', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${notifProvider.notifications.length} updates (${notifProvider.unreadCount} unread)',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const FractionallySizedBox(
                        heightFactor: 0.75,
                        child: NotificationsSheet(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 3. Video Playback
          _buildSectionHeader('VIDEO PLAYBACK & STREAMING'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined, color: AppTheme.primaryRed),
                  title: const Text('Default Stream Server', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${currentServer.name} (${currentServer.description})',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => _showServerSelectionSheet(profileProvider),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.play_circle_outline_rounded, color: Colors.white70),
                  title: const Text('Autoplay Next Episode', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Play subsequent episodes automatically', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  value: _autoplayNext,
                  onChanged: (val) async {
                    setState(() => _autoplayNext = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('voidflix_autoplay_next', val);
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.network_check_rounded, color: Colors.white70),
                  title: const Text('Cellular Data Usage', style: TextStyle(color: Colors.white)),
                  subtitle: Text(_cellularDataUsage, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _showCellularUsageSheet,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 4. Downloads
          _buildSectionHeader('DOWNLOADS & OFFLINE'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.wifi_outlined, color: Colors.white70),
                  title: const Text('Wi-Fi Only', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Only download video files when connected to Wi-Fi', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  value: _downloadWifiOnly,
                  onChanged: (val) async {
                    setState(() => _downloadWifiOnly = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('voidflix_download_wifi_only', val);
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.35),
                  secondary: const Icon(Icons.auto_delete_outlined, color: Colors.white70),
                  title: const Text('Smart Downloads', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Automatically remove completed episodes after watching', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  value: _smartDownloads,
                  onChanged: (val) async {
                    setState(() => _smartDownloads = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('voidflix_smart_downloads', val);
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined, color: Colors.white70),
                  title: const Text('Manage Downloads', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${downloadProvider.completedItems.length} titles saved offline',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 5. Data & Storage
          _buildSectionHeader('DATA & STORAGE'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined, color: Colors.white70),
                  title: const Text('Clear Image & Media Cache', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _isLoadingCache ? 'Calculating...' : '${_cacheSizeMb.toStringAsFixed(1)} MB cached',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: _clearCache,
                    child: const Text('Clear', style: TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.history_rounded, color: Colors.white70),
                  title: const Text('Clear Watch History', style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () async {
                    await context.read<HistoryProvider>().clearHistory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Watch history cleared.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined, color: Colors.white70),
                  title: const Text('Clear My List', style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () async {
                    await context.read<WatchlistProvider>().clearWatchlist();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('My List cleared.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: Color(0xFF242434)),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                  title: const Text('Reset All App Data', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Delete profiles, settings and saved data', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: _showResetConfirmDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 6. Help, Community & Support (Requested by User)
          _buildSectionHeader('COMMUNITY & HELP'),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF242434)),
            ),
            child: Column(
              children: [
                // Telegram Channel
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0088CC),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  title: const Text(
                    'Join Telegram Channel',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    't.me/VoidFlixOrg — Instant releases & mirrors',
                    style: TextStyle(color: Color(0xFF29B6F6), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, color: Color(0xFF29B6F6), size: 18),
                  onTap: () => _openTelegram('VoidFlixOrg'),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),

                // Telegram Discussion Group
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0088CC).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0088CC)),
                    ),
                    child: const Center(
                      child: Icon(Icons.forum_outlined, color: Color(0xFF29B6F6), size: 18),
                    ),
                  ),
                  title: const Text(
                    'Join Telegram Community Chat',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    't.me/Voidflixchat — Movie requests & chat',
                    style: TextStyle(color: Color(0xFF29B6F6), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, color: Color(0xFF29B6F6), size: 18),
                  onTap: () => _openTelegram('Voidflixchat'),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),

                // Official Website
                ListTile(
                  leading: const Icon(Icons.language_rounded, color: Colors.white70),
                  title: const Text('Official Website', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('https://voidflix.org', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 18),
                  onTap: () => _openUrl(_websiteUrl),
                ),
                const Divider(height: 1, color: Color(0xFF242434)),

                // App Version & Check
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                  title: const Text('Voidflix App Version', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('v1.0.0 (Release Build) • Up to date', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('LATEST', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
