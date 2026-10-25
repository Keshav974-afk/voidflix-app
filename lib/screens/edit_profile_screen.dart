import '../core/utils/language_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';
import 'choose_icon_screen.dart';
import 'subtitle_appearance_screen.dart';
import '../widgets/tv_back_button.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late int _selectedColorIndex;
  late String _avatar;
  late bool _isKids;
  String? _pin;
  String _gameHandle = '';
  String _maturityRating = 'No restrictions';
  String _displayLanguage = 'English';
  String _preferredAudio = 'Original Audio';
  String _preferredSubtitle = 'Off / None';
  bool _autoplayNext = true;
  bool _autoplayPreviews = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _selectedColorIndex = widget.profile.colorIndex;
    _avatar = widget.profile.avatar;
    _isKids = widget.profile.isKids;
    _pin = widget.profile.pin;
    _loadExtraSettings();
  }

  Future<void> _loadExtraSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gameHandle = prefs.getString('profile_${widget.profile.id}_game_handle') ?? '';
      _maturityRating = prefs.getString('profile_${widget.profile.id}_maturity') ?? (_isKids ? 'Kids (TV-Y, TV-G)' : 'No restrictions');
      _displayLanguage = prefs.getString('profile_${widget.profile.id}_lang') ?? 'English';
      _preferredAudio = widget.profile.preferredAudioLang ?? 'Original Audio';
      _preferredSubtitle = widget.profile.preferredSubtitleLang ?? 'Off / None';
      _autoplayNext = prefs.getBool('profile_${widget.profile.id}_autoplay_next') ?? true;
      _autoplayPreviews = prefs.getBool('profile_${widget.profile.id}_autoplay_previews') ?? true;
    });
  }

  Future<void> _saveExtraSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_${widget.profile.id}_game_handle', _gameHandle);
    await prefs.setString('profile_${widget.profile.id}_maturity', _maturityRating);
    await prefs.setString('profile_${widget.profile.id}_lang', _displayLanguage);
    await prefs.setString('profile_${widget.profile.id}_preferred_audio', _preferredAudio);
    await prefs.setString('profile_${widget.profile.id}_preferred_sub', _preferredSubtitle);
    await prefs.setBool('profile_${widget.profile.id}_autoplay_next', _autoplayNext);
    await prefs.setBool('profile_${widget.profile.id}_autoplay_previews', _autoplayPreviews);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final profileProv = context.read<ProfileProvider>();
    profileProv.updateProfile(
      widget.profile.id,
      name: name,
      colorIndex: _selectedColorIndex,
      avatar: _avatar,
      isKids: _isKids,
      pin: _pin,
      preferredAudioLang: _preferredAudio,
      preferredSubtitleLang: _preferredSubtitle,
      preferredLanguages: [_preferredAudio, 'English'],
      clearPin: _pin == null || _pin!.isEmpty,
    );

    await _saveExtraSettings();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openChooseIcon() async {
    final selected = await Navigator.of(context).push<AvatarItem>(
      MaterialPageRoute(
        builder: (_) => ChooseIconScreen(profile: widget.profile),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        if (selected.colorIndex != null) {
          _selectedColorIndex = selected.colorIndex!;
          _avatar = selected.name;
        } else if (selected.imageUrl != null) {
          _avatar = selected.imageUrl!;
        }
      });
    }
  }

  void _showGameHandleDialog() {
    final ctl = TextEditingController(text: _gameHandle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: AppTheme.primaryRed),
            SizedBox(width: 10),
            Text('Game Handle', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your unique gaming nickname on Voidflix.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. ShadowHunter',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF14141E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () {
              setState(() => _gameHandle = ctl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMaturityDialog() {
    final ratings = [
      'No restrictions',
      'Teens (13+)',
      'Kids (7+)',
      'Little Kids (All Ages)',
      'Adults Only (18+)',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                'Viewing Restrictions',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(color: Colors.white12),
            ...ratings.map((r) {
              final isSel = _maturityRating == r;
              return ListTile(
                title: Text(r, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                trailing: isSel ? const Icon(Icons.check, color: AppTheme.primaryRed) : null,
                onTap: () {
                  setState(() {
                    _maturityRating = r;
                    _isKids = r.contains('Kids');
                  });
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showPinDialog() {
    if (_pin != null && _pin!.isNotEmpty) {
      _showVerifyCurrentPinDialog();
    } else {
      _showSetNewPinDialog();
    }
  }

  void _showVerifyCurrentPinDialog() {
    final verifyCtl = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white12),
          ),
          title: const Text('Verify Current PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter current 4-digit PIN for ${widget.profile.name} to modify or remove lock.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: verifyCtl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 10, color: Colors.white),
                decoration: InputDecoration(
                  hintText: '••••',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF222222),
                  errorText: errorText,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) {
                  if (errorText != null) setModalState(() => errorText = null);
                  if (val.length == 4) {
                    if (val == _pin) {
                      Navigator.of(dialogCtx).pop();
                      _showSetNewPinDialog(canRemove: true);
                    } else {
                      setModalState(() {
                        errorText = 'Incorrect PIN. Try again.';
                        verifyCtl.clear();
                      });
                    }
                  }
                },
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  _showForgotPinDeleteProfileDialog(dialogCtx);
                },
                child: const Text(
                  'Forgot PIN? Delete Profile',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              onPressed: () {
                if (verifyCtl.text == _pin) {
                  Navigator.of(ctx).pop();
                  _showSetNewPinDialog(canRemove: true);
                } else {
                  setModalState(() {
                    errorText = 'Incorrect PIN. Try again.';
                    verifyCtl.clear();
                  });
                }
              },
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSetNewPinDialog({bool canRemove = false}) {
    final pinCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(canRemove ? 'Update Profile PIN' : 'Set Profile Lock PIN', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a 4-digit PIN to secure this profile.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 10, color: Colors.white),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF222222),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          if (canRemove)
            TextButton(
              onPressed: () {
                setState(() => _pin = null);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF1F1F1F),
                    content: Text('PIN protection removed.', style: TextStyle(color: Colors.white)),
                  ),
                );
              },
              child: const Text('Remove PIN', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            onPressed: () {
              final text = pinCtl.text.trim();
              if (text.length == 4) {
                setState(() => _pin = text);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF1F1F1F),
                    content: Text('Profile PIN saved.', style: TextStyle(color: Colors.white)),
                  ),
                );
              }
            },
            child: const Text('Save PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showForgotPinDeleteProfileDialog(BuildContext parentDialogCtx) {
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
          'Because this profile is locked with a PIN and you do not know the PIN, deleting the profile is the only option. All data, watch history, and watchlist for "${widget.profile.name}" will be permanently removed. Are you sure?',
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
              Navigator.of(parentDialogCtx).pop();
              await context.read<ProfileProvider>().deleteProfile(widget.profile.id);
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF1F1F1F),
                    content: Text('Profile "${widget.profile.name}" deleted.', style: const TextStyle(color: Colors.white)),
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

  void _showLanguageDialog() {
    final languages = [
      'English',
      'Hindi',
      'Urdu',
      'Nepali',
      'Español',
      'Français',
      'Deutsch',
      'Italiano',
      '日本語',
      '한국어',
      'Português',
      'العربية',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                'Display Language',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(color: Colors.white12),
            ...languages.map((l) {
              final isSel = _displayLanguage == l;
              return ListTile(
                title: Text(l, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                trailing: isSel ? const Icon(Icons.check, color: AppTheme.primaryRed) : null,
                onTap: () {
                  setState(() => _displayLanguage = l);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSearchableLanguagePicker({
    required String title,
    required String current,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = options.where((o) => o.toLowerCase().contains(query.toLowerCase())).toList();

            return SafeArea(
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.75,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      child: TextField(
                        onChanged: (q) => setModalState(() => query = q),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search language...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                          filled: true,
                          fillColor: const Color(0xFF222222),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final opt = filtered[idx];
                          final isSel = current == opt;
                          final info = LanguageUtils.getInfo(opt);

                          return ListTile(
                            leading: Text(
                              opt.contains('Original') ? '🔊' : (opt.contains('Off') ? '🚫' : info.flag),
                              style: const TextStyle(fontSize: 20),
                            ),
                            title: Text(
                              opt,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.white70,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            trailing: isSel
                                ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryRed, size: 22)
                                : null,
                            onTap: () {
                              onSelected(opt);
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
          },
        );
      },
    );
  }

  void _showPreferredAudioSheet() {
    final options = [
      'Original Audio',
      ...LanguageUtils.supportedLanguages.map((l) => l.name),
    ];
    _showSearchableLanguagePicker(
      title: 'Preferred Audio Language',
      current: _preferredAudio,
      options: options,
      onSelected: (val) => setState(() => _preferredAudio = val),
    );
  }

  void _showPreferredSubtitleSheet() {
    final options = [
      'Off / None',
      ...LanguageUtils.supportedLanguages.map((l) => l.name),
    ];
    _showSearchableLanguagePicker(
      title: 'Preferred Subtitle Language',
      current: _preferredSubtitle,
      options: options,
      onSelected: (val) => setState(() => _preferredSubtitle = val),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalProfiles = context.watch<ProfileProvider>().profiles.length;

    return TvScreenWrapper(
      onBack: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: const TvBackButton(),
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          actions: [
            TextButton(
              onPressed: _saveProfile,
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Profile Avatar with Pencil badge (Screenshot 5)
          Center(
            child: GestureDetector(
              onTap: _openChooseIcon,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: _avatar.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: _avatar,
                              fit: BoxFit.cover,
                            )
                          : ProfileAvatarTile(
                              name: _nameController.text,
                              gradientColors: ProfileProvider.avatarGradients[
                                  _selectedColorIndex % ProfileProvider.avatarGradients.length],
                              size: 96,
                              isKids: _isKids,
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Profile Name Input (Screenshot 5)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E24),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
                hintText: 'Profile Name',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Game Handle (Screenshot 5)
          _buildSettingsTile(
            icon: Icons.sports_esports_outlined,
            title: 'Game Handle',
            subtitle: _gameHandle.isNotEmpty ? _gameHandle : 'Create your game handle',
            onTap: _showGameHandleDialog,
          ),
          const SizedBox(height: 10),

          // 4. Viewing Restrictions (Screenshot 5)
          _buildSettingsTile(
            icon: Icons.warning_amber_rounded,
            title: 'Viewing Restrictions',
            subtitle: _maturityRating,
            onTap: _showMaturityDialog,
          ),
          const SizedBox(height: 10),

          // 5. Profile lock (Screenshot 5)
          _buildSettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Profile lock',
            subtitle: _pin != null && _pin!.isNotEmpty
                ? 'PIN protection active'
                : 'Add a 4-digit PIN to this profile',
            onTap: _showPinDialog,
          ),
          const SizedBox(height: 10),

          // 6. Display Language (Screenshot 5)
          _buildSettingsTile(
            icon: Icons.translate_rounded,
            title: 'Display Language',
            subtitle: 'Change the language of the text you see on Netflix across all devices.',
            onTap: _showLanguageDialog,
          ),
          const SizedBox(height: 10),

          // 7A. Preferred Audio Language
          _buildSettingsTile(
            icon: Icons.mic_none_rounded,
            title: 'Preferred Audio Language',
            subtitle: _preferredAudio,
            onTap: _showPreferredAudioSheet,
          ),
          const SizedBox(height: 10),

          // 7B. Preferred Subtitle Language
          _buildSettingsTile(
            icon: Icons.subtitles_outlined,
            title: 'Preferred Subtitle Language',
            subtitle: _preferredSubtitle,
            onTap: _showPreferredSubtitleSheet,
          ),
          const SizedBox(height: 10),

          // 8. Subtitle Appearance (Screenshot 5 -> Screenshot 4)
          _buildSettingsTile(
            icon: Icons.closed_caption_outlined,
            title: 'Subtitle Appearance',
            subtitle: 'Change the way subtitles appear on phones and tablets.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubtitleAppearanceScreen()),
              );
            },
          ),
          const SizedBox(height: 10),

          // 9. Autoplay Next Episode Switch (Screenshot 5)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.playlist_play_rounded, color: Colors.white70, size: 24),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autoplay Next Episode',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'On all devices',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoplayNext,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (val) => setState(() => _autoplayNext = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 10. Autoplay Previews Switch (Screenshot 5)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.autorenew_rounded, color: Colors.white70, size: 24),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autoplay Previews',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'On all devices',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoplayPreviews,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (val) => setState(() => _autoplayPreviews = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 11. Delete Profile (Screenshot 5)
          if (totalProfiles > 1)
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                label: const Text(
                  'Delete Profile',
                  style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  context.read<ProfileProvider>().deleteProfile(widget.profile.id);
                  Navigator.of(context).pop();
                },
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    ),
  );
}

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: Colors.white70, size: 22),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        onTap: onTap,
      ),
    );
  }
}
