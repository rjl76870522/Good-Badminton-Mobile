import 'dart:convert';

import '../models/venue.dart';

class VenueQrException implements Exception {
  const VenueQrException(this.message);

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

  Future<List<VenueVideo>> getVideos(String venueId) async {
    // 第一阶段仅使用 Mock 数据；后续在此接入球馆视频库接口。
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
