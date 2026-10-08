import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/theme_constants.dart';
import '../providers/media_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late int _selectedColorIndex;
  late bool _isKids;
  String? _pin;
  bool _autoplayNext = true;
  late Set<String> _preferredLanguages;
  late Set<int> _preferredGenres;
  late Set<String> _favoriteActors;
  late List<String> _favoriteTitles;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _selectedColorIndex = widget.profile.colorIndex;
    _isKids = widget.profile.isKids;
    _pin = widget.profile.pin;
    _preferredLanguages = Set.from(widget.profile.preferredLanguages);
    _preferredGenres = Set.from(widget.profile.preferredGenres);
    _favoriteActors = Set.from(widget.profile.favoriteActors);
    _favoriteTitles = List.from(widget.profile.favoriteTitles);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final profileProv = context.read<ProfileProvider>();
    profileProv.updateProfile(
      widget.profile.id,
      name: name,
      colorIndex: _selectedColorIndex,
      isKids: _isKids,
      pin: _pin,
      clearPin: _pin == null || _pin!.isEmpty,
    );

    profileProv.updateProfilePreferences(
      widget.profile.id,
      preferredLanguages: _preferredLanguages.toList(),
      preferredGenres: _preferredGenres.toList(),
      favoriteActors: _favoriteActors.toList(),
      favoriteTitles: _favoriteTitles,
    );

    if (profileProv.activeProfile.id == widget.profile.id) {
      context.read<MediaProvider>().fetchPersonalizedForProfile(
        profileProv.activeProfile,
        force: true,
      );
    }

    Navigator.of(context).pop();
  }

  void _showEditInterestsDialog() {
    final availableLanguages = [
      {'code': 'hi', 'name': 'Hindi & Bollywood', 'badge': '🇮🇳'},
      {'code': 'en', 'name': 'English & Hollywood', 'badge': '🇺🇸'},
      {'code': 'ja', 'name': 'Anime & Japanese', 'badge': '🇯🇵'},
      {'code': 'ko', 'name': 'K-Drama & Korean', 'badge': '🇰🇷'},
      {'code': 'te', 'name': 'South Indian Cinema', 'badge': '🇮🇳'},
    ];

    final availableGenres = [
      {'id': 878, 'name': 'Sci-Fi'},
      {'id': 28, 'name': 'Action'},
      {'id': 16, 'name': 'Anime'},
      {'id': 35, 'name': 'Comedy'},
      {'id': 27, 'name': 'Horror'},
      {'id': 53, 'name': 'Thriller'},
      {'id': 10749, 'name': 'Romance'},
      {'id': 14, 'name': 'Fantasy'},
      {'id': 80, 'name': 'Crime'},
      {'id': 99, 'name': 'Documentaries'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Personalized Cinema Preferences',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Adjust your favored languages and genres for customized home feed recommendations:',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    const Text('Languages', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableLanguages.map((l) {
                        final code = l['code'] as String;
                        final isSel = _preferredLanguages.contains(code);
                        return FilterChip(
                          selected: isSel,
                          backgroundColor: const Color(0xFF161622),
                          selectedColor: AppTheme.primaryRed,
                          label: Text('${l['badge']} ${l['name']}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          onSelected: (sel) {
                            setSheetState(() {
                              setState(() {
                                if (sel) {
                                  _preferredLanguages.add(code);
                                } else {
                                  _preferredLanguages.remove(code);
                                }
                              });
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Genres & Movie Types', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableGenres.map((g) {
                        final id = g['id'] as int;
                        final isSel = _preferredGenres.contains(id);
                        return FilterChip(
                          selected: isSel,
                          backgroundColor: const Color(0xFF161622),
                          selectedColor: AppTheme.primaryRed,
                          label: Text(g['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          onSelected: (sel) {
                            setSheetState(() {
                              setState(() {
                                if (sel) {
                                  _preferredGenres.add(id);
                                } else {
                                  _preferredGenres.remove(id);
                                }
                              });
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose Avatar Color',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(ProfileProvider.avatarGradients.length, (idx) {
                  final isSelected = idx == _selectedColorIndex;
                  final colors = ProfileProvider.avatarGradients[idx];
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedColorIndex = idx);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 22) : null,
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPinDialog() {
    final pinCtl = TextEditingController(text: _pin ?? '');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceVariant,
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
                  fillColor: AppTheme.cardColor,
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
        );
      },
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
          // Profile Avatar with Pencil badge (Screenshot 4)
          Center(
            child: GestureDetector(
              onTap: _showColorPicker,
              child: Stack(
                children: [
                  ProfileAvatarTile(
                    name: _nameController.text,
                    gradientColors: ProfileProvider.avatarGradients[_selectedColorIndex],
                    size: 96,
                    isKids: _isKids,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Name Input Box (Screenshot 4)
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
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Grouped Settings List (Exact Screenshot 4 items)
          _buildSettingsTile(
            icon: Icons.sports_esports_outlined,
            title: 'Game Handle',
            subtitle: 'Create your game handle',
            onTap: () {},
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.warning_amber_rounded,
            title: 'Viewing Restrictions',
            subtitle: _isKids ? 'Kids (TV-Y, TV-G, G)' : 'No restrictions',
            onTap: () {
              setState(() => _isKids = !_isKids);
            },
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Profile lock',
            subtitle: _pin != null && _pin!.isNotEmpty
                ? 'PIN protection active'
                : 'Add a 4-digit PIN to this profile',
            onTap: _showPinDialog,
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.translate_rounded,
            title: 'Display Language',
            subtitle: 'Change the language of the text you see on Voidflix across all devices.',
            onTap: () {},
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Audio & Subtitle Languages',
            subtitle: 'Choose the languages you like to watch shows and movies in.',
            onTap: () {},
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.closed_caption_outlined,
            title: 'Subtitle Appearance',
            subtitle: 'Change the way subtitles appear on phones and tablets.',
            onTap: () {},
          ),
          const SizedBox(height: 10),

          _buildSettingsTile(
            icon: Icons.auto_awesome,
            title: 'Cinema Preferences & Feed',
            subtitle: 'Tune favorite genres and languages tailored for this profile.',
            onTap: _showEditInterestsDialog,
          ),
          const SizedBox(height: 10),

          // Autoplay Next Episode Switch (Screenshot 4)
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
          const SizedBox(height: 28),

          // Delete Profile button
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
        leading: Icon(icon, color: Colors.white70, size: 24),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }
}
