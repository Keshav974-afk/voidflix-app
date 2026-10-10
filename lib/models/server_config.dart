class VideoServer {
  final String name;
  final String description;
  final String Function(dynamic id) movieUrl;
  final String Function(dynamic id, int s, int e) tvUrl;
  final bool isDirectPlay;

  const VideoServer({
    required this.name,
    required this.description,
    required this.movieUrl,
    required this.tvUrl,
    this.isDirectPlay = false,
  });
}

class ServerConfig {
  static final List<VideoServer> servers = [
    // -------------------------------------------------------------------------
    // DIRECT NATIVE SERVERS (Extractable HLS • Hardware Accelerated • No Ads)
    // -------------------------------------------------------------------------
    VideoServer(
      name: "Cine4K (Lisbon)",
      description: "Direct 4K Ultra HD HDR / 1080p with multi-audio (Recommended)",
      movieUrl: (id) => "https://api.wing.st/embed/movie/$id",
      tvUrl: (id, s, e) => "https://api.wing.st/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "NebulaHD",
      description: "Direct Full HD 1080p HLS stream with native player",
      movieUrl: (id) => "https://api.wing.st/embed/movie/$id",
      tvUrl: (id, s, e) => "https://api.wing.st/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "VoidDirect (Native)",
      description: "Direct stream extraction with native player (Recommended)",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "OrionStream",
      description: "Ultra-fast direct 1080p HLS cluster with native player",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "PulsarHD",
      description: "Direct CDN HLS stream with native player",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "NovaStream",
      description: "Fast direct HLS cluster with native player",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "AtlasStream",
      description: "Low-latency direct HLS stream with native player",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "VoidHD",
      description: "Direct 1080p stream with native player",
      movieUrl: (id) => "https://vidlink.pro/movie/$id?primaryColor=e50914",
      tvUrl: (id, s, e) => "https://vidlink.pro/tv/$id/$s/$e?primaryColor=e50914",
      isDirectPlay: true,
    ),

    // -------------------------------------------------------------------------
    // VERIFIED WEB EMBED SERVERS (Active Fallback • Developer Mode Only)
    // -------------------------------------------------------------------------
    VideoServer(
      name: "TurboStream",
      description: "High speed bufferless stream",
      movieUrl: (id) => "https://player.videasy.to/movie/$id?progress=true",
      tvUrl: (id, s, e) => "https://player.videasy.to/tv/$id/$s/$e?progress=true",
    ),
    VideoServer(
      name: "QuantumX",
      description: "Fast low-latency stream engine",
      movieUrl: (id) => "https://vidfast.vc/movie/$id",
      tvUrl: (id, s, e) => "https://vidfast.vc/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "FlashPlay",
      description: "Fast buffer-free server",
      movieUrl: (id) => "https://vidsrc.to/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidsrc.to/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "CosmoPlay",
      description: "Adaptive multi-server embed",
      movieUrl: (id) => "https://autoembed.to/movie/tmdb/$id",
      tvUrl: (id, s, e) => "https://autoembed.to/tv/tmdb/$id/$s/$e",
    ),
    VideoServer(
      name: "SmashyStream",
      description: "High-speed multi-quality embed cluster",
      movieUrl: (id) => "https://embed.smashystream.com/playere.php?tmdb=$id",
      tvUrl: (id, s, e) => "https://embed.smashystream.com/playere.php?tmdb=$id&season=$s&episode=$e",
    ),
    VideoServer(
      name: "CloudCast",
      description: "Global cloud streaming mirror",
      movieUrl: (id) => "https://www.2embed.cc/embed/$id",
      tvUrl: (id, s, e) => "https://www.2embed.cc/embedtv/$id&s=$s&e=$e",
    ),
    VideoServer(
      name: "AuraCine",
      description: "Multi-quality cinema engine",
      movieUrl: (id) => "https://vidcore.io/movie/$id",
      tvUrl: (id, s, e) => "https://vidcore.io/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "NontonGo",
      description: "Global streaming network",
      movieUrl: (id) => "https://www.NontonGo.win/embed/movie/$id",
      tvUrl: (id, s, e) => "https://www.NontonGo.win/embed/tv/$id/$s/$e",
    ),
  ];

  static String getEmbedUrl({
    required VideoServer server,
    required String type, // 'movie' or 'tv'
    required int id,
    int season = 1,
    int episode = 1,
  }) {
    if (type == 'tv') {
      return server.tvUrl(id, season, episode);
    }
    return server.movieUrl(id);
  }
}
