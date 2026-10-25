import '../providers/download_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/theme_constants.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_service.dart';
import '../core/services/tv_mode_service.dart';
import '../models/media_item.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/tv_back_button.dart';
import '../widgets/tv_focusable.dart';
import '../services/avatar_service.dart';
import 'choose_icon_screen.dart';
import 'edit_profile_screen.dart';
import 'main_navigation_screen.dart';

class ProfileGateScreen extends StatefulWidget {
  final bool canPop;
  final bool initialEditMode;

  const ProfileGateScreen({
    super.key,
    this.canPop = false,
    this.initialEditMode = false,
  });

  @override
  State<ProfileGateScreen> createState() => _ProfileGateScreenState();
}

class _ProfileGateScreenState extends State<ProfileGateScreen> {
  late bool _isManaging;
  List<MediaItem> _trendingPosters = [];
  String? _featuredLogoPath;
  String? _featuredSubtitle;

  @override
  void initState() {
    super.initState();
    _isManaging = widget.initialEditMode;
    _fetchTrendingPosters();
  }

  Future<void> _fetchTrendingPosters() async {
    try {
      final items = await ApiService().getTrending();
      if (mounted) {
        setState(() {
          _trendingPosters = items.where((m) => m.posterPath != null).take(18).toList();
        });
        if (_trendingPosters.isNotEmpty) {
          _fetchFeaturedLogo(_trendingPosters.first);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchFeaturedLogo(MediaItem item) async {
    try {
      final detail = await ApiService().getDetails(item.mediaType, item.id);
      if (mounted) {
        String subtitle;
        if (detail.tagline != null && detail.tagline!.trim().isNotEmpty) {
          subtitle = detail.tagline!.trim();
        } else if (item.mediaType == 'tv') {
          final count = detail.seasons.length;
          subtitle = count > 1 ? 'Watch all $count seasons' : (count == 1 ? 'Watch Season 1' : 'Watch series now');
        } else {
          subtitle = 'Watch movie now';
        }

        setState(() {
          _featuredLogoPath = detail.logoPath;
          _featuredSubtitle = subtitle;
        });
      }
    } catch (_) {}
  }

  void _onProfileTapped(UserProfile profile) {
    if (profile.pin != null && profile.pin!.isNotEmpty) {
      _showPinDialog(profile, isEditing: _isManaging);
      return;
    }

    if (_isManaging) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
      );
      return;
    }

    _selectProfileAndProceed(profile);
  }

  void _selectProfileAndProceed(UserProfile profile) {
    final provider = context.read<ProfileProvider>();
    provider.setActiveProfile(profile);
    context.read<DownloadProvider>().setActiveProfileId(profile.id);

    context.read<MediaProvider>().fetchPersonalizedForProfile(profile, force: true);

    if (widget.canPop && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  void _showPinDialog(UserProfile profile, {bool isEditing = false}) {
    final pinController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void handleUnlock() {
              if (pinController.text == profile.pin) {
                Navigator.of(dialogCtx).pop();
                if (isEditing) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
                  );
                } else {
                  _selectProfileAndProceed(profile);
                }
              } else {
                setDialogState(() {
                  errorText = 'Incorrect PIN. Try again.';
                  pinController.clear();
                });
              }
            }

            return Dialog(
              backgroundColor: AppTheme.surfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_rounded, color: AppTheme.primaryRed, size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Profile Locked',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 4-digit PIN for ${profile.name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.white60),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppTheme.cardColor,
                        errorText: errorText,
                        hintText: '••••',
                        hintStyle: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 16,
                          color: Colors.white24,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.primaryRed, width: 2),
                        ),
                      ),
                      onChanged: (val) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                        if (val.length == 4) {
                          handleUnlock();
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryRed,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: handleUnlock,
                            child: const Text('Unlock', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _showForgotPinDeleteDialog(profile, dialogCtx);
                      },
                      child: const Text(
                        'Forgot PIN? Delete Profile',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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

  void _showForgotPinDeleteDialog(UserProfile profile, BuildContext pinDialogCtx) {
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text('Delete Profile?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Because this profile is locked with a PIN and you do not know the PIN, deleting the profile is the only option. All data, watch history, and watchlist for "${profile.name}" will be permanently removed. Are you sure?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            onPressed: () async {
              Navigator.of(confirmCtx).pop();
              Navigator.of(pinDialogCtx).pop();
              await context.read<ProfileProvider>().deleteProfile(profile.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF1F1F1F),
                    content: Text('Profile "${profile.name}" deleted.', style: const TextStyle(color: Colors.white)),
                  ),
                );
              }
            },
            child: const Text('Delete Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddProfileModal() {
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
                                  placeholder: (_, __) => Container(color: const Color(0xFF282828)),
                                  errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white),
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
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                                  placeholder: (_, __) => Container(color: const Color(0xFF282828)),
                                  errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white),
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
    final profiles = profileProvider.profiles;
    final featuredItem = _trendingPosters.isNotEmpty ? _trendingPosters.first : null;
    final heroImageUrl = featuredItem != null
        ? ApiService.getImageUrl(featuredItem.backdropPath ?? featuredItem.posterPath, size: 'original')
        : '';

