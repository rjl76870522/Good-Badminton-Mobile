import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/offline_report_storage.dart';
import '../services/app_preferences.dart';
import '../services/notification_service.dart';
import '../services/user_storage.dart';
import 'legal_document_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static final _website = Uri.parse('https://www.audacity6441.kdns.fr/');
  static final _support = Uri.parse('https://www.audacity6441.kdns.fr/support');

  final UserStorage _storage = UserStorage();
  final OfflineReportStorage _offlineStorage = OfflineReportStorage();
  bool _autoPlay = false;
  bool _notifications = false;
  bool _eyeCare = false;
  int _offlineCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoPlay = await _storage.getAutoPlayVideos();
    final records = await _offlineStorage.list();
    final notifications = await AppPreferences.instance.notificationsEnabled();
    if (!mounted) return;
    setState(() {
      _autoPlay = autoPlay;
      _notifications = notifications;
      _eyeCare = AppPreferences.instance.eyeCareEnabled.value;
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

  void _openDocument(LegalDocumentType type) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentPage(type: type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsGroup(
            title: '提醒与显示',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('分析完成通知'),
                subtitle: const Text('应用运行期间或再次打开应用时提醒分析结果'),
                value: _notifications,
                onChanged: (value) async {
                  if (value) {
                    final allowed =
                        await NotificationService.instance.requestPermission();
                    if (!allowed) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请在系统设置中允许通知权限')),
                        );
                      }
                      return;
                    }
                  }
                  await AppPreferences.instance.setNotificationsEnabled(value);
                  if (mounted) setState(() => _notifications = value);
                },
              ),
              if (_notifications) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('发送测试通知'),
                  subtitle: const Text('立即检查系统通知能否正常显示'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await NotificationService.instance.showTestNotification();
                  },
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_outlined),
                title: const Text('护眼模式'),
                subtitle: const Text('降低纯白背景亮度，使用柔和低对比配色'),
                value: _eyeCare,
                onChanged: (value) async {
                  await AppPreferences.instance.setEyeCareEnabled(value);
                  if (mounted) setState(() => _eyeCare = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                onTap: () => _openDocument(LegalDocumentType.privacy),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('用户协议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDocument(LegalDocumentType.agreement),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('个人信息收集清单'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    _openDocument(LegalDocumentType.personalInformation),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text('第三方信息共享清单'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDocument(LegalDocumentType.thirdPartySharing),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.handshake_outlined),
                title: const Text('商务合作'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDocument(LegalDocumentType.cooperation),
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
