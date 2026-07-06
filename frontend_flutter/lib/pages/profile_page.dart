import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'history_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserStorage _storage = UserStorage();
  final ApiService _api = ApiService();
  String _userId = '';
  String _nickname = '';
  String? _identityError;
  bool? _registered;
  bool _registering = false;
  bool _checkingIdentity = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.getOrCreateUserId(),
      _storage.getNickname(),
    ]);
    if (mounted) {
      setState(() {
        _userId = values[0];
        _nickname = values[1];
      });
    }
    await _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    if (_userId.isEmpty) return;
    if (mounted) {
      setState(() {
        _checkingIdentity = true;
        _identityError = null;
      });
    }
    try {
      await _api.getUser(_userId);
      if (mounted) {
        setState(() {
          _registered = true;
          _identityError = null;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _registered = error.code == 'USER_NOT_FOUND' ? false : null;
        _identityError =
            error.code == 'USER_NOT_FOUND' ? null : error.toString();
      });
    } finally {
      if (mounted) setState(() => _checkingIdentity = false);
    }
  }

  Future<void> _registerIdentity() async {
    setState(() {
      _registering = true;
      _identityError = null;
    });
    try {
      await _api.registerUser(_userId);
      if (mounted) setState(() => _registered = true);
    } on ApiException catch (error) {
      if (error.code == 'USER_ID_TAKEN') {
        await _checkRegistration();
      } else if (mounted) {
        setState(() => _identityError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置本地昵称'),
        content: TextField(
          controller: controller,
          maxLength: 20,
          autofocus: true,
          decoration: const InputDecoration(hintText: '昵称仅保存在本机'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _storage.setNickname(value);
    await _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('训练档案')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.person_outline, size: 38),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _nickname.isEmpty ? '羽球访客' : _nickname,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('本地游客模式 · 无需登录'),
                  const SizedBox(height: 10),
                  SelectableText(
                    _userId.isEmpty ? '正在生成身份…' : _userId,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _editNickname,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('修改本地昵称'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '后端游客身份',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      Chip(
                        avatar: Icon(
                          _registered == true
                              ? Icons.check_circle
                              : _registered == false
                                  ? Icons.person_add_alt
                                  : Icons.cloud_off_outlined,
                          size: 17,
                        ),
                        label: Text(
                          _checkingIdentity
                              ? '查询中'
                              : _registered == true
                                  ? '已登记'
                                  : _registered == false
                                      ? '未登记'
                                      : '待查询',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '登记后仍然是游客模式；上传、历史记录和报告将继续使用同一个 user_id。',
                    style: TextStyle(height: 1.5),
                  ),
                  if (_identityError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _identityError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _checkingIdentity ? null : _checkRegistration,
                        icon: const Icon(Icons.manage_search),
                        label: const Text('查询游客身份'),
                      ),
                      if (_registered != true)
                        FilledButton.tonalIcon(
                          onPressed: _registering ? null : _registerIdentity,
                          icon: _registering
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.how_to_reg_outlined),
                          label: Text(_registering ? '登记中' : '登记游客身份'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('查看训练历史'),
              subtitle: const Text('历史记录按本机游客 ID 隔离'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