    final isDesktopOrTv = MediaQuery.of(context).size.width >= 600 ||
        TvModeService().isTvMode ||
        (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS));

    if (isDesktopOrTv) {
      return _buildDesktopTvScreen(context, profiles, featuredItem, heroImageUrl);
    }

    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      body: Stack(
        children: [
          // Top ~52%: Hero Featured Show Artwork (Screenshot 3)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.53,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (heroImageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: heroImageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (c, u) => Container(color: const Color(0xFF1B1B22)),
                    errorWidget: (c, u, e) => Container(color: const Color(0xFF1B1B22)),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF2A1B18), Color(0xFF120E0D)],
                      ),
                    ),
                  ),

                // Cinematic vignette gradients
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 0.8, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                          const Color(0xFF0F0F14),
                        ],
                      ),
                    ),
                  ),
                ),

                // Top left back button if canPop
                if (widget.canPop && Navigator.of(context).canPop())
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 14,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                  ),

                // Featured Announcement & Title Badge at bottom of hero artwork (Screenshot 1)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Stylized Logo (TMDB) with fallback to clean Title
                      if (_featuredLogoPath != null && _featuredLogoPath!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ApiConstants.getImageUrl(_featuredLogoPath, size: 'w500'),
                          height: 64,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          errorWidget: (c, u, e) => Text(
                            (featuredItem?.title ?? 'VOIDFLIX').toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.bebasNeue(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                        )
                      else
                        Text(
                          (featuredItem?.title ?? 'VOIDFLIX').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.bebasNeue(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),

                      // Dynamic subtitle or tagline
                      Text(
                        _featuredSubtitle ?? (featuredItem?.mediaType == 'tv' ? 'Watch series now' : 'Watch movie now'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom ~49%: Curved "Elige tu perfil" section (Screenshot 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: screenHeight * 0.49,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141217),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Title: "Choose your profile"
                      Text(
                        'Choose your profile',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3-Column Grid of Profile tiles + Edit
                      Expanded(
                        child: Center(
                          child: profiles.isEmpty
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_add_alt_1, color: AppTheme.primaryRed, size: 52),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Who\'s watching?',
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Create your profile to start streaming',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white60, fontSize: 13),
                                    ),
                                    const SizedBox(height: 18),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryRed,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.add, color: Colors.white),
                                      label: const Text(
                                        'Create Profile',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: _showAddProfileModal,
                                    ),
                                  ],
                                )
                              : ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 360),
                                  child: GridView.count(
                                    shrinkWrap: true,
                                    physics: const BouncingScrollPhysics(),
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 0.82,
                                    children: [
                                      // All User profiles (up to 5)
                                      ...profiles.take(5).map((p) => _buildProfileTile(p)),

                                      // Optional Add tile if user has fewer than 5 profiles and not managing
                                      if (profiles.length < 5 && !_isManaging)
                                        _buildActionTile(
                                          icon: Icons.add_rounded,
                                          label: 'Add',
                                          onTap: _showAddProfileModal,
                                        ),

                                      // Edit tile with pencil icon
                                      _buildActionTile(
                                        icon: _isManaging ? Icons.check_rounded : Icons.edit_outlined,
                                        label: _isManaging ? 'Done' : 'Edit',
                                        isHighlight: _isManaging,
                                        onTap: () {
                                          setState(() => _isManaging = !_isManaging);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
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
    );
  }

  Widget _buildDesktopTvScreen(
    BuildContext context,
    List<UserProfile> profiles,
    MediaItem? featuredItem,
    String heroImageUrl,
  ) {
    return TvScreenWrapper(
      onBack: (widget.canPop && Navigator.of(context).canPop())
          ? () => Navigator.of(context).pop()
          : null,
      child: Scaffold(
        backgroundColor: const Color(0xFF111114),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Dimmed featured backdrop
            if (heroImageUrl.isNotEmpty)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.28,
                  child: CachedNetworkImage(
                    imageUrl: heroImageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    placeholder: (_, __) => Container(color: const Color(0xFF111114)),
                    errorWidget: (_, __, ___) => Container(color: const Color(0xFF111114)),
                  ),
                ),
              ),

            // Vignette gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      const Color(0xFF0F0F12).withValues(alpha: 0.95),
                      const Color(0xFF0A0A0D),
                    ],
                  ),
                ),
              ),
            ),

            // Top-left: VOIDFLIX logo + optional back button
            Positioned(
              top: 36,
              left: 48,
              child: Row(
                children: [
                  if (widget.canPop && Navigator.of(context).canPop()) ...[
                    TvBackButton(
                      showBackground: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                  ],
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'VOID',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryRed,
                            letterSpacing: 2.5,
                          ),
                        ),
                        TextSpan(
                          text: 'FLIX',
                          style: GoogleFonts.bebasNeue(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Center: "Who's watching?" + Profiles Row + Manage Profiles button
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Who's watching?",
                        style: GoogleFonts.inter(
                          fontSize: 44,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 42),

                      // Profile Cards Wrap
                      Wrap(
                        spacing: 32,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          ...profiles.map((profile) {
                            return TvFocusable(
                              scaleFactor: 1.08,
                              glowColor: AppTheme.primaryRed,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: () => _onProfileTapped(profile),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ProfileAvatarTile.fromProfile(
                                        profile: profile,
                                        size: 130,
                                        showEditBadge: _isManaging,
                                      ),
                                      if (profile.isLocked && !_isManaging)
                                        Positioned(
                                          right: 6,
                                          bottom: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF141217),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.lock_rounded, color: Colors.amber, size: 20),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    profile.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          // Add Profile Card (up to 5 profiles)
                          if (profiles.length < 5)
                            TvFocusable(
                              scaleFactor: 1.08,
                              glowColor: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: _showAddProfileModal,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white30, width: 1.5),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.add_rounded, size: 54, color: Colors.white54),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Add Profile',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      color: Colors.white54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 52),

                      // [ MANAGE PROFILES ] Outlined Pill Button
                      TvFocusable(
                        scaleFactor: 1.05,
                        glowColor: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        onPressed: () => setState(() => _isManaging = !_isManaging),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            color: _isManaging ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _isManaging ? Colors.white : Colors.white54,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            _isManaging ? 'DONE' : 'MANAGE PROFILES',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isManaging ? Colors.black : Colors.white70,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom-left featured badge
            if (featuredItem != null)
              Positioned(
                left: 48,
                bottom: 32,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_featuredLogoPath != null && _featuredLogoPath!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: ApiConstants.getImageUrl(_featuredLogoPath, size: 'w500'),
                        height: 48,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorWidget: (c, u, e) => Text(
                          featuredItem.title.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      )
                    else
                      Text(
                        featuredItem.title.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Watch the Limited Series now',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(UserProfile profile) {
    return GestureDetector(
      onTap: () => _onProfileTapped(profile),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ProfileAvatarTile.fromProfile(
                profile: profile,
                size: 76,
              ),
              if (profile.isLocked && !_isManaging)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF141217),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.amber, size: 16),
                  ),
                ),
              if (_isManaging)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Icon(Icons.edit, color: Colors.white, size: 28),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isHighlight = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: isHighlight ? AppTheme.primaryRed : const Color(0xFF383842),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
