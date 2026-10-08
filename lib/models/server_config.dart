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
    VideoServer(
      name: "VoidDirect (Native)",
      description: "Direct stream extraction with native player (Recommended)",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
      isDirectPlay: true,
    ),
    VideoServer(
      name: "VoidHD",
      description: "Ultra-fast direct player (Recommended)",
      movieUrl: (id) => "https://vidlink.pro/movie/$id?primaryColor=e50914",
      tvUrl: (id, s, e) => "https://vidlink.pro/tv/$id/$s/$e?primaryColor=e50914",
    ),
    VideoServer(
      name: "TurboStream",
      description: "High speed multi-quality stream",
      movieUrl: (id) => "https://player.videasy.net/movie/$id?progress=true",
      tvUrl: (id, s, e) => "https://player.videasy.net/tv/$id/$s/$e?progress=true",
    ),
    VideoServer(
      name: "QuantumX",
      description: "Fast low-latency stream engine",
      movieUrl: (id) => "https://vidfast.pro/movie/$id",
      tvUrl: (id, s, e) => "https://vidfast.pro/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "EmberPlay",
      description: "Multi-quality bufferless stream",
      movieUrl: (id) => "https://embed.su/embed/movie/$id",
      tvUrl: (id, s, e) => "https://embed.su/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "VixHD",
      description: "HD cinema stream with subtitles",
      movieUrl: (id) => "https://vixsrc.to/movie/$id",
      tvUrl: (id, s, e) => "https://vixsrc.to/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "PulsarHD",
      description: "Low latency streaming source",
      movieUrl: (id) => "https://vidrock.ru/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidrock.ru/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "FlashPlay",
      description: "Fast buffer-free server",
      movieUrl: (id) => "https://vidsrc.me/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidsrc.me/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "NebulaHD",
      description: "Reliable fallback server",
      movieUrl: (id) => "https://vidsrc.cc/v2/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidsrc.cc/v2/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "TitanPlay",
      description: "High reliability cinema server",
      movieUrl: (id) => "https://111movies.com/movie/$id",
      tvUrl: (id, s, e) => "https://111movies.com/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "AstroFlix",
      description: "Instant adaptive auto-embed stream",
      movieUrl: (id) => "https://player.autoembed.cc/embed/movie/$id",
      tvUrl: (id, s, e) => "https://player.autoembed.cc/embed/tv/$id/$s/$e",
    ),
    VideoServer(
      name: "OrbitCine",
      description: "Alternative multi-source mirror",
      movieUrl: (id) => "https://moviesapi.club/movie/$id",
      tvUrl: (id, s, e) => "https://moviesapi.club/tv/$id-$s-$e",
    ),
    VideoServer(
      name: "PrimeView",
      description: "Alternative multi-language server",
      movieUrl: (id) => "https://vidsrc.pro/embed/movie/$id",
      tvUrl: (id, s, e) => "https://vidsrc.pro/embed/tv?tmdb=$id&season=$s&episode=$e",
    ),
    VideoServer(
      name: "CloudCast",
      description: "Global cloud streaming mirror",
      movieUrl: (id) => "https://www.2embed.cc/embed/$id",
      tvUrl: (id, s, e) => "https://www.2embed.cc/embedtv/$id&s=$s&e=$e",
    ),
    VideoServer(
      name: "NovaStream",
      description: "Multi-embed global network",
      movieUrl: (id) => "https://multiembed.mov/?video_id=$id&tmdb=1",
      tvUrl: (id, s, e) => "https://multiembed.mov/?video_id=$id&tmdb=1&s=$s&e=$e",
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
