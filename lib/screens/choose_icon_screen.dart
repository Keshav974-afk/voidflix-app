import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/profile_provider.dart';
import '../services/avatar_service.dart';

class AvatarItem {
  final String id;
  final String name;
  final String? imageUrl;
  final int? colorIndex;

  const AvatarItem({
    required this.id,
    required this.name,
    this.imageUrl,
    this.colorIndex,
  });
}

class ChooseIconScreen extends StatefulWidget {
  final UserProfile profile;

  const ChooseIconScreen({super.key, required this.profile});

  @override
  State<ChooseIconScreen> createState() => _ChooseIconScreenState();
}

class _ChooseIconScreenState extends State<ChooseIconScreen> {
  final AvatarService _avatarService = AvatarService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvatars();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAvatars() async {
    await _avatarService.loadAvatars();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectAvatar(AvatarItem item) {
    if (widget.profile.id != 'temp') {
      final provider = context.read<ProfileProvider>();
      if (item.imageUrl != null) {
        provider.updateProfile(
          widget.profile.id,
          avatar: item.imageUrl!,
        );
      } else if (item.colorIndex != null) {
        provider.updateProfile(
          widget.profile.id,
          colorIndex: item.colorIndex!,
          avatar: item.name,
        );
      }
    }
    Navigator.of(context).pop(item);
  }

  Widget _buildAvatarCard(AvatarItem item) {
    return GestureDetector(
      onTap: () => _selectAvatar(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12, width: 1.2),
          ),
          child: item.imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.imageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  memCacheHeight: 200,
                  placeholder: (c, u) => Container(color: const Color(0xFF1E1E24)),
                  errorWidget: (c, u, e) => Container(
                    color: const Color(0xFF1E1E24),
                    child: const Icon(Icons.person, color: Colors.white54, size: 36),
                  ),
                )
              : Container(
                  color: const Color(0xFFE50914),
                  child: Center(
                    child: Text(
                      item.name.isNotEmpty ? item.name[0] : 'V',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildAvatarGrid(List<AvatarItem> items) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (ctx, idx) => _buildAvatarCard(items[idx]),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 22, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatar = widget.profile.avatar.startsWith('http')
        ? widget.profile.avatar
        : AvatarService.defaultFeatured.first.url;

    final categories = _avatarService.categories;
    final isSearching = _searchQuery.isNotEmpty;
    final searchResults = isSearching ? _avatarService.search(_searchQuery) : <NetflixAvatar>[];

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
          'Choose Icon',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE50914)),
            )
          : Column(
              children: [
                // Search Bar across 976 avatars
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search 970+ characters or shows...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                        suffixIcon: isSearching
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: isSearching
                      ? (searchResults.isEmpty
                          ? const Center(
                              child: Text(
                                'No avatars found',
                                style: TextStyle(color: Colors.white54, fontSize: 15),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final a = searchResults[index];
                                final item = AvatarItem(
                                  id: a.id,
                                  name: a.name,
                                  imageUrl: a.url,
                                );
                                return _buildAvatarCard(item);
                              },
                            ))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: [
                            // Current Icon
                            _buildSectionHeader('Current Icon'),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFE50914), width: 2.0),
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: currentAvatar,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 200,
                                        memCacheHeight: 200,
                                        placeholder: (c, u) => Container(color: const Color(0xFF1E1E24)),
                                        errorWidget: (c, u, e) => Container(
                                          color: const Color(0xFF1E1E24),
                                          child: const Icon(Icons.person, color: Colors.white54, size: 36),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // All 103 Official Netflix Categories
                            ...categories.entries.map((entry) {
                              final catName = entry.key;
                              final avatarList = entry.value.map((a) {
                                return AvatarItem(
                                  id: a.id,
                                  name: a.name,
                                  imageUrl: a.url,
                                );
                              }).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(catName),
                                  _buildAvatarGrid(avatarList),
                                ],
                              );
                            }),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
