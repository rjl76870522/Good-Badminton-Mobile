import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/venue.dart';

/// Stores only small pieces of local UI state for the venue library.
/// Videos themselves remain on the venue server or in the system gallery.
class VenueLibraryStorage {
  static const _favoritesKey = 'venue_video_favorites_v1';
  static const _recentKey = 'venue_video_recent_v1';
  static const _clipsKey = 'venue_video_saved_clips_v1';

  String keyFor(VenueInfo venue, VenueVideo video) =>
      '${venue.serverUrl}|${video.id}';

  Future<Set<String>> favoriteKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? const []).toSet();
  }

  Future<bool> toggleFavorite(VenueInfo venue, VenueVideo video) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await favoriteKeys();
    final key = keyFor(venue, video);
    final nowFavorite = !keys.remove(key);
    if (nowFavorite) keys.add(key);
    await prefs.setStringList(_favoritesKey, keys.toList()..sort());
    return nowFavorite;
  }

  Future<List<String>> recentKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? const [];
  }

  Future<void> addRecent(VenueInfo venue, VenueVideo video) async {
    final prefs = await SharedPreferences.getInstance();
    final key = keyFor(venue, video);
    final values = (prefs.getStringList(_recentKey) ?? const [])
        .where((value) => value != key)
        .toList()
      ..insert(0, key);
    await prefs.setStringList(_recentKey, values.take(20).toList());
  }

  Future<List<SavedVenueClip>> clipsFor(
      VenueInfo venue, VenueVideo video) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final key = keyFor(venue, video);
      final clips = decoded
          .whereType<Map>()
          .map((item) => SavedVenueClip.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((clip) => clip.videoKey == key)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return clips;
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveClip({
    required VenueInfo venue,
    required VenueVideo video,
    required String name,
    required int startMs,
    required int endMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clipsKey);
    final values = <SavedVenueClip>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          values.addAll(decoded.whereType<Map>().map(
                (item) => SavedVenueClip.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ));
        }
      } on FormatException {
        // A corrupted local preference should not block a newly saved clip.
      }
    }
    values.insert(
      0,
      SavedVenueClip(
        videoKey: keyFor(venue, video),
        name: name.trim().isEmpty ? '未命名片段' : name.trim(),
        startMs: startMs,
        endMs: endMs,
        createdAt: DateTime.now(),
      ),
    );
    await prefs.setString(
      _clipsKey,
      jsonEncode(values.take(100).map((clip) => clip.toJson()).toList()),
    );
  }
}

class SavedVenueClip {
  const SavedVenueClip({
    required this.videoKey,
    required this.name,
    required this.startMs,
    required this.endMs,
    required this.createdAt,
  });

  final String videoKey;
  final String name;
  final int startMs;
  final int endMs;
  final DateTime createdAt;

  factory SavedVenueClip.fromJson(Map<String, dynamic> json) => SavedVenueClip(
        videoKey: json['video_key']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名片段',
        startMs: int.tryParse(json['start_ms']?.toString() ?? '') ?? 0,
        endMs: int.tryParse(json['end_ms']?.toString() ?? '') ?? 0,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'video_key': videoKey,
        'name': name,
        'start_ms': startMs,
        'end_ms': endMs,
        'created_at': createdAt.toIso8601String(),
      };
}
