import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

enum MapApp {
  amap,
  baidu,
  meituan,
  browser,
}

class MapLauncherService {
  const MapLauncherService();

  static const _keyword = '羽毛球馆';

  Future<bool> launchAmapPlace(String keyword) {
    return _launchFirstAvailable([
      if (Platform.isIOS)
        Uri(
          scheme: 'iosamap',
          host: 'poi',
          queryParameters: {
            'sourceApplication': 'good-badminton',
            'keywords': keyword,
            'dev': '0',
          },
        )
      else
        Uri(
          scheme: 'androidamap',
          host: 'poi',
          queryParameters: {
            'sourceApplication': 'good-badminton',
            'keywords': keyword,
            'dev': '0',
          },
        ),
      Uri.https('uri.amap.com', '/search', {
        'keyword': keyword,
        'callnative': '1',
      }),
    ]);
  }

  Future<bool> launchBaiduPlace(String keyword) {
    return _launchFirstAvailable([
      Uri(
        scheme: 'baidumap',
        host: 'map',
        path: '/place/search',
        queryParameters: {
          'query': keyword,
          'region': '全国',
          'src': 'good-badminton',
        },
      ),
      Uri.https('map.baidu.com', '/search/$keyword'),
    ]);
  }

  Future<bool> launchNearbyBadminton(
    MapApp app, {
    double? latitude,
    double? longitude,
  }) async {
    final location = latitude == null || longitude == null
        ? null
        : '${longitude.toStringAsFixed(6)},${latitude.toStringAsFixed(6)}';
    switch (app) {
      case MapApp.amap:
        return _launchFirstAvailable([
          if (Platform.isIOS)
            Uri(
              scheme: 'iosamap',
              host: 'poi',
              queryParameters: {
                'sourceApplication': 'good-badminton',
                'keywords': _keyword,
                'dev': '0',
                if (location != null) 'location': location,
              },
            )
          else
            Uri(
              scheme: 'androidamap',
              host: 'poi',
              queryParameters: {
                'sourceApplication': 'good-badminton',
                'keywords': _keyword,
                'dev': '0',
                if (location != null) 'location': location,
              },
            ),
          Uri.https('uri.amap.com', '/search', {
            'keyword': _keyword,
            if (location != null) 'center': location,
            'callnative': '1',
          }),
        ]);
      case MapApp.baidu:
        return _launchFirstAvailable([
          Uri(
            scheme: 'baidumap',
            host: 'map',
            path: '/place/search',
            queryParameters: {
              'query': _keyword,
              'region': '全国',
              'src': 'good-badminton',
              if (latitude != null && longitude != null)
                'location': '$latitude,$longitude',
            },
          ),
          Uri.https('map.baidu.com', '/search/$_keyword', {
            if (latitude != null && longitude != null)
              'center': '$longitude,$latitude',
          }),
        ]);
      case MapApp.meituan:
        return _launchFirstAvailable([
          Uri(
            scheme: 'imeituan',
            host: 'www.meituan.com',
            path: '/search',
            queryParameters: const {'q': _keyword},
          ),
          Uri.https('www.meituan.com', '/s/$_keyword/'),
        ]);
      case MapApp.browser:
        return _launchFirstAvailable([
          if (Platform.isAndroid)
            Uri.parse(
              'geo:${latitude ?? 0},${longitude ?? 0}?q=$_keyword',
            ),
          Uri.https('uri.amap.com', '/search', {
            'keyword': _keyword,
            if (location != null) 'center': location,
          }),
          Uri.https('map.baidu.com', '/search/$_keyword'),
        ]);
    }
  }

  Future<bool> _launchFirstAvailable(List<Uri> candidates) async {
    for (final uri in candidates) {
      if (!await canLaunchUrl(uri)) continue;
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    }
    return false;
  }
}
