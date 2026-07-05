import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/task_status.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
import 'history_page.dart';
import 'profile_page.dart';
import 'report_page.dart';
import 'task_status_page.dart';
import 'upload_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ApiService _api = ApiService();
  final TaskStorage _storage = TaskStorage();
  Map<String, dynamic>? _health;
  TaskStatus? _restoredTask;
  String? _error;
  bool _checking = false;
  bool _restoringTask = true;

  @override
  void initState() {
    super.initState();
    _restoreActiveTask();
  }

  Future<void> _restoreActiveTask() async {
    try {
      final taskId = await _storage.getActiveTaskId();
      if (taskId == null) return;
      final task = await _api.getTask(taskId);
      if (task.isRunning) {
        if (mounted) setState(() => _restoredTask = task);
      } else if (task.isCompleted) {
        await _storage.removeUpload(taskId);
      } else {
        await _storage.clearActiveTask(taskId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '恢复未完成任务失败：$error');
      }
    } finally {
      if (mounted) setState(() => _restoringTask = false);
    }
  }

  Future<void> _openRestoredTask() async {
    final task = _restoredTask;
    if (task == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskStatusPage(taskId: task.taskId),
      ),
    );
    if (!mounted) return;
    setState(() {
      _restoredTask = null;
      _restoringTask = true;
    });
    await _restoreActiveTask();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final health = await _api.checkHealth();
      if (!mounted) return;
      setState(() => _health = health);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Good-Badminton')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: const Icon(Icons.sports_tennis, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '羽毛球视频分析',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      const Text('上传比赛视频，查看移动数据与可视化报告'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('当前后端地址'),
          const SizedBox(height: 4),
          const SelectableText(ApiConfig.baseUrl),
          if (_restoringTask) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const Text('正在检查未完成任务…'),
          ],
          if (_restoredTask != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('发现未完成任务'),
                subtitle: Text(
                  '${_restoredTask!.videoName}\n'
                  '${_restoredTask!.status} · '
                  '${_restoredTask!.progressPercent}%',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _openRestoredTask,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _checking ? null : _checkHealth,
            icon: _checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(_checking ? '正在连接' : '测试后端连接'),
          ),
          if (_health != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ok：${_health!['ok']}'),
                    Text('project_root：${_health!['project_root'] ?? ''}'),
                    Text(
                      'default_template：'
                      '${_health!['default_template'] ?? ''}',
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              '连接失败：$_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UploadPage()),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text('上传视频'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportPage.demo()),
            ),
            icon: const Icon(Icons.science_outlined),
            label: const Text('查看 Demo 报告'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
            icon: const Icon(Icons.history),
            label: const Text('历史记录'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
            icon: const Icon(Icons.person_outline),
            label: const Text('训练档案'),
          ),
        ],
      ),
    );
  }
}
