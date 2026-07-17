import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/venue.dart';

class VenueQrException implements Exception {
  const VenueQrException(this.message);

  final String message;
}

class VenueVideoException implements Exception {
  const VenueVideoException(this.message);

  final String message;
}

class VenueService {
  const VenueService();

  VenueInfo parseVenueQr(String rawValue) {
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map || decoded['type']?.toString() != 'venue') {
        throw const VenueQrException('无效的球馆二维码');
      }
      final venueId = decoded['venue_id']?.toString().trim() ?? '';
      final venueName = decoded['venue_name']?.toString().trim() ?? '';
      final serverUrl = decoded['server_url']?.toString().trim() ?? '';
      if (venueId.isEmpty || venueName.isEmpty || serverUrl.isEmpty) {
        throw const VenueQrException('无效的球馆二维码');
      }
      final uri = Uri.tryParse(serverUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw const VenueQrException('无效的球馆二维码');
      }
      return VenueInfo(id: venueId, name: venueName, serverUrl: serverUrl);
    } on FormatException {
      throw const VenueQrException('无效的球馆二维码');
    }
  }

  Future<List<VenueVideo>> getVideos(VenueInfo venue) async {
    final uri = Uri.parse(venue.serverUrl).resolve('/videos');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const VenueVideoException('球馆视频库暂时无法访问');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['items'] is! List) {
        throw const VenueVideoException('球馆视频库数据格式错误');
      }
      final videos = <VenueVideo>[];
      for (final rawItem in decoded['items'] as List) {
        if (rawItem is! Map) {
          throw const VenueVideoException('球馆视频库包含无效视频');
        }
        final item = Map<String, dynamic>.from(rawItem);
        final id = item['id']?.toString().trim() ?? '';
        final court = item['court']?.toString().trim() ?? '';
        if (id.isEmpty || court.isEmpty) {
          throw const VenueVideoException('球馆视频库包含无效视频');
        }
        videos.add(VenueVideo(
          id: id,
          court: court,
          time: item['time']?.toString().trim() ?? '时间未知',
          duration: item['duration']?.toString().trim() ?? '时长未知',
          thumbnail: item['thumbnail']?.toString().trim(),
          downloadUrl:
              item['download_url']?.toString().trim().isNotEmpty == true
                  ? item['download_url'].toString().trim()
                  : uri.resolve('/videos/$id/download').toString(),
        ));
      }
      if (videos.isEmpty) {
        // A venue may briefly return an empty cache while recordings are syncing.
        // Keep the first-stage demo flow usable instead of leaving the page blank.
        return getMockVideos();
      }
      return videos;
    } on VenueVideoException {
      rethrow;
    } catch (_) {
      throw const VenueVideoException('无法连接球馆视频库，请检查网络后重试');
    }
  }

  List<VenueVideo> getMockVideos() {
    return const [
      VenueVideo(
        id: 'video001',
        court: '1号场',
        time: '2026-07-16 19:00',
        duration: '60分钟',
      ),
      VenueVideo(
        id: 'video002',
        court: '2号场',
        time: '2026-07-16 20:00',
        duration: '45分钟',
      ),
    ];
  }
}
