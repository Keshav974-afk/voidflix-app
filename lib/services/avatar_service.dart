import 'dart:convert';
import 'package:flutter/services.dart';

class NetflixAvatar {
  final String id;
  final String name;
  final String url;
  final String category;

  const NetflixAvatar({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
  });

  factory NetflixAvatar.fromJson(Map<String, dynamic> json, String category) {
    return NetflixAvatar(
      id: json['asset_id'] as String? ?? json['uuid'] as String? ?? '',
      name: json['name'] as String? ?? 'Avatar',
      url: json['url'] as String? ?? '',
      category: category,
    );
  }
}

class AvatarService {
  static final AvatarService _instance = AvatarService._internal();
  factory AvatarService() => _instance;
  AvatarService._internal();

  Map<String, List<NetflixAvatar>> _categories = {};
  List<NetflixAvatar> _allAvatars = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  Map<String, List<NetflixAvatar>> get categories => _categories;
  List<NetflixAvatar> get allAvatars => _allAvatars;

  /// Default curated top avatars available immediately before async load finishes
  static const List<NetflixAvatar> defaultFeatured = [
    NetflixAvatar(
      id: 'classic_scarlet_chilleez',
      name: 'Scarlet Chilleez',
      url: 'https://occ-0-4873-3647.1.nflxso.net/dnm/api/v6/SO2HoVCx33X8phZh2pZZmQ4QgNY/AAAABTk6nphithdqaDreuMsv-yBIzn5xmqqPyz35rHfxkU78C5oD_iRonk_v4jEoZq0U5XFq2c8Qn3phI_uchLj9PKfzFWHgA_QaHw.png?r=201',
      category: 'The Classics',
    ),
    NetflixAvatar(
      id: 'classic_sunny_chilleez',
      name: 'Sunny Chilleez',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABaB4hP-03hFOdIwXeYrc_Fb0P-QukEb4sV2BnOlJKVG1dpjJpL7aUOu4VFZenH1zr20DMYE6e8Fa6E7L9BnCvKlDzZEd25S_Ew.png?r=7c7',
      category: 'The Classics',
    ),
    NetflixAvatar(
      id: 'classic_robin_chilleez',
      name: 'Robin Chilleez',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTzykXqE0IgG15a8RLZ7okU8HrL3PU7kuNVL91w9HjwJXRswlPVKSVvVdYUSoea9F1CONTUIZyRzxpgZFd0XC94v-svyKCQpXA.png?r=b39',
      category: 'The Classics',
    ),
    NetflixAvatar(
      id: 'classic_dusty_chilleez',
      name: 'Dusty Chilleez',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABfV378_nLCLJYYUS14ujtntA1bLSp4VseVCuahmhQGGoWVOwxuuqGAmICG3H5L-24Fvh8Ezkj6Fik4F9jMGbFitqsfnFrDVh6Q.png?r=6a6',
      category: 'The Classics',
    ),
    NetflixAvatar(
      id: 'mh_mask',
      name: 'Dalí Mask',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABQPQcU0ckecAwbr6vEDlu2l5UawW6M82K7Sgx2dgpj9XIUW9sSJosAXvp2l_1hTdCxCEs9uFwyfYXgW-BrN-qDBNtTND3rmrlw.png?r=d0a',
      category: 'Money Heist',
    ),
    NetflixAvatar(
      id: 'mh_professor',
      name: 'The Professor',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYqQWXH98Pzf8msDpV2poLCKqSG4BOt4NoHMH-R6s0HYdbbXbUelr9AjwvYRiLT6p9bNQQNeIICa3d-Hsgyr663l-9aQaR1VTg.png?r=b38',
      category: 'Money Heist',
    ),
    NetflixAvatar(
      id: 'st_eleven',
      name: 'Eleven',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTXzu7xECGCa9z4eCqIeE0swz7mk86sF7IGahya6fYok4wqRGpm2oO_uMKwL6zNYhI37ljISGDe5iF__eGTncUToQxQ-atNbDA.png?r=1bb',
      category: 'Stranger Things',
    ),
    NetflixAvatar(
      id: 'st_dustin',
      name: 'Dustin',
      url: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYlk619kRF7q9TiQTwALJJRQhiwjuO7dIUZIQignWt6UaFXYyvNrUVB-0Cb_0oRxfyQUbteWQ9SPtmTJJFA2zhV5oGzoJDSVog.png?r=f60',
      category: 'Stranger Things',
    ),
  ];

  Future<void> loadAvatars() async {
    if (_isLoaded) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/netflix_avatars.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final rawCategories = data['categories'] as Map<String, dynamic>? ?? {};

      final Map<String, List<NetflixAvatar>> parsedCats = {};
      final List<NetflixAvatar> all = [];

      rawCategories.forEach((catName, list) {
        if (list is List) {
          final catAvatars = list
              .map((item) => NetflixAvatar.fromJson(item as Map<String, dynamic>, catName))
              .where((a) => a.url.isNotEmpty)
              .toList();
          if (catAvatars.isNotEmpty) {
            parsedCats[catName] = catAvatars;
            all.addAll(catAvatars);
          }
        }
      });

      _categories = parsedCats;
      _allAvatars = all;
      _isLoaded = true;
    } catch (_) {
      // Fallback
      _allAvatars = List.from(defaultFeatured);
      _categories = {'Featured': List.from(defaultFeatured)};
      _isLoaded = true;
    }
  }

  List<NetflixAvatar> search(String query) {
    if (query.trim().isEmpty) return _allAvatars;
    final q = query.toLowerCase().trim();
    return _allAvatars.where((a) {
      return a.name.toLowerCase().contains(q) || a.category.toLowerCase().contains(q);
    }).toList();
  }
}
