import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/user_storage.dart';
import '../widgets/app_background.dart';
import 'history_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UserStorage _storage = UserStorage();
  final ImagePicker _imagePicker = ImagePicker();
  String _nickname = '';
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.getNickname(),
      _storage.getAvatarPath(),
    ]);
    if (!mounted) return;
    setState(() {
      _nickname = values[0] ?? '';
      _avatarPath = values[1];
    });
  }

  Future<void> _pickAvatar() async {
    final selected = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (selected == null) return;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/GoodBadminton/profile');
    await directory.create(recursive: true);
    final extension =
        selected.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final target = File('${directory.path}/avatar.$extension');
    await File(selected.path).copy(target.path);
    final previous = _avatarPath;
    await _storage.setAvatarPath(target.path);
    if (previous != null && previous != target.path) {
      try {
        await File(previous).delete();
      } on FileSystemException {
        // 旧头像不存在时不影响新头像。
      }
    }
    await _load();
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          maxLength: 20,
          autofocus: true,
          decoration: const InputDecoration(hintText: '昵称保存在本机'),
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
    final avatar = _avatarPath == null ? null : File(_avatarPath!);
    final hasAvatar = avatar?.existsSync() ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('家'),
        backgroundColor: Colors.transparent,
      ),
      body: AppBackground(
        imageAsset: 'assets/images/history_court_bg.png',
        imageOpacity: 0.12,
        alignment: const Alignment(0.1, -0.35),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _pickAvatar,
                        customBorder: const CircleBorder(),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 38,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              backgroundImage:
                                  hasAvatar ? FileImage(avatar!) : null,
                              child: hasAvatar
                                  ? null
                                  : const Icon(Icons.person_outline, size: 40),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                child: const Icon(
                                  Icons.camera_alt_outlined,
                                  size: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nickname.isEmpty ? '羽球用户' : _nickname,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 5),
                            const Text('点击头像可以从相册更换'),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '修改昵称',
                        onPressed: _editNickname,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('训练历史'),
                      subtitle: const Text('查看任务、报告和手机离线记录'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HistoryPage()),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('设置'),
                      subtitle: const Text('播放、存储、权限与帮助'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('智羽'),
                  subtitle: Text('版本 0.1.2'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
