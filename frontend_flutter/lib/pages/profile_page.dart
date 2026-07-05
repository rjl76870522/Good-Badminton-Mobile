import 'package:flutter/material.dart';

import '../services/user_storage.dart';
import 'history_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserStorage _storage = UserStorage();
  String _userId = '';
  String _nickname = '';

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
                  const Text('游客模式 · 无需登录'),
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
