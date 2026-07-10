import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_status.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
import '../widgets/app_background.dart';
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
      appBar: AppBar(
        title: const Text('任务状态'),
        actions: [
          IconButton(
            tooltip: '退出',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
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
                          if (task.isRunning)
                            _AnalysisWaiting(
                              animation: _motionController,
                              color: _statusColor(context, task),
                            )
                          else
                            SizedBox(
                              width: 112,
                              height: 112,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _statusColor(context, task)
                                      .withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _statusIcon(task),
                                  size: 42,
                                  color: _statusColor(context, task),
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          Text(
                            _stageMessage(task),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Chip(
                                backgroundColor: _statusColor(context, task)
                                    .withValues(alpha: 0.12),
                                side: BorderSide.none,
                                avatar: Icon(
                                  _statusIcon(task),
                                  size: 18,
                                  color: _statusColor(context, task),
                                ),
                                label: Text(_statusLabel(task)),
                              ),
                              const Spacer(),
                              Text(
                                task.isFailed
                                    ? '已停止'
                                    : '${task.progressPercent}%',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: task.progress.clamp(0.0, 1.0).toDouble(),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                            color: task.isFailed
                                ? const Color(0xFFB65C62)
                                : Theme.of(context).colorScheme.primary,
                            backgroundColor:
                                task.isFailed ? const Color(0xFFF4E5E6) : null,
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '当前阶段：'
                              '${_stageLabel(task)}',
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
                    _FailureHelpCard(
                      error: task.error,
                      onRetry: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => UploadPage(retryTaskId: task.taskId),
                        ),
                      ),
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
                        _temporaryNetworkIssue
                            ? Icons.sync
                            : Icons.error_outline,
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
      'completed' => const Color(0xFF2E7D32),
      'failed' => const Color(0xFFB65C62),
      'processing' => Theme.of(context).colorScheme.primary,
      'queued' => const Color(0xFF607D9B),
      _ => Theme.of(context).colorScheme.secondary,
    };
  }

  String _stageLabel(TaskStatus task) {
    if (task.isFailed) return '分析已停止';
    if (task.isCompleted) return '分析完成';
    if (task.status == 'queued') return '等待分析';
    if (task.stage.isEmpty) return '等待更新';
    return task.stage;
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

class _AnalysisWaiting extends StatelessWidget {
  const _AnalysisWaiting({
    required this.animation,
    required this.color,
  });

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final imageWidth =
        (MediaQuery.sizeOf(context).width * 0.4).clamp(132.0, 168.0).toDouble();
    return Semantics(
      label: '请耐心等待，分析正在进行中',
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: imageWidth,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.asset(
                  'assets/images/cai_xukun_waiting.gif',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '请耐心等待',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(width: 7),
              _JumpingDots(animation: animation, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _JumpingDots extends StatelessWidget {
  const _JumpingDots({
    required this.animation,
    required this.color,
  });

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (animation.value + index * 0.18) % 1;
            final normalized = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final height = Curves.easeInOut.transform(normalized) * 7;
            return Transform.translate(
              offset: Offset(0, -height),
              child: Container(
                width: 6,
                height: 6,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            );
          }),
        );
      },
    );
  }
}

class _FailureHelpCard extends StatelessWidget {
  const _FailureHelpCard({
    required this.error,
    required this.onRetry,
  });

  final String? error;
  final VoidCallback onRetry;

  bool get _isDetectionFailure {
    final message = error ?? '';
    return message.contains('未检测到有效球场') ||
        message.contains('球员数据') ||
        message.contains('四个球场角点');
  }

  @override
  Widget build(BuildContext context) {
    final title = _isDetectionFailure ? '没有识别到有效比赛画面' : '本次分析未完成';
    final description = _isDetectionFailure
        ? '系统没有获得足够稳定的球场和球员数据，暂时无法生成可靠报告。'
        : '分析过程中出现问题，请根据下方错误详情检查视频后重试。';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0C9CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFB65C62),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(description, style: const TextStyle(height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          if (_isDetectionFailure) ...[
            const SizedBox(height: 14),
            const _SuggestionLine(text: '确认视频完整拍到球场，且人物没有长时间离开画面'),
            const SizedBox(height: 8),
            const _SuggestionLine(text: '重新上传后，在预览页手动标记四个球场角点'),
          ],
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('查看原始错误详情'),
              children: [
                SelectableText(
                  error!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(
                _isDetectionFailure ? '重新上传并标记角点' : '重新上传',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionLine extends StatelessWidget {
  const _SuggestionLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    );
  }
}
