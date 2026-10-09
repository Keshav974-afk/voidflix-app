import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/theme_constants.dart';
import '../core/network/api_service.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../services/avatar_service.dart';
import '../screens/choose_icon_screen.dart';
import '../screens/profile_gate_screen.dart';
import 'profile_avatar.dart';

/// Authentic Netflix "Choose your profile" bottom modal matching Screenshot 1.
///
/// Features:
/// 1. Top cinematic poster backdrop with dark vignette fade.
/// 2. "Choose your profile" title.
/// 3. Horizontal row of rounded square profile cards with official Netflix PFPs.
/// 4. Side-by-side [ + Add ] and [ Edit ] action tiles below.
/// 5. Add Profile flow uses official Netflix PFPs with full 976-avatar catalog access.
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
      Navigator.of(context).pop();
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
          backgroundColor: const Color(0xFF1E1E26),
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

  void _showAddProfileModal(BuildContext context) {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    String selectedAvatarUrl = AvatarService.defaultFeatured.first.url;
    bool isKids = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF191920),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add Profile',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.of(bottomCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Centered Selected Official Netflix Avatar (Tappable to pick from 976 avatars)
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final tempProfile = UserProfile(
                            id: 'temp',
                            name: nameController.text.isEmpty ? 'New' : nameController.text,
                            avatar: selectedAvatarUrl,
                          );
                          final newUrl = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder: (_) => ChooseIconScreen(profile: tempProfile),
                            ),
                          );
                          if (newUrl != null && newUrl.isNotEmpty) {
                            setModalState(() {
                              selectedAvatarUrl = newUrl;
                            });
                          }
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: CachedNetworkImage(
                                  imageUrl: selectedAvatarUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(color: const Color(0xFF282828)),
                                  errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.edit, color: Colors.black, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.grid_view_rounded, size: 15, color: Colors.white70),
                        label: const Text('Choose Official Avatar (976 Available)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        onPressed: () async {
                          final tempProfile = UserProfile(
                            id: 'temp',
                            name: nameController.text.isEmpty ? 'New' : nameController.text,
                            avatar: selectedAvatarUrl,
                          );
                          final newUrl = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder: (_) => ChooseIconScreen(profile: tempProfile),
                            ),
                          );
                          if (newUrl != null && newUrl.isNotEmpty) {
                            setModalState(() {
                              selectedAvatarUrl = newUrl;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Horizontal scroll of Featured Official Avatars
                    const Text(
                      'Featured Official PFPs',
                      style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: AvatarService.defaultFeatured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (ctx, idx) {
                          final av = AvatarService.defaultFeatured[idx];
                          final isSelected = av.url == selectedAvatarUrl;
                          return GestureDetector(
                            onTap: () => setModalState(() => selectedAvatarUrl = av.url),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: av.url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => Container(color: const Color(0xFF282828)),
                                  errorWidget: (_, _, _) => const Icon(Icons.person, color: Colors.white),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Profile Name',
                        labelStyle: const TextStyle(color: Colors.white60),
                        hintText: 'e.g. Alex, Family',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: AppTheme.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 14),
                    // Kids Mode Toggle
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kids Profile?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Filter content suitable for kids only', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      activeTrackColor: AppTheme.primaryRed,
                      activeThumbColor: Colors.white,
                      value: isKids,
                      onChanged: (val) => setModalState(() => isKids = val),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, letterSpacing: 4),
                      decoration: InputDecoration(
                        labelText: 'Profile Lock PIN (Optional)',
                        labelStyle: const TextStyle(color: Colors.white60),
                        hintText: '4-digit PIN',
                        hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 1),
                        counterText: '',
                        filled: true,
                        fillColor: AppTheme.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          context.read<ProfileProvider>().addProfile(
                                name: name,
                                colorIndex: 0,
                                isKids: isKids,
                                pin: pinController.text.trim().isEmpty ? null : pinController.text.trim(),
                                avatar: selectedAvatarUrl,
                              );
                          Navigator.of(bottomCtx).pop();
                        },
                        child: const Text('Save Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final mediaProvider = context.watch<MediaProvider>();
    final profiles = profileProvider.profiles;

    final first = mediaProvider.trending.firstOrNull;
    final String? backdropUrl = first != null
        ? ApiService.getImageUrl(first.backdropPath ?? first.posterPath, size: 'w780')
        : null;

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Top Cinematic Poster Backdrop (Screenshot 1)
          if (backdropUrl != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: screenHeight * 0.45,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: backdropUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
                  ),
                  // Dark Vignette gradient fading down to sheet background
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.black.withValues(alpha: 0.70),
                          const Color(0xFF141416),
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 2. Sheet Handle Bar
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // 3. Main Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),

                // "Choose your profile" Title (Screenshot 1)
                const Text(
                  'Choose your profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 22),

                // Profiles Horizontal Row (Screenshot 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: profiles.map((p) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: GestureDetector(
                          onTap: () => _onProfileTapped(context, p),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ProfileAvatarTile.fromProfile(
                                profile: p,
                                size: 84,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 84,
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 32),

                // Action Buttons Row: [ + Add ] and [ Edit ] (Screenshot 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // [ + ] Add Profile Tile
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _showAddProfileModal(context);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C32),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12, width: 1),
                            ),
                            child: const Center(
                              child: Icon(Icons.add, color: Colors.white, size: 28),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),

                    // [ Edit ] Edit Profiles Tile
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileGateScreen(canPop: true, initialEditMode: true),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C32),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12, width: 1),
                            ),
                            child: const Center(
                              child: Icon(Icons.edit_outlined, color: Colors.white, size: 24),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Edit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
