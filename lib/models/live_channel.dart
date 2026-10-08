class LiveChannel {
  final dynamic id;
  final String name;
  final String category;
  final String streamUrl;

  const LiveChannel({
    required this.id,
    required this.name,
    required this.category,
    required this.streamUrl,
  });
}

class LiveData {
  static const List<String> categories = [
    "All",
    "Sports",
    "News",
    "Entertainment",
    "Movies",
    "Kids",
    "Documentary",
  ];

  static final List<LiveChannel> channels = [
    const LiveChannel(
      id: 130,
      name: "Sky Sports Main Event",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-130.php",
    ),
    const LiveChannel(
      id: 131,
      name: "Sky Sports Premier League",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-131.php",
    ),
    const LiveChannel(
      id: 65,
      name: "TNT Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-65.php",
    ),
    const LiveChannel(
      id: 44,
      name: "ESPN",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-44.php",
    ),
    const LiveChannel(
      id: 45,
      name: "ESPN 2",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-45.php",
    ),
    const LiveChannel(
      id: 35,
      name: "Fox Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-35.php",
    ),
    const LiveChannel(
      id: 327,
      name: "beIN Sports 1",
      category: "Sports",
      streamUrl: "https://dlhd.pk/stream/stream-327.php",
    ),
    const LiveChannel(
      id: 51,
      name: "CNN News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-51.php",
    ),
    const LiveChannel(
      id: 81,
      name: "BBC News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-81.php",
    ),
    const LiveChannel(
      id: 78,
      name: "Sky News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-78.php",
    ),
    const LiveChannel(
      id: 50,
      name: "Fox News",
      category: "News",
      streamUrl: "https://dlhd.pk/stream/stream-50.php",
    ),
    const LiveChannel(
      id: 332,
      name: "HBO Cinema",
      category: "Movies",
      streamUrl: "https://dlhd.pk/stream/stream-332.php",
    ),
    const LiveChannel(
      id: 333,
      name: "HBO 2",
      category: "Movies",
      streamUrl: "https://dlhd.pk/stream/stream-333.php",
    ),
    const LiveChannel(
      id: 339,
      name: "AMC Series",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-339.php",
    ),
    const LiveChannel(
      id: 340,
      name: "FX Network",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-340.php",
    ),
    const LiveChannel(
      id: 614,
      name: "Comedy Central",
      category: "Entertainment",
      streamUrl: "https://dlhd.pk/stream/stream-614.php",
    ),
    const LiveChannel(
      id: 360,
      name: "Cartoon Network",
      category: "Kids",
      streamUrl: "https://dlhd.pk/stream/stream-360.php",
    ),
    const LiveChannel(
      id: 361,
      name: "Nickelodeon",
      category: "Kids",
      streamUrl: "https://dlhd.pk/stream/stream-361.php",
    ),
    const LiveChannel(
      id: 320,
      name: "Discovery Channel",
      category: "Documentary",
      streamUrl: "https://dlhd.pk/stream/stream-320.php",
    ),
    const LiveChannel(
      id: 321,
      name: "National Geographic",
      category: "Documentary",
      streamUrl: "https://dlhd.pk/stream/stream-321.php",
    ),
  ];
}
