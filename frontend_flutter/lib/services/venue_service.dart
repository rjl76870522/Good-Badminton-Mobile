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
    final value = rawValue.trim();
    if (value.isEmpty) {
      throw const VenueQrException('二维码内容为空');
    }

    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return _venueFromMap(Map<String, dynamic>.from(decoded));
      }
    } on FormatException {
      // Many venue QR codes are URLs instead of JSON payloads.
    } on VenueQrException {
      rethrow;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const VenueQrException('无效的球馆二维码');
    }
    if (uri.queryParameters.isNotEmpty) {
      return _venueFromQuery(uri);
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _venueFromPlainServerUrl(uri);
    }

    throw const VenueQrException('无效的球馆二维码');
  }

  VenueInfo _venueFromMap(Map<String, dynamic> decoded) {
    final type = decoded['type']?.toString().trim().toLowerCase();
    if (type != null && type.isNotEmpty && type != 'venue') {
      throw const VenueQrException('无效的球馆二维码');
    }
    final serverUrl = _firstNonEmpty(decoded, const [
      'server_url',
      'serverUrl',
      'url',
      'base_url',
      'baseUrl',
    ]);
    return _buildVenue(
      id: _firstNonEmpty(decoded, const ['venue_id', 'venueId', 'id']),
      name: _firstNonEmpty(decoded, const [
        'venue_name',
        'venueName',
        'name',
        'title',
      ]),
      serverUrl: serverUrl,
    );
  }

  VenueInfo _venueFromQuery(Uri uri) {
    final params = uri.queryParameters;
    final serverUrl = _firstNonEmpty(params, const [
      'server_url',
      'serverUrl',
      'url',
      'base_url',
      'baseUrl',
      'server',
    ]);
    if (serverUrl.isNotEmpty) {
      return _buildVenue(
        id: _firstNonEmpty(params, const ['venue_id', 'venueId', 'id']),
        name: _firstNonEmpty(params, const [
          'venue_name',
          'venueName',
          'name',
          'title',
        ]),
        serverUrl: serverUrl,
        fallbackId: uri.host,
        fallbackName: uri.host,
      );
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _venueFromPlainServerUrl(uri);
    }
    throw const VenueQrException('球馆二维码缺少视频库地址');
  }

  VenueInfo _venueFromPlainServerUrl(Uri uri) {
    final serverUri = uri.replace(query: null, fragment: null);
    return _buildVenue(
      id: uri.host,
      name: uri.host,
      serverUrl: serverUri.toString(),
    );
  }

  VenueInfo _buildVenue({
    required String id,
    required String name,
    required String serverUrl,
    String? fallbackId,
    String? fallbackName,
  }) {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    final venueId = id.trim().isNotEmpty
        ? id.trim()
        : fallbackId?.trim().isNotEmpty == true
            ? fallbackId!.trim()
            : Uri.parse(normalizedServerUrl).host;
    final venueName = name.trim().isNotEmpty
        ? name.trim()
        : fallbackName?.trim().isNotEmpty == true
            ? fallbackName!.trim()
            : venueId;
    return VenueInfo(
      id: venueId,
      name: venueName,
      serverUrl: normalizedServerUrl,
    );
  }

  String _normalizeServerUrl(String serverUrl) {
    final value = serverUrl.trim();
    if (value.isEmpty) {
      throw const VenueQrException('球馆二维码缺少视频库地址');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const VenueQrException('球馆视频库地址无效');
    }
    return uri.replace(query: null, fragment: null).toString();
  }

  String _firstNonEmpty(Map<dynamic, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Future<List<VenueVideo>> getVideos(VenueInfo venue) async {
    final uri = _endpoint(venue.serverUrl, 'videos');
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
        final id = (item['id'] ?? item['video_id'])?.toString().trim() ?? '';
        final court =
            (item['court_name'] ?? item['court'])?.toString().trim() ?? '';
        final revision = item['revision']?.toString().trim() ?? '';
        if (id.isEmpty || court.isEmpty) {
          throw const VenueVideoException('球馆视频库包含无效视频');
        }
        videos.add(VenueVideo(
          id: id,
          court: court,
          time:
              (item['timestamp'] ?? item['time'])?.toString().trim() ?? '时间未知',
          duration: item['duration']?.toString().trim() ?? '时长未知',
          thumbnail: item['thumbnail']?.toString().trim(),
          downloadUrl: (item['video_url'] ?? item['download_url'])
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true
              ? (item['video_url'] ?? item['download_url']).toString().trim()
              : _endpoint(
                  venue.serverUrl,
                  'videos/$id/download',
                )
                  .replace(
                    queryParameters: revision.isEmpty
                        ? null
                        : <String, String>{'v': revision},
                  )
                  .toString(),
          isPreparedClip: item['is_prepared_clip'] == true,
          isFavorite: item['is_favorite'] == true,
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

  Uri _endpoint(String serverUrl, String relativePath) {
    final base = Uri.parse(serverUrl);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    final child =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;
    return base.replace(path: '$basePath$child', query: null, fragment: null);
  }

  List<VenueVideo> getMockVideos() {
    return const [
      VenueVideo(
        id: 'example-court1-demo01',
        court: '1号场',
        time: '球馆录像片段 01',
        duration: '8秒',
        assetPath: 'assets/videos/demo01.mp4',
        isPreparedClip: true,
      ),
      VenueVideo(
        id: 'example-court2-demo02',
        court: '2号场',
        time: '球馆录像片段 02',
        duration: '11秒',
        assetPath: 'assets/videos/demo02.mp4',
        isPreparedClip: true,
      ),
    ];
  }
}
