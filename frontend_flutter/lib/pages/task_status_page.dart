import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_status.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
import 'report_page.dart';
import 'upload_page.dart';

class TaskStatusPage extends StatefulWidget {
  const TaskStatusPage({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskStatusPage> createState() => _TaskStatusPageState();
}

class _TaskStatusPageState extends State<TaskStatusPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final TaskStorage _storage = TaskStorage();
  Timer? _timer;
  TaskStatus? _task;
  String? _error;
  bool _temporaryNetworkIssue = false;
  bool _loading = true;
  bool _requestInFlight = false;
  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
      final task = await _api.getTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = task;
        _error = null;
        _temporaryNetworkIssue = false;
        _loading = false;
      });
      if (!task.isRunning) {
        _timer?.cancel();
        if (task.isCompleted) {
          await _storage.removeUpload(task.taskId);
        } else {
          await _storage.clearActiveTask(task.taskId);
        }
      }
    } catch (error) {
      if (!mounted) return;
      final isTransient = error is ApiException && error.isTransient;
      setState(() {
        _temporaryNetworkIssue = isTransient;
        _error = isTransient ? '网络连接短暂中断，正在自动重试。' : error.toString();
        _loading = false;
      });
    } finally {
      _requestInFlight = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motionController.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: AppBar(title: const Text('任务状态')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            SelectableText('task_id：${widget.taskId}'),
            const SizedBox(height: 16),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (task != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: _statusColor(context, task)
                              .withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: task.isRunning
                            ? RotationTransition(
                                turns: _motionController,
                                child: Icon(
                                  Icons.sports_tennis,
                                  size: 42,
                                  color: _statusColor(context, task),
                                ),
                              )
                            : Icon(
                                _statusIcon(task),
                                size: 42,
                                color: _statusColor(context, task),
                              ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _stageMessage(task),
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Chip(
                            avatar: Icon(
                              _statusIcon(task),
                              size: 18,
                              color: _statusColor(context, task),
                            ),
                            label: Text(_statusLabel(task)),
                          ),
                          const Spacer(),
                          Text(
                            '${task.progressPercent}%',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: task.progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '当前阶段：'
                          '${task.stage.isEmpty ? '等待更新' : task.stage}',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('视频：${task.videoName}'),
                      ),
                    ],
                  ),
                ),
              ),
              if (task.isCompleted) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportPage(taskId: widget.taskId),
                    ),
                  ),
                  child: const Text('查看报告'),
                ),
              ],
              if (task.isFailed) ...[
                const SizedBox(height: 12),
                Text(
                  task.error ?? '分析失败',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => UploadPage(retryTaskId: task.taskId),
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新上传'),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: _temporaryNetworkIssue
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    _temporaryNetworkIssue ? Icons.sync : Icons.error_outline,
                  ),
                  title: Text(_error!),
                  subtitle: _temporaryNetworkIssue
                      ? const Text('任务编号已保留，无需重新上传。')
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(TaskStatus task) {
    return switch (task.status) {
      'queued' => '排队中',
      'processing' => '分析中',
      'completed' => '已完成',
      'failed' => '分析失败',
      _ => task.status,
    };
  }

  IconData _statusIcon(TaskStatus task) {
    return switch (task.status) {
      'queued' => Icons.schedule,
      'processing' => Icons.analytics_outlined,
      'completed' => Icons.check_circle_outline,
      'failed' => Icons.error_outline,
      _ => Icons.help_outline,
    };
  }

  Color _statusColor(BuildContext context, TaskStatus task) {
    return switch (task.status) {
      'completed' => Colors.green.shade700,
      'failed' => Theme.of(context).colorScheme.error,
      'processing' => Theme.of(context).colorScheme.primary,
      _ => Theme.of(context).colorScheme.secondary,
    };
  }

  String _stageMessage(TaskStatus task) {
    if (task.status == 'queued') return '[1/4] 正在准备分析资源…';
    if (task.isCompleted) return '分析完成，训练报告已生成';
    if (task.isFailed) return '分析未完成，请查看错误信息';
    final stage = task.stage.toLowerCase();
    if (stage.contains('court') ||
        stage.contains('template') ||
        stage.contains('preview')) {
      return '[1/4] 正在检测球场角点…';
    }
    if (stage.contains('pose') ||
        stage.contains('player') ||
        stage.contains('track')) {
      return '[2/4] 正在追踪球员轨迹…';
    }
    if (stage.contains('shuttle') || stage.contains('ball')) {
      return '[3/4] 正在识别羽毛球运动…';
    }
    if (stage.contains('report') ||
        stage.contains('visual') ||
        stage.contains('finish')) {
      return '[4/4] 正在生成复盘报告…';
    }
    if (task.progress < 0.25) return '[1/4] 正在检测球场角点…';
    if (task.progress < 0.55) return '[2/4] 正在追踪球员轨迹…';
    if (task.progress < 0.82) return '[3/4] 正在识别羽毛球运动…';
    return '[4/4] 正在生成复盘报告…';
  }
}
