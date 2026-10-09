import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_avatar.dart';

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
  // Official Netflix CDN Classic Furry & Smiley avatars
  static const List<AvatarItem> _classics = [
    AvatarItem(
      id: 'classic_scarlet_chilleez',
      name: 'Scarlet Chilleez',
      imageUrl: 'https://occ-0-4873-3647.1.nflxso.net/dnm/api/v6/SO2HoVCx33X8phZh2pZZmQ4QgNY/AAAABTk6nphithdqaDreuMsv-yBIzn5xmqqPyz35rHfxkU78C5oD_iRonk_v4jEoZq0U5XFq2c8Qn3phI_uchLj9PKfzFWHgA_QaHw.png?r=201',
    ),
    AvatarItem(
      id: 'classic_sunny_chilleez',
      name: 'Sunny Chilleez',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABaB4hP-03hFOdIwXeYrc_Fb0P-QukEb4sV2BnOlJKVG1dpjJpL7aUOu4VFZenH1zr20DMYE6e8Fa6E7L9BnCvKlDzZEd25S_Ew.png?r=7c7',
    ),
    AvatarItem(
      id: 'classic_robin_chilleez',
      name: 'Robin Chilleez',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTzykXqE0IgG15a8RLZ7okU8HrL3PU7kuNVL91w9HjwJXRswlPVKSVvVdYUSoea9F1CONTUIZyRzxpgZFd0XC94v-svyKCQpXA.png?r=b39',
    ),
    AvatarItem(
      id: 'classic_dusty_chilleez',
      name: 'Dusty Chilleez',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABfV378_nLCLJYYUS14ujtntA1bLSp4VseVCuahmhQGGoWVOwxuuqGAmICG3H5L-24Fvh8Ezkj6Fik4F9jMGbFitqsfnFrDVh6Q.png?r=6a6',
    ),
    AvatarItem(
      id: 'classic_red_smile',
      name: 'Red Smile',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABakRc13qnznu9gXCjeNTetIpWLBYv1BHtjenkcA2UPHsk_oKNyiEjMqDg5JrLMa6B-Ynairtq2_fSFPjKJ6mqB2xuIeeCZm23A.png?r=e6e',
    ),
    AvatarItem(
      id: 'classic_yellow_smile',
      name: 'Yellow Smile',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABelkMs-h2DXUYbzHHCaFQo7ykBvO6JoCssR5azSK1jNcUTRExSzh9R1HNbNbWzIhTri5iN8U3N9GSmbXeLASZqL5IKRHLri1PA.png?r=1d4',
    ),
    AvatarItem(
      id: 'classic_green_smile',
      name: 'Green Smile',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABXan2ftdVhTtVVzZctW_PhUGLw-uzzdXn1BaTkNyVzJQk62yuNZpVU0_GUBJu9X6ry23mg6k7-C11lblVvDFot41ZZ6dxcZoFw.png?r=a4b',
    ),
    AvatarItem(
      id: 'classic_purple_smile',
      name: 'Purple Smile',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABVhab2XqRI6ThDSR6UvGIb_4U4tDnYLNtsDTaZxg91Vj02LwK50_WVhohDm7wDZ_ncQP7D9EQo_iPdzQDCU7ulekO9gcgOMKDw.png?r=98e',
    ),
    AvatarItem(
      id: 'classic_blue_smile',
      name: 'Blue Classic',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABXh10ggeTTdhZO1JIH_SNQ4gp0vsNnWfE8Mg2ckwzGvUzJMRpPFCujRK3Ex5K9VbkIyvUHQ92LBVdsemkj6zlpquL-qWMCNKeg.png?r=229',
    ),
  ];

  // Money Heist (La Casa de Papel) Characters
  static const List<AvatarItem> _moneyHeist = [
    AvatarItem(
      id: 'mh_mask',
      name: 'Salvador Dalí Mask',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABQPQcU0ckecAwbr6vEDlu2l5UawW6M82K7Sgx2dgpj9XIUW9sSJosAXvp2l_1hTdCxCEs9uFwyfYXgW-BrN-qDBNtTND3rmrlw.png?r=d0a',
    ),
    AvatarItem(
      id: 'mh_professor',
      name: 'The Professor',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYqQWXH98Pzf8msDpV2poLCKqSG4BOt4NoHMH-R6s0HYdbbXbUelr9AjwvYRiLT6p9bNQQNeIICa3d-Hsgyr663l-9aQaR1VTg.png?r=b38',
    ),
    AvatarItem(
      id: 'mh_tokio',
      name: 'Tokio',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABZIN5ALWTmxTEQzWlyqBhHzRBeBtVN-FpWudf6fgrghnio_-XZIbS3jdQ0abnzMFN1VwaKHm8j4Wj3G7iw-_s2VOuzI0rmTfig.png?r=852',
    ),
    AvatarItem(
      id: 'mh_berlin',
      name: 'Berlin',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABXJL5OiMgZqLIwU3q4Xs8tsbDieQ4SyZ59Rpo1PCa3128dbRl5hIISzxENmDsYaBOy9y_Xvu9H5hPcL1uDNzuuYGGc1XMauFXg.png?r=cf8',
    ),
    AvatarItem(
      id: 'mh_nairobi',
      name: 'Nairobi',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABWrhs_UHEmhWXUmtn2KzQ_ILxSeBreYN0kRAb-A5KNC0vzzOO7LEBUUx0AtTDHmr3hHTxKGWb4bmZ9CP0_iWzyFsQA0Tx-FSig.png?r=d19',
    ),
    AvatarItem(
      id: 'mh_denver',
      name: 'Denver',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABbl7F0njO1GGLokRd_l_HJl8hAOtA1FLsikTPsbsyk82p7jTs_xmWai7lLto1o_pzd5cDztdixXgC3RA4XqGu9Wy5-xGzJFAEg.png?r=b83',
    ),
    AvatarItem(
      id: 'mh_rio',
      name: 'Rio',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABbZsPMN0WlgI5IKskDuJ2DHcEpGRHjclXbMoE23gK_jaglJm7BlAmG0SdBxdpIefEqPQSL_48bxuS6StDaZgAVtlrl-li3LxMA.png?r=959',
    ),
    AvatarItem(
      id: 'mh_lisboa',
      name: 'Lisboa',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABbMJZT8S6d3BnEzpcTPlmwh13s7_A3QMFp3mqRQZsStQv9GHf4GgmV8rQtpc4vchlkDB0E3xO3SybxI6j5CW1diRam0u8ydjOg.png?r=619',
    ),
  ];

  // Stranger Things Characters
  static const List<AvatarItem> _strangerThings = [
    AvatarItem(
      id: 'st_eleven',
      name: 'Eleven',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTXzu7xECGCa9z4eCqIeE0swz7mk86sF7IGahya6fYok4wqRGpm2oO_uMKwL6zNYhI37ljISGDe5iF__eGTncUToQxQ-atNbDA.png?r=1bb',
    ),
    AvatarItem(
      id: 'st_dustin',
      name: 'Dustin',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYlk619kRF7q9TiQTwALJJRQhiwjuO7dIUZIQignWt6UaFXYyvNrUVB-0Cb_0oRxfyQUbteWQ9SPtmTJJFA2zhV5oGzoJDSVog.png?r=f60',
    ),
    AvatarItem(
      id: 'st_eddie',
      name: 'Eddie',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABT80pSdtOL8qzdrRtJISys90D3h5NbTpPmaR472mHDPiku5h2D4HDG6j1vl-A4h0_Ycb-4LXlbhKn9wqhQc0rrmypevjsiqHRQ.png?r=c31',
    ),
    AvatarItem(
      id: 'st_hopper',
      name: 'Hopper',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABT-ycrcHhQ-h6ebg-wgzOpRLYhVhVDW4vYpYXaQ9ePKkubTr2GTMRLMxPZh7iz19e4QeNg4gPouTqEHoKarFk3JkLQev7C_nPQ.png?r=e6c',
    ),
    AvatarItem(
      id: 'st_lucas',
      name: 'Lucas',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABRmYagnYMNaIIO8ULw4eMXS7liCZcuoRNYzWeeFQlcHcGVMBOEx9D6BgplufY7g147VwMRdYLVhOA22zgnxMxDws7RFmmA1mOg.png?r=2d1',
    ),
    AvatarItem(
      id: 'st_argyle',
      name: 'Argyle',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABc-YJv207ZdlqqkWtEOUsE0kckOfJnyFv1aXJL9bMSITB47dIXoo_op_I-jGJFV1zOXtdPUzIs0UHDHt-n7Ay_Dr76jgYbKEDA.png?r=17d',
    ),
  ];

  // Squid Game Characters
  static const List<AvatarItem> _squidGame = [
    AvatarItem(
      id: 'sg_frontman',
      name: 'Front Man',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYi8u2Nz9dp3EF_xcUQoW4TbnDi672S6usNUHhola5qHBSVEhNnIG8FadHiWs_L985TvUX7ST9m7CijuBJqeoO5oHirnkPkNYw.png?r=66c',
    ),
    AvatarItem(
      id: 'sg_younghee',
      name: 'Young-hee Doll',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABWVoYzlSivjXDh16yJtaZ2BJ11T4Tnjuu2ODGqzGHaMvGliRQgaQrroMgVMDfXtlp9QKPYSKIWHIGjU83kcCpksI43rFWcus8g.png?r=83b',
    ),
    AvatarItem(
      id: 'sg_manager',
      name: 'Masked Manager',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABfPu2f1oZJ0FZdVC4ZppMaGFIZb1ACzzzlfHVDL_mt7IL6CIXRBkG25MwaF0odM6YCMBU8YVV_NAT9dP-r9Wv_3ttFb3hEAJvQ.png?r=d38',
    ),
    AvatarItem(
      id: 'sg_soldier',
      name: 'Masked Soldier',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABVAT9O2xslNGonW6i6hvuphcgvqG5pWL0pPTNGmI-aBBq9xpfcWRUwqPYd4W1EOycE6VhKEZAGmKU1miGeUG9toxfuwwG2Grig.png?r=0b0',
    ),
    AvatarItem(
      id: 'sg_worker',
      name: 'Masked Worker',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYF8dGeSMi9OTFGFtVt8LrkNh3KcVLQRddt3RbyJOx_36oG_Y0UGr-PZb6_4sCyVdNLQzfgcHQTZhLDTJJKQsujCNWWxgr8vRw.png?r=53d',
    ),
    AvatarItem(
      id: 'sg_gihun',
      name: 'Player 456 (Gi-hun)',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABYbrqdf7I4CYwyJH8YDRuWVX1wkNsxDXQpd3b3VO_My7_6_GL8g_r_kUC_dVstGYx5IQU5VK6xyysrHdPmampfcc56x_wT8HCg.png?r=c83',
    ),
  ];

  // Wednesday Characters
  static const List<AvatarItem> _wednesday = [
    AvatarItem(
      id: 'wed_wednesday',
      name: 'Wednesday Addams',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABS_fCAimFcSuIgnyvchWA3eNUjEsCsciKhhXfklGV3idvRbG7qu7YwPOCIyNrZNjkteloppY2M-9rXnuvUYXPqTIXh5GB9Ri_Q.png?r=02d',
    ),
    AvatarItem(
      id: 'wed_enid',
      name: 'Enid Sinclair',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABSXPwEmF1ALowNekM3-Uwn3C6sxfRrMDcs4b8KnmNQXc23gv5kjjYSnQEZvKtRN7RvnXVk-ynPqT_LTIeKqiBUOc-v06PRlbVQ.png?r=6c2',
    ),
    AvatarItem(
      id: 'wed_thing',
      name: 'Thing',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABTLZj0uwbm7xUAiqmyK1hsMyiQWZLhaMM7yg0YhTO7EJKaCKA_g-xAIWwWzZKNKHLbCx6RupWw9u7enfPOveA7UKo1HPzxaZKQ.png?r=421',
    ),
  ];

  // One Piece Characters
  static const List<AvatarItem> _onePiece = [
    AvatarItem(
      id: 'op_luffy',
      name: 'Monkey D. Luffy',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABc-963K_PIXK-o0mRr2QiuMS8-Q8HQZWqaRGwtx3mrzM-p23gjyOD-QRxjXtQWgxM2yVp0eKnTKRIW-8J43NWL0xzlEDsoxqOQ.png?r=0a4',
    ),
    AvatarItem(
      id: 'op_zoro',
      name: 'Roronoa Zoro',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABfsL-kSoIj-SCrh3uYYPjMyJEsf9kwnmCWxaTndO5Cm97v8elwFytcnsD0456DWfD1oNgKawnJhpC8iUisCC8lCgUr1vXMNS5w.png?r=3fc',
    ),
    AvatarItem(
      id: 'op_nami',
      name: 'Nami',
      imageUrl: 'https://occ-0-8782-2219.1.nflxso.net/dnm/api/v6/vN7bi_My87NPKvsBoib006Llxzg/AAAABW_3K6JepGxR9Z4R-9XgZDVsgYs7PsTdUHrIsoaB6fuy5EexRESHHvNbMykFjYTzDm_DaIg67Fajuls2Eykp8BF4_fNAXk9B9Q.png?r=396',
    ),
  ];

  void _selectAvatar(AvatarItem item) {
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
    Navigator.of(context).pop(item);
  }

  Widget _buildAvatarGrid(List<AvatarItem> items) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (ctx, idx) {
          final item = items[idx];
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
                        placeholder: (c, u) => Container(color: const Color(0xFF1E1E24)),
                        errorWidget: (c, u, e) => Container(
                          color: const Color(0xFF1E1E24),
                          child: const Icon(Icons.person, color: Colors.white54, size: 36),
                        ),
                      )
                    : ProfileAvatarTile(
                        name: item.name,
                        gradientColors: ProfileProvider.avatarGradients[
                            (item.colorIndex ?? 0) % ProfileProvider.avatarGradients.length],
                        size: 96,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 22, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatar = widget.profile.avatar.startsWith('http')
        ? widget.profile.avatar
        : _classics.first.imageUrl!;

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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _buildSectionHeader('The Classics'),
          _buildAvatarGrid(_classics),

          _buildSectionHeader('History'),
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
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: currentAvatar,
                      fit: BoxFit.cover,
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

          _buildSectionHeader('MONEY HEIST'),
          _buildAvatarGrid(_moneyHeist),

          _buildSectionHeader('STRANGER THINGS'),
          _buildAvatarGrid(_strangerThings),

          _buildSectionHeader('SQUID GAME'),
          _buildAvatarGrid(_squidGame),

          _buildSectionHeader('WEDNESDAY'),
          _buildAvatarGrid(_wednesday),

          _buildSectionHeader('ONE PIECE'),
          _buildAvatarGrid(_onePiece),
        ],
      ),
    );
  }
}
