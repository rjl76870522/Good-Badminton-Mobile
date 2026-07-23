import 'package:flutter/foundation.dart';

import '../models/venue.dart';
import '../services/venue_library_storage.dart';
import '../services/venue_service.dart';

/// Frontend-only state and grouping for the digital venue floorplan.
/// It derives every court node and count from [VenueVideo.court], which maps
/// to the API's `court_name` field in [VenueService].
class VenueLibraryViewModel extends ChangeNotifier {
  VenueLibraryViewModel({
    required this.venue,
    required this.service,
    required this.storage,
  });

  final VenueInfo venue;
  final VenueService service;
  final VenueLibraryStorage storage;

  List<VenueVideo> _videos = const [];
  Set<String> _favoriteKeys = const {};
  List<String> _recentKeys = const [];
  String _query = '';
  bool _favoritesOnly = false;
  bool _loading = true;
  String? _error;

  List<VenueVideo> get allVideos => _videos;
  bool get isLoading => _loading;
  String? get error => _error;
  String get query => _query;
  bool get favoritesOnly => _favoritesOnly;

  List<String> get courtNames {
    final names = _videos.map((video) => video.court).toSet().toList();
    names.sort(_courtCompare);
    return names;
  }

  List<String> get floorplanCourts {
    final namedCourts = List<String>.generate(10, (index) => '${index + 1}号场');
    for (final court in courtNames) {
      if (!namedCourts.contains(court)) namedCourts.add(court);
    }
    return namedCourts;
  }

  List<VenueVideo> get filteredVideos => _videos.where((video) {
        final text =
            '${video.court} ${video.time} ${video.duration}'.toLowerCase();
        final matchesQuery =
            _query.isEmpty || text.contains(_query.toLowerCase());
        return matchesQuery && (!_favoritesOnly || isFavorite(video));
      }).toList(growable: false);

  int videoCountFor(String court) =>
      filteredVideos.where((video) => video.court == court).length;

  int allVideoCountFor(String court) =>
      _videos.where((video) => video.court == court).length;

  List<VenueVideo> videosFor(String court) => filteredVideos
      .where((video) => video.court == court)
      .toList(growable: false);

  List<VenueVideo> allVideosFor(String court) =>
      _videos.where((video) => video.court == court).toList(growable: false);

  bool isFavorite(VenueVideo video) =>
      video.isFavorite || _favoriteKeys.contains(storage.keyFor(venue, video));

  bool isRecent(VenueVideo video) =>
      _recentKeys.contains(storage.keyFor(venue, video));

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        service.getVideos(venue),
        storage.favoriteKeys(),
        storage.recentKeys(),
      ]);
      _videos = values[0] as List<VenueVideo>;
      _favoriteKeys = values[1] as Set<String>;
      _recentKeys = values[2] as List<String>;
    } on VenueVideoException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = '视频库暂时无法访问，请稍后重试。';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void showDemoVideos() {
    _videos = service.getMockVideos();
    _error = null;
    _loading = false;
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value.trim();
    notifyListeners();
  }

  void setFavoritesOnly(bool value) {
    _favoritesOnly = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(VenueVideo video) async {
    final favorite = await storage.toggleFavorite(venue, video);
    final key = storage.keyFor(venue, video);
    _favoriteKeys = {..._favoriteKeys};
    if (favorite) {
      _favoriteKeys.add(key);
    } else {
      _favoriteKeys.remove(key);
    }
    notifyListeners();
  }

  Future<void> markOpened(VenueVideo video) async {
    final key = storage.keyFor(venue, video);
    _recentKeys =
        [key, ..._recentKeys.where((item) => item != key)].take(20).toList();
    notifyListeners();
    await storage.addRecent(venue, video);
  }

  static int _courtCompare(String left, String right) {
    final leftNumber =
        int.tryParse(RegExp(r'\d+').firstMatch(left)?.group(0) ?? '');
    final rightNumber =
        int.tryParse(RegExp(r'\d+').firstMatch(right)?.group(0) ?? '');
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return left.compareTo(right);
  }
}
