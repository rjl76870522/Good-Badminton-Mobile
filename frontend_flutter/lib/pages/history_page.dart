import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/history_item.dart';
import '../services/api_service.dart';
import '../services/offline_report_storage.dart';
import '../services/user_storage.dart';
import '../utils/user_facing_error.dart';
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
  final OfflineReportStorage _offlineStorage = OfflineReportStorage();
  List<HistoryItem> _tasks = const [];
  List<OfflineReportRecord> _offlineRecords = const [];
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
    _offlineRecords = await _offlineStorage.list();
    try {
      final userId = await _userStorage.getOrCreateUserId();
      final tasks = await _api.getHistory(
        userId: userId,
        limit: 30,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (mounted) setState(() => _tasks = tasks);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            error,
            fallback: '暂时无法读取训练历史，请确认分析服务已启动后重试。',
          ),
        );
      }
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
    final offline = _offlineRecordFor(task.taskId);
    final page = task.isCompleted
        ? offline != null
            ? ReportPage.offline(record: offline)
            : ReportPage(taskId: task.taskId)
        : TaskStatusPage(taskId: task.taskId);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  OfflineReportRecord? _offlineRecordFor(String taskId) {
    for (final record in _offlineRecords) {
      if (record.taskId == taskId) return record;
    }
    return null;
  }

  Future<void> _saveOffline(HistoryItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存离线报告'),
        content: const Text(
          '将核心指标、训练建议、热力图和轨迹图保存到本机'
          '\n\n为了节省手机存储空间，分析视频不会随离线报告保存'
          '，有需要可以在报告中单独下载到系统相册',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final record = await _offlineStorage.save(
        api: _api,
        taskId: task.taskId,
        videoName: task.videoName,
      );
      if (!mounted) return;
      setState(() {
        _offlineRecords = [
          record,
          ..._offlineRecords.where((item) => item.taskId != task.taskId),
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('报告和图表已保存，暂时无法联网时也能查看')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(error, fallback: '保存离线报告失败，请稍后重试。')),
        ),
      );
    }
  }

  Future<void> _deleteOffline(OfflineReportRecord record) async {
    await _offlineStorage.delete(record);
    if (!mounted) return;
    setState(() {
      _offlineRecords = _offlineRecords
          .where((item) => item.taskId != record.taskId)
          .toList();
    });
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
        SnackBar(
          content: Text(
            userFacingError(error, fallback: '删除训练记录失败，请稍后重试。'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05080B),
      appBar: AppBar(
        title: const Text('训练历史'),
        backgroundColor: const Color(0xFF080D12),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/history_court_bg.png',
            fit: BoxFit.cover,
            alignment: const Alignment(0.18, -0.15),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x52000000),
                  Color(0x26000000),
                  Color(0x99000000),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    dropdownColor: const Color(0xFF172026),
                    iconEnabledColor: Colors.white,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '状态筛选',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.62),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Color(0xFFFFC44D),
                          width: 1.5,
                        ),
                      ),
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
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  if (_error != null)
                    _HistoryErrorCard(message: _error!, onRetry: _load),
                  if (_offlineRecords.isNotEmpty) ...[
                    _OfflineSection(
                      records: _offlineRecords,
                      onOpen: (record) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReportPage.offline(record: record),
                        ),
                      ),
                      onDelete: _deleteOffline,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_loading && _tasks.isEmpty && _error == null)
                    Container(
                      margin: const EdgeInsets.only(top: 18),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        '暂无训练记录',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ..._tasks.map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HistoryCard(
                        task: task,
                        onTap: () => _openTask(task),
                        onRetry: task.isFailed ? () => _retryTask(task) : null,
                        onDelete: () => _deleteTask(task),
                        offlineSaved: _offlineRecordFor(task.taskId) != null,
                        onSaveOffline:
                            task.isCompleted ? () => _saveOffline(task) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryErrorCard extends StatelessWidget {
  const _HistoryErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xF2FFF8F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFC9C6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xFFC45B57)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '暂时无法读取训练记录',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Color(0xFF69413F))),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新连接'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.task,
    required this.onTap,
    required this.onDelete,
    required this.offlineSaved,
    this.onRetry,
    this.onSaveOffline,
  });

  final HistoryItem task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool offlineSaved;
  final VoidCallback? onRetry;
  final VoidCallback? onSaveOffline;

  @override
  Widget build(BuildContext context) {
    final thumbnail = ApiConfig.absoluteFileUrl(task.thumbnail);
    return Card(
      color: Colors.white.withValues(alpha: 0.93),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbnail != null)
              AspectRatio(
                aspectRatio: 2.6,
                child: Image.network(
                  thumbnail,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onRetry != null)
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新上传'),
                        ),
                      if (onSaveOffline != null)
                        OutlinedButton.icon(
                          onPressed: offlineSaved ? null : onSaveOffline,
                          icon: Icon(
                            offlineSaved
                                ? Icons.offline_pin_outlined
                                : Icons.download_for_offline_outlined,
                          ),
                          label: Text(offlineSaved ? '已离线保存' : '离线保存'),
                        ),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除记录'),
                      ),
                    ],
                  ),
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

class _OfflineSection extends StatelessWidget {
  const _OfflineSection({
    required this.records,
    required this.onOpen,
    required this.onDelete,
  });

  final List<OfflineReportRecord> records;
  final ValueChanged<OfflineReportRecord> onOpen;
  final ValueChanged<OfflineReportRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xF2F4FAF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB6CFBA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.offline_pin_outlined, color: Color(0xFF286B35)),
              SizedBox(width: 8),
              Text(
                '手机离线报告',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('暂时无法联网时仍可查看核心指标、训练建议和图表'),
          ...records.map(
            (record) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                record.videoName.isEmpty ? '训练报告' : record.videoName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${record.savedAt.year}-${record.savedAt.month.toString().padLeft(2, '0')}-'
                '${record.savedAt.day.toString().padLeft(2, '0')} 已保存到本机',
              ),
              onTap: () => onOpen(record),
              trailing: IconButton(
                tooltip: '删除离线副本',
                onPressed: () => onDelete(record),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
