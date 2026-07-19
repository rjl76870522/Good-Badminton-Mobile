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

  Future<bool> launchNearbyBadminton(MapApp app) async {
    switch (app) {
      case MapApp.amap:
        return _launchFirstAvailable([
          if (Platform.isIOS)
            Uri(
              scheme: 'iosamap',
              host: 'poi',
              queryParameters: const {
                'sourceApplication': 'good-badminton',
                'keywords': _keyword,
                'dev': '0',
              },
            )
          else
            Uri(
              scheme: 'androidamap',
              host: 'poi',
              queryParameters: const {
                'sourceApplication': 'good-badminton',
                'keywords': _keyword,
                'dev': '0',
              },
            ),
          Uri.https('uri.amap.com', '/search', {
            'keyword': _keyword,
            'callnative': '1',
          }),
        ]);
      case MapApp.baidu:
        return _launchFirstAvailable([
          Uri(
            scheme: 'baidumap',
            host: 'map',
            path: '/place/search',
            queryParameters: const {
              'query': _keyword,
              'region': '全国',
              'src': 'good-badminton',
            },
          ),
          Uri.https('map.baidu.com', '/search/$_keyword'),
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
          if (Platform.isAndroid) Uri.parse('geo:0,0?q=$_keyword'),
          Uri.https('uri.amap.com', '/search', {'keyword': _keyword}),
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
