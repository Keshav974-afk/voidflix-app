class SportsStream {
  final String id;
  final String type; // 'hls', 'dash', 'embed'
  final String label;
  final String url;
  final bool isDirect;
  final String? manifest;
  final String? keyId;
  final String? key;
  final Map<String, String>? headers;

  const SportsStream({
    required this.id,
    required this.type,
    required this.label,
    required this.url,
    this.isDirect = true,
    this.manifest,
    this.keyId,
    this.key,
    this.headers,
  });

  factory SportsStream.fromJson(Map<String, dynamic> json) {
    return SportsStream(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'hls',
      label: json['label']?.toString() ?? 'Live Stream',
      url: json['url']?.toString() ?? '',
      isDirect: json['isDirect'] == true,
      manifest: json['manifest']?.toString(),
      keyId: json['keyId']?.toString(),
      key: json['key']?.toString(),
      headers: json['headers'] is Map
          ? (json['headers'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        'url': url,
        'isDirect': isDirect,
        if (manifest != null) 'manifest': manifest,
        if (keyId != null) 'keyId': keyId,
        if (key != null) 'key': key,
        if (headers != null) 'headers': headers,
      };
}

class SportsMatch {
  final String id;
  final String slug;
  final String title;
  final String sport;
  final String category;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamLogo;
  final String awayTeamLogo;
  final String thumbnail;
  final DateTime startDateTime;
  final int durationMinutes;
  final bool isLive;
  final List<SportsStream> streams;

  const SportsMatch({
    required this.id,
    required this.slug,
    required this.title,
    required this.sport,
    required this.category,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamLogo = '',
    this.awayTeamLogo = '',
    this.thumbnail = '',
    required this.startDateTime,
    this.durationMinutes = 180,
    this.isLive = false,
    this.streams = const [],
  });

  factory SportsMatch.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['startDateTime']?.toString() ?? '');
    } catch (_) {
      parsedDate = DateTime.now();
    }

    final rawStreams = json['streams'] as List<dynamic>? ?? [];
    final streamsList = rawStreams
        .whereType<Map<String, dynamic>>()
        .map((s) => SportsStream.fromJson(s))
        .toList();

    return SportsMatch(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Live Match',
      sport: json['sport']?.toString() ?? 'Sports',
      category: json['category']?.toString() ?? 'Tournament',
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      homeTeamLogo: json['homeTeamLogo']?.toString() ?? '',
      awayTeamLogo: json['awayTeamLogo']?.toString() ?? '',
      thumbnail: json['thumbnail']?.toString() ?? '',
      startDateTime: parsedDate,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 180,
      isLive: json['isLive'] == true,
      streams: streamsList,
    );
  }

  String get formattedStatus {
    final now = DateTime.now();
    final end = startDateTime.add(Duration(minutes: durationMinutes));
    if (now.isAfter(startDateTime) && now.isBefore(end)) {
      return 'LIVE NOW';
    } else if (now.isBefore(startDateTime)) {
      final diff = startDateTime.difference(now);
      if (diff.inDays > 0) return 'Starts in ${diff.inDays}d';
      if (diff.inHours > 0) return 'Starts in ${diff.inHours}h ${diff.inMinutes % 60}m';
      return 'Starts in ${diff.inMinutes}m';
    } else {
      return 'Completed';
    }
  }
}
