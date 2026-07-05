import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/history_item.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import 'report_page.dart';
import 'task_status_page.dart';
import 'upload_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ApiService _api = ApiService();
  final UserStorage _userStorage = UserStorage();
  List<HistoryItem> _tasks = const [];
  String? _error;
  String _statusFilter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = await _userStorage.getOrCreateUserId();
      final tasks = await _api.getHistory(
        userId: userId,
        limit: 30,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (mounted) setState(() => _tasks = tasks);
    } catch (error) {
      if (mounted) setState(() => _error = '读取历史失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _openTask(HistoryItem task) {
    final page = task.isCompleted
        ? ReportPage(taskId: task.taskId)
        : TaskStatusPage(taskId: task.taskId);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _retryTask(HistoryItem task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UploadPage(retryTaskId: task.taskId),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _deleteTask(HistoryItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除训练记录？'),
        content: Text(
          '将删除“${task.videoName.isEmpty ? task.taskId : task.videoName}”'
          '及后端生成的相关文件，此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final userId = await _userStorage.getOrCreateUserId();
      await _api.deleteTask(task.taskId, userId: userId);
      if (!mounted) return;
      setState(() {
        _tasks = _tasks
            .where((item) => item.taskId != task.taskId)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('训练记录已删除')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('训练历史')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(
                labelText: '状态筛选',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('全部')),
                DropdownMenuItem(value: 'queued', child: Text('排队中')),
                DropdownMenuItem(value: 'processing', child: Text('分析中')),
                DropdownMenuItem(value: 'completed', child: Text('已完成')),
                DropdownMenuItem(value: 'failed', child: Text('失败')),
              ],
              onChanged: (value) {
                setState(() => _statusFilter = value ?? 'all');
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_loading && _tasks.isEmpty && _error == null)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无训练记录'),
              )),
            ..._tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HistoryCard(
                  task: task,
                  onTap: () => _openTask(task),
                  onRetry: task.isFailed ? () => _retryTask(task) : null,
                  onDelete: () => _deleteTask(task),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.task,
    required this.onTap,
    required this.onDelete,
    this.onRetry,
  });

  final HistoryItem task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final thumbnail = ApiConfig.absoluteFileUrl(task.thumbnail);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail != null)
              Image.network(
                thumbnail,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.videoName.isEmpty ? task.taskId : task.videoName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(label: Text(_statusLabel(task.status))),
                      IconButton(
                        tooltip: '删除记录',
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MiniMetric(
                        label: '总距离',
                        value:
                            '${task.summary.totalDistanceM.toStringAsFixed(1)} m',
                      ),
                      _MiniMetric(
                        label: '最高速度',
                        value:
                            '${task.summary.maxSpeedMps.toStringAsFixed(1)} m/s',
                      ),
                      _MiniMetric(
                        label: '训练强度',
                        value: '${task.summary.intensityScore}',
                      ),
                    ],
                  ),
                  if (task.reportSummary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      task.reportSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新上传'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'queued' => '排队中',
        'processing' => '分析中',
        'completed' => '已完成',
        'failed' => '失败',
        _ => status,
      };
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
