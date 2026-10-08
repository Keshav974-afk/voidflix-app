import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../models/server_config.dart';
import '../providers/history_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/profile_avatar.dart';
import 'profile_gate_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showSetPinDialog(BuildContext context, UserProfile profile) {
    final pinController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceVariant,
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
                    : 'Set a 4-digit PIN to lock ${profile.name}.',
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
                  fillColor: AppTheme.cardColor,
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

  void _showResetConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Reset All App Data?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'This will permanently erase all created profiles, your watch progress, and saved lists. The app will return to the initial profile setup.',
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
              if (context.mounted) {
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
    final profileProvider = context.watch<ProfileProvider>();
    final activeProfile = profileProvider.activeProfile;
    final currentServer = ServerConfig.servers[profileProvider.selectedServerIndex];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Profiles & Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit, size: 16, color: AppTheme.primaryRed),
            label: const Text('Manage', style: TextStyle(color: AppTheme.primaryRed, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileGateScreen(canPop: true)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Profiles row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Who\'s Watching?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileGateScreen(canPop: true)),
                  );
                },
                child: const Text(
                  'Switch / Edit',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: profileProvider.profiles.length,
              itemBuilder: (ctx, idx) {
                final p = profileProvider.profiles[idx];
                final isSelected = p.id == activeProfile.id;

                return GestureDetector(
                  onTap: () => profileProvider.setActiveProfile(p),
                  child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryRed : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ProfileAvatarTile.fromProfile(
                                profile: p,
                                size: 60,
                              ),
                            ),
                            if (p.isLocked)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_rounded, color: Colors.amber, size: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p.name,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 16),

          // Profile Lock / PIN Management
          Text(
            'Security (${activeProfile.name})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListTile(
              leading: Icon(
                activeProfile.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: activeProfile.isLocked ? Colors.amber : Colors.white70,
              ),
              title: Text(
                activeProfile.isLocked ? 'Profile PIN Lock: Active' : 'Profile PIN Lock: Off',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                activeProfile.isLocked
                    ? '4-digit PIN required when switching to ${activeProfile.name}'
                    : 'Add a 4-digit PIN to prevent others from entering your profile',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: activeProfile.isLocked ? const Color(0xFF2E2E3A) : AppTheme.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showSetPinDialog(context, activeProfile),
                child: Text(activeProfile.isLocked ? 'Change / Off' : 'Set PIN', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Streaming Server Preference
          const Text(
            'Playback & Server',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.cloud_done, color: AppTheme.primaryRed),
              title: const Text('Default Video Server', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                '${currentServer.name} - ${currentServer.description}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () {
                _showServerSelectionSheet(context, profileProvider);
              },
            ),
          ),
          const SizedBox(height: 24),

          // Storage & Cache
          Text(
            'Data & Storage (${activeProfile.name})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.white70),
                  title: const Text('Clear Watch History', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Clear continue watching and played titles for this profile', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () async {
                    await context.read<HistoryProvider>().clearHistory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Watch history cleared for ${activeProfile.name}.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: AppTheme.border),
                ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined, color: Colors.white70),
                  title: const Text('Clear My List', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Remove all saved movies & shows from this profile\'s list', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () async {
                    await context.read<WatchlistProvider>().clearWatchlist();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('My List cleared for ${activeProfile.name}.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: AppTheme.border),
                ListTile(
                  leading: const Icon(Icons.cleaning_services, color: Colors.white70),
                  title: const Text('Clear Media & Image Cache', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Free up memory and reload thumbnails', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    PaintingBinding.instance.imageCache.clear();
                    PaintingBinding.instance.imageCache.clearLiveImages();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image and media cache cleared.')),
                    );
                  },
                ),
                const Divider(height: 1, color: AppTheme.border),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                  title: const Text('Reset All App Data', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Delete all profiles and stored information', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () => _showResetConfirmDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Notification Settings
          const Text(
            'Notifications & Updates',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, child) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SwitchListTile(
                  activeThumbColor: AppTheme.primaryRed,
                  activeTrackColor: AppTheme.primaryRed.withValues(alpha: 0.3),
                  secondary: const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryRed),
                  title: const Text('New Releases & Updates', style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Get notified about new movies, trending series, and updates from voidflix.org',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  value: notifProvider.notificationsEnabled,
                  onChanged: (val) => notifProvider.setNotificationsEnabled(val),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // App Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'VOIDFLIX',
                      style: TextStyle(
                        color: AppTheme.primaryRed,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'v1.0.0',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Official mobile and desktop client for voidflix.org. Stream movies, TV series, anime, drama, and live IPTV channels with ultra-low buffering.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 10),
                Text(
                  'Web: https://voidflix.org',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showServerSelectionSheet(BuildContext context, ProfileProvider profileProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Choose Default Server',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const Divider(color: AppTheme.border),
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
        );
      },
    );
  }
}
