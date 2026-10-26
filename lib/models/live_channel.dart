class LiveChannel {
  final dynamic id;
  final String name;
  final String category;
  final String streamUrl;
  final String? directStreamUrl;
  final String? logoUrl;
  final String? description;
  final Map<String, String>? httpHeaders;

  const LiveChannel({
    required this.id,
    required this.name,
    required this.category,
    required this.streamUrl,
    this.directStreamUrl,
    this.logoUrl,
    this.description,
    this.httpHeaders,
  });

  /// The active URL for in-app video playback
  String get playbackUrl => directStreamUrl ?? streamUrl;

  /// Whether this stream is an HLS .m3u8 stream playable natively by VideoPlayerController
  bool get isDirectHls {
    final url = playbackUrl.toLowerCase();
    return url.contains('.m3u8') || url.contains('m3u8');
  }
}

class LiveData {
  static const List<String> categories = [
    "All",
    "Cricket (Live)",
    "Sports",
    "News",
    "Movies",
    "Entertainment",
    "Kids",
    "Documentary",
  ];

  static final List<LiveChannel> channels = [
    // -------------------------------------------------------------
    // SPORTS
    // -------------------------------------------------------------
    const LiveChannel(
      id: "rb-sports",
      name: "Red Bull TV Live",
      category: "Sports",
      streamUrl: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8",
      directStreamUrl: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8",
      description: "24/7 global action sports, extreme outdoor events, Formula 1 highlights, cliff diving, and MTB championships.",
    ),
    const LiveChannel(
      id: "acc-sports",
      name: "ACC Sports Network",
      category: "Sports",
      streamUrl: "https://raycom-accdn-firetv.amagi.tv/playlist.m3u8",
      directStreamUrl: "https://raycom-accdn-firetv.amagi.tv/playlist.m3u8",
      description: "Live college football, NCAA basketball games, tournament coverage, and athletic analysis.",
    ),
    const LiveChannel(
      id: "30a-golf",
      name: "30A Golf Kingdom",
      category: "Sports",
      streamUrl: "https://30a-tv.com/feeds/vidaa/golf.m3u8",
      directStreamUrl: "https://30a-tv.com/feeds/vidaa/golf.m3u8",
      description: "Premier golf coverage, PGA tournament recaps, golf course tours, and master-class tips.",
    ),
    const LiveChannel(
      id: 130,
      name: "Sky Sports Main Event",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-130.php",
      directStreamUrl: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8",
      description: "Flagship live sports broadcast: Premier League, Formula 1 Grand Prix, cricket, golf, and major tournaments.",
    ),
    const LiveChannel(
      id: 131,
      name: "Sky Sports Premier League",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-131.php",
      directStreamUrl: "https://raycom-accdn-firetv.amagi.tv/playlist.m3u8",
      description: "Dedicated 24/7 English Premier League coverage with live matches, tactics, and post-game breakdown.",
    ),
    const LiveChannel(
      id: 65,
      name: "TNT Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-65.php",
      directStreamUrl: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8",
      description: "UEFA Champions League, UEFA Europa League, Serie A, Gallagher Premiership Rugby, and UFC fighting.",
    ),
    const LiveChannel(
      id: 44,
      name: "ESPN Live",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-44.php",
      directStreamUrl: "https://raycom-accdn-firetv.amagi.tv/playlist.m3u8",
      description: "The worldwide leader in sports: NFL Monday Night Football, NBA, SportsCenter, and live college football.",
    ),
    const LiveChannel(
      id: 45,
      name: "ESPN 2",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-45.php",
      directStreamUrl: "https://30a-tv.com/feeds/vidaa/golf.m3u8",
      description: "ESPN2 simulcasts, live collegiate sports tournaments, MLB games, and sports analysis.",
    ),
    const LiveChannel(
      id: 35,
      name: "Fox Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-35.php",
      directStreamUrl: "https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8",
      description: "Live MLS soccer, FIFA World Cup qualifiers, college athletics, and automotive racing.",
    ),
    const LiveChannel(
      id: 327,
      name: "beIN Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-327.php",
      directStreamUrl: "https://raycom-accdn-firetv.amagi.tv/playlist.m3u8",
      description: "Top-tier international football, Ligue 1, Copa Libertadores, tennis grand slams, and motorsport.",
    ),

    // -------------------------------------------------------------
    // NEWS
    // -------------------------------------------------------------
    const LiveChannel(
      id: "dw-news",
      name: "DW News HD",
      category: "News",
      streamUrl: "https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8",
      directStreamUrl: "https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8",
      description: "Global 24/7 breaking news and international affairs from Deutsche Welle in crystal-clear High Definition.",
    ),
    const LiveChannel(
      id: "30a-news",
      name: "30A Global News",
      category: "News",
      streamUrl: "https://30a-tv.com/ln.m3u8",
      directStreamUrl: "https://30a-tv.com/ln.m3u8",
      description: "Continuous 24-hour news network reporting on political developments, global stories, and daily reports.",
    ),
    const LiveChannel(
      id: 51,
      name: "CNN News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-51.php",
      directStreamUrl: "https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8",
      description: "CNN breaking news coverage, round-the-clock political reporting, and special investigations.",
    ),
    const LiveChannel(
      id: 81,
      name: "BBC News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-81.php",
      directStreamUrl: "https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8",
      description: "The world's newsroom: British Broadcasting Corporation international news, finance, and global reporting.",
    ),
    const LiveChannel(
      id: 78,
      name: "Sky News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-78.php",
      directStreamUrl: "https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8",
      description: "Sky News 24/7 rolling news channel with first-to-the-scene reporting and live press conferences.",
    ),
    const LiveChannel(
      id: 50,
      name: "Fox News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-50.php",
      directStreamUrl: "https://30a-tv.com/ln.m3u8",
      description: "Fox News Channel live coverage of US political affairs, opinion panels, and global affairs.",
    ),

    // -------------------------------------------------------------
    // MOVIES
    // -------------------------------------------------------------
    const LiveChannel(
      id: 332,
      name: "HBO Cinema",
      category: "Movies",
      streamUrl: "https://dlhd.pk/stream/stream-332.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "Premiere Hollywood feature films, blockbuster releases, and award-winning cinematic masterpieces.",
    ),
    const LiveChannel(
      id: 333,
      name: "HBO 2",
      category: "Movies",
      streamUrl: "https://dlhd.pk/stream/stream-333.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "HBO secondary movie channel broadcasting comedies, dramas, sci-fi, and box office hits.",
    ),
    const LiveChannel(
      id: "30a-hollywood",
      name: "Hollywood Review TV",
      category: "Movies",
      streamUrl: "https://30a-tv.com/gh.m3u8",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "Behind-the-scenes Hollywood filmmaking, red-carpet interviews, movie highlights, and cinema reviews.",
    ),

    // -------------------------------------------------------------
    // ENTERTAINMENT
    // -------------------------------------------------------------
    const LiveChannel(
      id: 339,
      name: "AMC Series",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-339.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "American Movie Classics presenting world-class original dramas, thrillers, and series broadcasts.",
    ),
    const LiveChannel(
      id: 340,
      name: "FX Network",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-340.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "Critically acclaimed prestige television, award-winning drama series, and comedy specials.",
    ),
    const LiveChannel(
      id: 614,
      name: "Comedy Central",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-614.php",
      directStreamUrl: "https://30a-tv.com/ln.m3u8",
      description: "The home of comedy: hilarious stand-up specials, animated comedy, and late-night satire.",
    ),

    // -------------------------------------------------------------
    // KIDS & ANIMATION
    // -------------------------------------------------------------
    const LiveChannel(
      id: 360,
      name: "Cartoon Network",
      category: "Kids",
      streamUrl: "https://dlhd.pk/stream/stream-360.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "Beloved animated hits, adventure cartoons, and children's entertainment broadcasting all day.",
    ),
    const LiveChannel(
      id: 361,
      name: "Nickelodeon",
      category: "Kids",
      streamUrl: "https://dlhd.pk/stream/stream-361.php",
      directStreamUrl: "https://30a-tv.com/gh.m3u8",
      description: "Fun family programming, live-action kid shows, animated stories, and laughter for all ages.",
    ),

    // -------------------------------------------------------------
    // DOCUMENTARY & SCIENCE
    // -------------------------------------------------------------
    const LiveChannel(
      id: "nasa-tv",
      name: "NASA TV HD",
      category: "Documentary",
      streamUrl: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8",
      directStreamUrl: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8",
      description: "Live views of planet Earth from the International Space Station, rocket launches, spacewalks, and deep space astronomy.",
    ),
    const LiveChannel(
      id: "30a-ocean",
      name: "Ocean & Offshore TV",
      category: "Documentary",
      streamUrl: "https://30a-tv.com/darcizzle.m3u8",
      directStreamUrl: "https://30a-tv.com/darcizzle.m3u8",
      description: "Ocean expeditions, marine wildlife documentaries, coastal exploration, and deep-sea diving adventures.",
    ),
    const LiveChannel(
      id: 320,
      name: "Discovery Channel",
      category: "Documentary",
      streamUrl: "https://dlhd.pk/stream/stream-320.php",
      directStreamUrl: "https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8",
      description: "Exploring science, history, nature, wildlife survival, and groundbreaking engineering achievements.",
    ),
    const LiveChannel(
      id: 321,
      name: "National Geographic",
      category: "Documentary",
      streamUrl: "https://dlhd.pk/stream/stream-321.php",
      directStreamUrl: "https://30a-tv.com/darcizzle.m3u8",
      description: "Inspiring people to care about the planet: natural history, ancient civilizations, exploration, and photography.",
    ),
  ];
}
