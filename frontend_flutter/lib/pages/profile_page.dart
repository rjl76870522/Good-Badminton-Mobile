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
                  Text(
                    _registered == true
                        ? '游客身份已在当前后端登记'
                        : _registered == false
                            ? '本地游客模式 · 尚未在后端登记'
                            : '正在检查游客身份',
                  ),
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
                  if (_registered == false) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _registering ? null : _registerIdentity,
                      icon: _registering
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.how_to_reg_outlined),
                      label: Text(_registering ? '登记中' : '登记游客身份'),
                    ),
                  ],
                  if (_identityError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _identityError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
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
