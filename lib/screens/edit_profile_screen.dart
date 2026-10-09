import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/theme_constants.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';
import 'choose_icon_screen.dart';
import 'subtitle_appearance_screen.dart';

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
  String _audioLanguages = 'English, Original';
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
      _audioLanguages = prefs.getString('profile_${widget.profile.id}_audio_lang') ?? 'English, Original';
      _autoplayNext = prefs.getBool('profile_${widget.profile.id}_autoplay_next') ?? true;
      _autoplayPreviews = prefs.getBool('profile_${widget.profile.id}_autoplay_previews') ?? true;
    });
  }

  Future<void> _saveExtraSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_${widget.profile.id}_game_handle', _gameHandle);
    await prefs.setString('profile_${widget.profile.id}_maturity', _maturityRating);
    await prefs.setString('profile_${widget.profile.id}_lang', _displayLanguage);
    await prefs.setString('profile_${widget.profile.id}_audio_lang', _audioLanguages);
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
    final pinCtl = TextEditingController(text: _pin ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Profile Lock PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Require a 4-digit PIN to access this profile.',
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
                fillColor: const Color(0xFF14141E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          if (_pin != null && _pin!.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _pin = null);
                Navigator.of(ctx).pop();
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
              setState(() => _pin = text.isEmpty ? null : text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    final languages = ['English', 'Español', 'Français', 'Deutsch', 'Italiano', 'Hindi', '日本語', '한국어', 'Português'];
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

  void _showAudioLanguagesDialog() {
    final audioOptions = [
      'English, Original',
      'Hindi, English',
      'Japanese, English',
      'Korean, English',
      'Spanish, English',
      'All Languages (Multi-Audio)',
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
                'Audio & Subtitle Languages',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(color: Colors.white12),
            ...audioOptions.map((opt) {
              final isSel = _audioLanguages == opt;
              return ListTile(
                title: Text(opt, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                trailing: isSel ? const Icon(Icons.check, color: AppTheme.primaryRed) : null,
                onTap: () {
                  setState(() => _audioLanguages = opt);
                  Navigator.pop(ctx);
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
    final totalProfiles = context.watch<ProfileProvider>().profiles.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
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

          // 7. Audio & Subtitle Languages (Screenshot 5)
          _buildSettingsTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Audio & Subtitle Languages',
            subtitle: 'Choose the languages you like to watch shows and movies in.',
            onTap: _showAudioLanguagesDialog,
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
