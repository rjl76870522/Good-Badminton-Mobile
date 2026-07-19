import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/offline_report_storage.dart';
import '../services/user_storage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final _website = Uri.parse('https://www.audacity6441.kdns.fr/');
  static final _privacy = Uri.parse('https://www.audacity6441.kdns.fr/privacy');
  static final _support = Uri.parse('https://www.audacity6441.kdns.fr/support');

  final UserStorage _storage = UserStorage();
  final OfflineReportStorage _offlineStorage = OfflineReportStorage();
  bool _autoPlay = false;
  int _offlineCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoPlay = await _storage.getAutoPlayVideos();
    final records = await _offlineStorage.list();
    if (!mounted) return;
    setState(() {
      _autoPlay = autoPlay;
      _offlineCount = records.length;
    });
  }

  Future<void> _clearOfflineReports() async {
    if (_offlineCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部离线报告？'),
        content: const Text('只删除手机中的离线副本，不会删除训练记录'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _offlineStorage.clearAll();
    await _load();
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsGroup(
            title: '媒体',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.play_circle_outline),
                title: const Text('自动播放报告视频'),
                subtitle: const Text('打开报告时自动开始播放在线视频'),
                value: _autoPlay,
                onChanged: (value) async {
                  await _storage.setAutoPlayVideos(value);
                  if (mounted) setState(() => _autoPlay = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            title: '存储',
            children: [
              ListTile(
                leading: const Icon(Icons.offline_pin_outlined),
                title: const Text('手机离线报告'),
                subtitle: Text('已保存 $_offlineCount 条，不包含分析视频'),
                trailing: TextButton(
                  onPressed: _offlineCount == 0 ? null : _clearOfflineReports,
                  child: const Text('清理'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            title: '权限',
            children: [
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('系统权限管理'),
                subtitle: const Text('管理相机、照片和视频访问权限'),
                trailing: const Icon(Icons.open_in_new),
                onTap: openAppSettings,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: const Text('官方网站'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(_website),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(_privacy),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('帮助与支持'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(_support),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('关于智羽'),
                subtitle: Text('版本 0.1.2'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}
