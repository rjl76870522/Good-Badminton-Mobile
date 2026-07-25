import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/map_launcher_service.dart';
import '../services/wallpaper_storage.dart';
import '../widgets/app_background.dart';
import 'badminton_knowledge_page.dart';

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
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: const GlassAppBarBackdrop(),
      ),
      body: AppBackground(
        wallpaperTarget: WallpaperTarget.discover,
        imageAsset: 'assets/images/history_court_bg.png',
        imageOpacity: 0.06,
        alignment: const Alignment(0.15, -0.2),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            key: const ValueKey('discover-list'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              _NearbyVenuePanel(
                positionAvailable: _position != null,
                locating: _locating,
                locationMessage: _locationMessage,
                launching: _launching,
                onLocate: _locate,
                onLaunch: _launch,
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

class KnowledgeModules extends StatelessWidget {
  const KnowledgeModules({super.key});

  static final _newsUri = Uri.parse('https://www.badmintoncn.com/');

  Future<void> _openNews(BuildContext context) async {
    final opened = await launchUrl(
      _newsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法打开羽球资讯')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const modules = <({
      KnowledgeSection section,
      IconData icon,
      String title,
      String subtitle,
    })>[
      (
        section: KnowledgeSection.calendar,
        icon: Icons.calendar_month_outlined,
        title: '大赛日历',
        subtitle: '赛事级别与观赛安排',
      ),
      (
        section: KnowledgeSection.rankings,
        icon: Icons.leaderboard_outlined,
        title: '世界排名',
        subtitle: '五个项目与积分规则',
      ),
      (
        section: KnowledgeSection.players,
        icon: Icons.person_search_outlined,
        title: '球星资料',
        subtitle: '打法特点与观察重点',
      ),
      (
        section: KnowledgeSection.equipment,
        icon: Icons.sports_tennis_outlined,
        title: '装备库',
        subtitle: '球拍、球鞋和用球选择',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '羽球内容',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '无需离开应用，快速了解赛事、球员与装备',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: modules.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 122,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final module = modules[index];
            return _PressScaleCard(
              key: ValueKey('community-card-${module.section.name}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BadmintonKnowledgePage(
                    initialSection: module.section,
                  ),
                ),
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x142E7D32),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          module.icon,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        module.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        module.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _PressScaleCard(
          key: const ValueKey('community-card-news'),
          onTap: () => _openNews(context),
          child: Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.newspaper_outlined),
              ),
              title: const Text(
                '近期赛事与球星新闻',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                '前往中羽在线查看最新羽球资讯',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              trailing: const Icon(Icons.open_in_new),
            ),
          ),
        ),
      ],
    );
  }
}

class _PressScaleCard extends StatefulWidget {
  const _PressScaleCard({
    super.key,
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScaleCard> createState() => _PressScaleCardState();
}

class _PressScaleCardState extends State<_PressScaleCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: widget.child,
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
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    city,
                    style: const TextStyle(
                      color: Color(0xFFC2410C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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

class _NearbyVenuePanel extends StatelessWidget {
  const _NearbyVenuePanel({
    required this.positionAvailable,
    required this.locating,
    required this.locationMessage,
    required this.launching,
    required this.onLocate,
    required this.onLaunch,
  });

  final bool positionAvailable;
  final bool locating;
  final String? locationMessage;
  final MapApp? launching;
  final VoidCallback onLocate;
  final ValueChanged<MapApp> onLaunch;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFF0FDF4)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8E8DA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x142E7D32),
              blurRadius: 24,
              spreadRadius: 1,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.location_on_outlined,
                        color: Color(0xFF2E7D32)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '附近羽毛球馆',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          positionAvailable ? '已定位，可选择地图开始导航' : '定位后优先查找附近场馆',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF6B7280),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (locationMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F8F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(locationMessage!,
                      style: const TextStyle(height: 1.35)),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: locating ? null : onLocate,
                  icon: locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(locating ? '正在定位…' : '定位并导航'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Text(
                '选择地图服务',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.35,
                children: [
                  _MapServiceButton(
                    icon: Icons.map_outlined,
                    label: '高德地图',
                    backgroundColor: const Color(0xFFEAF4FF),
                    iconColor: const Color(0xFF2563EB),
                    loading: launching == MapApp.amap,
                    onTap: () => onLaunch(MapApp.amap),
                  ),
                  _MapServiceButton(
                    icon: Icons.explore_outlined,
                    label: '百度地图',
                    backgroundColor: const Color(0xFFFFEEEE),
                    iconColor: const Color(0xFFDC2626),
                    loading: launching == MapApp.baidu,
                    onTap: () => onLaunch(MapApp.baidu),
                  ),
                  _MapServiceButton(
                    icon: Icons.storefront_outlined,
                    label: '美团',
                    backgroundColor: const Color(0xFFFFF8D9),
                    iconColor: const Color(0xFFB45309),
                    loading: launching == MapApp.meituan,
                    onTap: () => onLaunch(MapApp.meituan),
                  ),
                  _MapServiceButton(
                    icon: Icons.public_outlined,
                    label: '浏览器搜索',
                    backgroundColor: const Color(0xFFE9F7EA),
                    iconColor: const Color(0xFF2E7D32),
                    loading: launching == MapApp.browser,
                    onTap: () => onLaunch(MapApp.browser),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapServiceButton extends StatelessWidget {
  const _MapServiceButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.iconColor,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color iconColor;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
