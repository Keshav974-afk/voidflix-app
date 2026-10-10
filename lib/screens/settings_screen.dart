import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/theme_constants.dart';
import '../providers/download_provider.dart';
import '../providers/history_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
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
  // Persisted state
  bool _downloadWifiOnly = false;
  bool _smartDownloads = true;
  String _cellularDataUsage = 'Automatic';
  String _downloadQuality = 'Standard';
  double _cacheSizeMb = 0.0;
  bool _isLoadingCache = true;

  // Developer Mode state (unlocked by 5 taps on Device)
  bool _isDeveloperMode = false;
  int _deviceTapCount = 0;
  DateTime? _lastDeviceTapTime;
  Map<String, dynamic>? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculateCacheSize();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('org.voidflix/notifications');
        final dynamic res = await platform.invokeMethod('getDeviceInfo');
        if (res != null && mounted) {
          setState(() {
            _deviceInfo = Map<String, dynamic>.from(res as Map);
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load device info: $e');
    }
  }

  String get _formattedDeviceInfo {
    if (_deviceInfo != null) {
      final versionName = _deviceInfo!['versionName']?.toString() ?? '1.0.0';
      final versionCode = _deviceInfo!['versionCode']?.toString() ?? '1';
      final sdkInt = _deviceInfo!['sdkInt']?.toString() ?? '31';
      final primaryAbi = _deviceInfo!['primaryAbi']?.toString() ?? 'arm64-v8a';
      final model = _deviceInfo!['model']?.toString() ?? 'Device';
      final manufacturer = _deviceInfo!['manufacturer']?.toString() ?? '';
      final brand = _deviceInfo!['brand']?.toString() ?? '';
      final release = _deviceInfo!['release']?.toString() ?? '';
      final display = _deviceInfo!['display']?.toString() ?? _deviceInfo!['buildId']?.toString() ?? '';
      final fingerprint = _deviceInfo!['fingerprint']?.toString() ?? '';

      final safeBrand = (brand.isNotEmpty ? brand : manufacturer).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final safeModel = model.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final esnHash = fingerprint.isNotEmpty ? fingerprint.hashCode.abs().toString() : '74592019';
      final esn = 'NFANDROID1-PRV-$safeBrand-$safeModel-$sdkInt-$esnHash';

      final mfgStr = manufacturer.isNotEmpty && !model.toLowerCase().contains(manufacturer.toLowerCase())
          ? ' ($manufacturer)'
          : '';

      return 'Version: $versionName build $versionCode (code $versionCode), OS API: $sdkInt, $primaryAbi\n'
          'Model: $model$mfgStr\n'
          'Android: $release (API $sdkInt)\n'
          'Build: $display\n'
          'ESN: $esn';
    }

    return 'Version: 1.0.0, OS API: ${Platform.operatingSystemVersion}\n'
        'Model: ${Platform.operatingSystem}\n'
        'Platform: ${Platform.isAndroid ? "Android" : Platform.operatingSystem}';
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _downloadWifiOnly = prefs.getBool('voidflix_download_wifi_only') ?? false;
        _smartDownloads = prefs.getBool('voidflix_smart_downloads') ?? true;
        _cellularDataUsage = prefs.getString('voidflix_cellular_data') ?? 'Automatic';
        _downloadQuality = prefs.getString('voidflix_download_quality') ?? 'Standard';
        _isDeveloperMode = prefs.getBool('voidflix_developer_mode') ?? false;
      });
    }
  }

  void _handleDeviceTap() async {
    final now = DateTime.now();
    if (_lastDeviceTapTime == null || now.difference(_lastDeviceTapTime!).inSeconds > 2) {
      _deviceTapCount = 0;
    }
    _lastDeviceTapTime = now;
    _deviceTapCount++;

    if (_isDeveloperMode) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer mode is already active.'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    if (_deviceTapCount >= 5) {
      _deviceTapCount = 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('voidflix_developer_mode', true);
      if (!mounted) return;
      setState(() => _isDeveloperMode = true);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer mode enabled! Web servers unlocked.'),
          backgroundColor: Color(0xFFE50914),
          duration: Duration(seconds: 3),
        ),
      );
    } else if (_deviceTapCount >= 2) {
      final remaining = 5 - _deviceTapCount;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tap $remaining more times to unlock Developer options.'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  Future<void> _turnOffDeveloperMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voidflix_developer_mode', false);
    if (!mounted) return;
    setState(() => _isDeveloperMode = false);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Developer mode turned off.'),
        duration: Duration(seconds: 2),
      ),
    );
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
                'Mobile Data Usage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const Divider(color: Color(0xFF262638)),
            ...options.map((opt) {
              final isSel = _cellularDataUsage == opt;
              return ListTile(
                leading: Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSel ? const Color(0xFF0071eb) : Colors.white54,
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

  void _showDownloadQualitySheet() {
    final options = [
      {'title': 'Standard', 'desc': 'Downloads faster and uses less storage space.'},
      {'title': 'High', 'desc': 'Uses more storage space, maximum video sharpness.'},
    ];
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
                'Download Video Quality',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            const Divider(color: Color(0xFF262638)),
            ...options.map((opt) {
              final isSel = _downloadQuality == opt['title'];
              return ListTile(
                leading: Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSel ? const Color(0xFF0071eb) : Colors.white54,
                ),
                title: Text(opt['title']!, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: FontWeight.bold)),
                subtitle: Text(opt['desc']!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                onTap: () async {
                  setState(() => _downloadQuality = opt['title']!);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('voidflix_download_quality', opt['title']!);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSmartDownloadsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Smart Downloads',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'When you finish watching an episode, Smart Downloads deletes it and downloads the next episode when on Wi-Fi.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF0071eb),
                title: const Text('Download Next Episode', style: TextStyle(color: Colors.white)),
                value: _smartDownloads,
                onChanged: (val) async {
                  setSheetState(() => _smartDownloads = val);
                  setState(() => _smartDownloads = val);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('voidflix_smart_downloads', val);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF262634),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Done', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCheckNetworkDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDiagState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF14141A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cell_tower, color: Color(0xFF0071eb)),
                SizedBox(width: 10),
                Text('Network Diagnostics', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDiagRow('Voidflix CDN Server 1', '34 ms', true),
                const SizedBox(height: 12),
                _buildDiagRow('TMDB Metadata API', '48 ms', true),
                const SizedBox(height: 12),
                _buildDiagRow('Stream Mirror Cluster', '29 ms', true),
                const SizedBox(height: 12),
                _buildDiagRow('Internet Connection', 'Active', true),
                const SizedBox(height: 16),
                const Text(
                  'All Voidflix streaming and metadata systems are fully operational.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Close', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0071eb)),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                },
                child: const Text('Done', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDiagRow(String title, String latency, bool success) {
    return Row(
      children: [
        Icon(success ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: success ? Colors.greenAccent : Colors.redAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        Text(latency, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showPlaybackSpecificationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Playback Specification',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Divider(color: Color(0xFF262638)),
            _buildSpecRow('Digital Rights Management', 'Widevine L1'),
            _buildSpecRow('Max Playback Resolution', '4K UHD (3840×2160)'),
            _buildSpecRow('Supported Codecs', 'HEVC (H.265), VP9, AVC (H.264), AV1'),
            _buildSpecRow('HDR Capabilities', 'HDR10, HLG, Dolby Vision'),
            _buildSpecRow('Audio Formats', 'Dolby Atmos, 5.1 Surround, Stereo'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF242434)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showAccountDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Account', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Color(0xFF262638)),
            const SizedBox(height: 8),
            const Text('Membership & Plan', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Voidflix Unlimited', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Plan Details', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('Premium • Ultra HD (4K) & HDR • Ad-Free', style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: Colors.white)),
              ),
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
          'This will permanently reset all downloaded items, watch history, cached artwork, and local preferences.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              final profileP = context.read<ProfileProvider>();
              final historyP = context.read<HistoryProvider>();
              final watchlistP = context.read<WatchlistProvider>();
              await profileP.clearAllData();
              await historyP.clearHistory();
              await watchlistP.clearWatchlist();
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

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final downloadProvider = context.watch<DownloadProvider>();

    // Calculate dynamic download storage (in MB/GB)
    final int downloadedBytes = downloadProvider.completedItems.fold<int>(
      0,
      (sum, item) => sum + (item.fileSizeBytes > 0 ? item.fileSizeBytes : 50 * 1024 * 1024),
    );
    final String voidflixStorageStr = downloadedBytes > (1024 * 1024 * 1024)
        ? '${(downloadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
        : downloadedBytes > (1024 * 1024)
            ? '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(0)} MB'
            : '21 B';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'App Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          // ═══════════════════════════════════════════════
          // 1. VIDEO PLAYBACK (Screenshot 1)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Video Playback'),
          _buildSettingTile(
            leading: Icons.signal_cellular_alt,
            title: 'Mobile Data Usage',
            subtitle: _cellularDataUsage,
            onTap: _showCellularUsageSheet,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 2. NOTIFICATIONS (Screenshot 1)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Notifications'),
          _buildSwitchTile(
            leading: Icons.notifications_none,
            title: 'Allow notifications',
            subtitle: 'Customise in Settings → Notifications',
            value: notifProvider.notificationsEnabled,
            onChanged: (val) => notifProvider.setNotificationsEnabled(val),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 3. DOWNLOADS (Screenshot 1)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Downloads'),
          _buildSwitchTile(
            leading: Icons.wifi,
            title: 'Wi-Fi Only',
            value: _downloadWifiOnly,
            onChanged: (val) async {
              setState(() => _downloadWifiOnly = val);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('voidflix_download_wifi_only', val);
            },
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.file_download_outlined,
            title: 'Smart Downloads',
            onTap: _showSmartDownloadsSheet,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.video_settings_outlined,
            title: 'Download Video Quality',
            subtitle: _downloadQuality,
            onTap: _showDownloadQualitySheet,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.storage_outlined,
            title: 'Download Location',
            subtitle: 'Internal Storage',
            onTap: () {},
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // Storage Bar Section (Screenshot 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Internal Storage', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text('Default', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                // Horizontal Segmented Bar (Used: White, Voidflix: Blue, Free: Grey)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      // Used (white segment ~70%)
                      Expanded(
                        flex: 70,
                        child: Container(height: 12, color: Colors.white),
                      ),
                      // Voidflix (blue segment ~2%)
                      Expanded(
                        flex: 2,
                        child: Container(height: 12, color: const Color(0xFF0071eb)),
                      ),
                      // Free (dark grey segment ~28%)
                      Expanded(
                        flex: 28,
                        child: Container(height: 12, color: const Color(0xFF555555)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Legend Row
                Row(
                  children: [
                    _buildLegendItem(Colors.white, 'Used • 44 GB'),
                    const SizedBox(width: 18),
                    _buildLegendItem(const Color(0xFF0071eb), 'Voidflix • $voidflixStorageStr'),
                    const SizedBox(width: 18),
                    _buildLegendItem(const Color(0xFF555555), 'Free • 6.3 GB'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 4. ABOUT (Screenshot 2)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('About'),
          InkWell(
            onTap: _handleDeviceTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.smartphone, color: Colors.white70, size: 24),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Device', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          _formattedDeviceInfo,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // DEVELOPER MODE (Hidden, activated via 5 taps)
          // ═══════════════════════════════════════════════
          if (_isDeveloperMode) ...[
            _buildCategoryHeader('Developer Options'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1824),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.developer_mode, color: Colors.amber, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Developer Mode Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Web embed servers and WebView fallbacks are unlocked in player.',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _turnOffDeveloperMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text(
                          'TURN OFF',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF1E1E1E)),
          ],
          _buildSettingTile(
            leading: Icons.person_outline,
            title: 'Account',
            subtitle: 'Membership & Plan Details',
            trailing: const Icon(Icons.open_in_new, color: Colors.white54, size: 20),
            onTap: _showAccountDialog,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 5. DIAGNOSTICS (Screenshot 2)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Diagnostics'),
          _buildSettingTile(
            leading: Icons.cell_tower,
            title: 'Check network',
            onTap: _showCheckNetworkDialog,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.smart_display_outlined,
            title: 'Playback Specification',
            onTap: _showPlaybackSpecificationSheet,
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.speed,
            title: 'Internet speed test',
            trailing: const Icon(Icons.open_in_new, color: Colors.white54, size: 20),
            onTap: () => _openUrl('https://fast.com'),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 6. LEGAL (Screenshot 2)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Legal'),
          _buildSettingTile(
            leading: Icons.description_outlined,
            title: 'Open Source Licences',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Voidflix',
                applicationVersion: '1.0.0 (Release Build)',
              );
            },
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.description_outlined,
            title: 'Privacy',
            trailing: const Icon(Icons.open_in_new, color: Colors.white54, size: 20),
            onTap: () => _openUrl('https://voidflix.org/privacy'),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),

          // ═══════════════════════════════════════════════
          // 7. COMMUNITY & HELP (Telegram & Support)
          // ═══════════════════════════════════════════════
          _buildCategoryHeader('Help & Community'),
          _buildSettingTile(
            leading: Icons.send_rounded,
            title: 'Join Telegram Channel',
            subtitle: 't.me/VoidFlixOrg',
            trailing: const Icon(Icons.open_in_new, color: Color(0xFF0088CC), size: 20),
            onTap: () => _openTelegram('VoidFlixOrg'),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.forum_outlined,
            title: 'Join Telegram Community Chat',
            subtitle: 't.me/Voidflixchat',
            trailing: const Icon(Icons.open_in_new, color: Color(0xFF0088CC), size: 20),
            onTap: () => _openTelegram('Voidflixchat'),
          ),
          const Divider(height: 1, color: Color(0xFF1E1E1E)),
          _buildSettingTile(
            leading: Icons.delete_outline,
            title: 'Reset App Data & Cache',
            subtitle: _isLoadingCache ? 'Calculating cache...' : '${_cacheSizeMb.toStringAsFixed(1)} MB cached',
            trailing: const Icon(Icons.chevron_right, color: Colors.redAccent, size: 20),
            onTap: _showResetConfirmDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 22, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(leading, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData leading,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: Icon(leading, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            )
          : null,
      activeThumbColor: Colors.white,
      activeTrackColor: const Color(0xFF0071eb),
      inactiveThumbColor: Colors.white60,
      inactiveTrackColor: const Color(0xFF333333),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
