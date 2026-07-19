import 'package:flutter/material.dart';

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

  Future<void> _launch(MapApp app) async {
    setState(() => _launching = app);
    final launched = await _mapLauncher.launchNearbyBadminton(app);
    if (!mounted) return;
    setState(() => _launching = null);
    if (launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有找到可打开的地图服务，请检查应用或网络')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('导航'),
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
            ],
          ),
        ),
      ),
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
