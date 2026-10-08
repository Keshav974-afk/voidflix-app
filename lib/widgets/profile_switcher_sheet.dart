import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/profile_provider.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/profile_gate_screen.dart';
import 'profile_avatar.dart';

class ProfileSwitcherSheet extends StatelessWidget {
  const ProfileSwitcherSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProfileSwitcherSheet(),
    );
  }

  void _onProfileTapped(BuildContext context, UserProfile profile) {
    final provider = context.read<ProfileProvider>();
    if (profile.id == provider.activeProfile.id) {
      // Open Edit Profile
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
      );
      return;
    }

    if (profile.pin != null && profile.pin!.isNotEmpty) {
      _showPinUnlockDialog(context, profile);
      return;
    }

    provider.setActiveProfile(profile);
    Navigator.of(context).pop();
  }

  void _showPinUnlockDialog(BuildContext context, UserProfile profile) {
    final pinCtl = TextEditingController();
    String? errorText;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Enter PIN for ${profile.name}', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: TextField(
            controller: pinCtl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              errorText: errorText,
              filled: true,
              fillColor: AppTheme.cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (val) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
              if (val.length == 4) {
                if (val == profile.pin) {
                  context.read<ProfileProvider>().setActiveProfile(profile);
                  Navigator.of(dialogCtx).pop();
                  Navigator.of(context).pop();
                } else {
                  setDialogState(() {
                    errorText = 'Incorrect PIN';
                    pinCtl.clear();
                  });
                }
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              onPressed: () {
                if (pinCtl.text == profile.pin) {
                  context.read<ProfileProvider>().setActiveProfile(profile);
                  Navigator.of(dialogCtx).pop();
                  Navigator.of(context).pop();
                } else {
                  setDialogState(() {
                    errorText = 'Incorrect PIN';
                    pinCtl.clear();
                  });
                }
              },
              child: const Text('Unlock', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final active = profileProvider.activeProfile;
    final otherProfiles = profileProvider.profiles.where((p) => p.id != active.id).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF14141A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sheet Handle Bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Header: Profile Title + Close Button (Screenshot 3)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Active Profile Big Card (Screenshot 3)
              GestureDetector(
                onTap: () => _onProfileTapped(context, active),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        ProfileAvatarTile.fromProfile(
                          profile: active,
                          size: 90,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.edit, size: 14, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      active.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Other Profiles Row + Add Button (Screenshot 3)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...otherProfiles.map((p) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: GestureDetector(
                        onTap: () => _onProfileTapped(context, p),
                        child: Column(
                          children: [
                            ProfileAvatarTile.fromProfile(
                              profile: p,
                              size: 58,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.name,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Add tile
                  if (profileProvider.profiles.length < 5)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileGateScreen(canPop: true),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: const Color(0xFF26262E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Add',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Manage Profiles Pill Button (Screenshot 3)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileGateScreen(canPop: true),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF24242C),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Manage Profiles',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Settings List (Screenshot 3: App Settings, Account, Help, Sign Out)
              _buildListRow(
                icon: Icons.settings_outlined,
                title: 'App Settings',
                onTap: () {},
              ),
              _buildListRow(
                icon: Icons.person_outline,
                title: 'Account',
                onTap: () {},
              ),
              _buildListRow(
                icon: Icons.help_outline,
                title: 'Help',
                onTap: () {},
              ),
              _buildListRow(
                icon: Icons.logout,
                title: 'Sign Out',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ProfileGateScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
        onTap: onTap,
      ),
    );
  }
}
