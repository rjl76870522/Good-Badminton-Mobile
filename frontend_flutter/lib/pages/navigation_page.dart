import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/map_launcher_service.dart';
import '../widgets/app_background.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  final MapLauncherService _mapLauncher = const MapLauncherService();
  MapApp? _launching;
  String? _launchingVenue;
  Position? _position;
  bool _locating = false;
  String? _locationMessage;

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('请先开启手机定位服务');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('未获得定位权限，可到系统设置中开启');
      }
      Position? position = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: Platform.isAndroid,
      );
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  forceLocationManager: true,
                  timeLimit: Duration(seconds: 25),
                )
              : AppleSettings(
                  accuracy: LocationAccuracy.best,
                  timeLimit: Duration(seconds: 20),
                ),
        );
      } on TimeoutException {
        if (position == null) {
          throw StateError('暂时无法获得位置，请到开阔处开启定位后重试');
        }
      }
      if (!mounted) return;
      setState(() {
        _position = position;
        _locationMessage = '已定位，将优先搜索当前位置附近的场馆';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _launch(MapApp app) async {
    setState(() => _launching = app);
    final launched = await _mapLauncher.launchNearbyBadminton(
      app,
      latitude: _position?.latitude,
      longitude: _position?.longitude,
    );
    if (!mounted) return;
    setState(() => _launching = null);
    if (launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有找到可打开的地图服务，请检查应用或网络')),
    );
  }

  Future<void> _launchVenue(String keyword, MapApp app) async {
    final launchKey = '${app.name}:$keyword';
    setState(() => _launchingVenue = launchKey);
    final launched = app == MapApp.baidu
        ? await _mapLauncher.launchBaiduPlace(keyword)
        : await _mapLauncher.launchAmapPlace(keyword);
    if (!mounted) return;
    setState(() => _launchingVenue = null);
    if (launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂时无法打开地图，请检查应用或网络')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('发现'),
        backgroundColor: Colors.transparent,
      ),
      body: AppBackground(
        imageAsset: 'assets/images/history_court_bg.png',
        imageOpacity: 0.1,
        alignment: const Alignment(0.15, -0.2),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF174B2A),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.sports_tennis_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '附近羽毛球馆',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '选择常用服务，查找距离合适的场馆并开始导航',
                            style: TextStyle(
                              color: Color(0xDFFFFFFF),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.my_location_outlined),
                  title: Text(_position == null ? '定位当前位置' : '当前位置已启用'),
                  subtitle:
                      _locationMessage == null ? null : Text(_locationMessage!),
                  trailing: _locating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: '定位',
                          onPressed: _locate,
                          icon: const Icon(Icons.gps_fixed),
                        ),
                  onTap: _locating ? null : _locate,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '选择服务',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              _NavigationOption(
                icon: Icons.map_outlined,
                title: '高德地图',
                subtitle: '搜索附近场馆并规划路线',
                color: const Color(0xFFE6F4FF),
                loading: _launching == MapApp.amap,
                onTap: () => _launch(MapApp.amap),
              ),
              const SizedBox(height: 10),
              _NavigationOption(
                icon: Icons.explore_outlined,
                title: '百度地图',
                subtitle: '查看场馆位置和出行路线',
                color: const Color(0xFFEAF0FF),
                loading: _launching == MapApp.baidu,
                onTap: () => _launch(MapApp.baidu),
              ),
              const SizedBox(height: 10),
              _NavigationOption(
                icon: Icons.storefront_outlined,
                title: '美团',
                subtitle: '查看场馆营业信息和预订服务',
                color: const Color(0xFFFFF6D9),
                loading: _launching == MapApp.meituan,
                onTap: () => _launch(MapApp.meituan),
              ),
              const SizedBox(height: 10),
              _NavigationOption(
                icon: Icons.public_outlined,
                title: '浏览器搜索',
                subtitle: '未安装地图应用时继续查找',
                color: const Color(0xFFE9F7EA),
                loading: _launching == MapApp.browser,
                onTap: () => _launch(MapApp.browser),
              ),
              const SizedBox(height: 24),
              Text(
                '校园场馆示例',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '校内场馆通常需要校园身份或提前预约，开放安排以学校当天通知为准',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              _VenueExampleCard(
                city: '沈阳',
                title: '东北大学南湖校区羽乒馆',
                address: '辽宁省沈阳市和平区文化路三号巷11号',
                details: '南湖校区内场馆，学校羽毛球赛事常用场地\n'
                    '师生开放时段及预约方式请查看智慧东大或体育场馆通知',
                launching: _launchingVenue,
                onNavigate: (app) => _launchVenue('东北大学南湖校区羽乒馆', app),
              ),
              const SizedBox(height: 12),
              _VenueExampleCard(
                city: '杭州',
                title: '浙江大学紫金港校区风雨操场',
                address: '浙江省杭州市西湖区余杭塘路866号',
                details: '校内设有10片羽毛球场，适合日常训练和校内比赛\n'
                    '校内用户请通过学校体育场馆预约渠道确认可用时段',
                launching: _launchingVenue,
                onNavigate: (app) => _launchVenue('浙江大学紫金港校区风雨操场', app),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VenueExampleCard extends StatelessWidget {
  const _VenueExampleCard({
    required this.city,
    required this.title,
    required this.address,
    required this.details,
    required this.launching,
    required this.onNavigate,
  });

  final String city;
  final String title;
  final String address;
  final String details;
  final String? launching;
  final ValueChanged<MapApp> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(city),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _VenueInfoLine(icon: Icons.location_on_outlined, text: address),
            const SizedBox(height: 8),
            _VenueInfoLine(icon: Icons.info_outline, text: details),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: launching == null
                        ? () => onNavigate(MapApp.amap)
                        : null,
                    icon: launching == 'amap:$title'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.navigation_outlined),
                    label: const Text('高德地图'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: launching == null
                        ? () => onNavigate(MapApp.baidu)
                        : null,
                    icon: launching == 'baidu:$title'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.map_outlined),
                    label: const Text('百度地图'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VenueInfoLine extends StatelessWidget {
  const _VenueInfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ],
    );
  }
}

class _NavigationOption extends StatelessWidget {
  const _NavigationOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_new_rounded),
        onTap: loading ? null : onTap,
      ),
    );
  }
}
