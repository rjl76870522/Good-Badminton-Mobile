class VenueInfo {
  const VenueInfo({
    required this.id,
    required this.name,
    required this.serverUrl,
  });

  final String id;
  final String name;
  final String serverUrl;
}

class VenueVideo {
  const VenueVideo({
    required this.id,
    required this.court,
    required this.time,
    required this.duration,
    this.thumbnail,
    this.downloadUrl,
  });

  final String id;
  final String court;
  final String time;
  final String duration;
  final String? thumbnail;
  final String? downloadUrl;
}
