import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/report.dart';
import '../services/api_service.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.taskId}) : loadDemo = false;

  const ReportPage.demo({super.key})
      : taskId = null,
        loadDemo = true;

  final String? taskId;
  final bool loadDemo;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final ApiService _api = ApiService();
  AnalysisReport? _report;
  Map<String, bool> _fileAvailability = const {};
  String? _error;
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
      final report = widget.loadDemo
          ? await _api.getDemoReport()
          : await _api.getReport(widget.taskId!);
      final availability = await _checkReportFiles(report);
      if (!mounted) return;
      setState(() {
        _report = report;
        _fileAvailability = availability;
      });
    } on ReportPendingException {
      if (!mounted) return;
      setState(() => _error = '报告还未生成完成');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取报告失败：$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, bool>> _checkReportFiles(AnalysisReport report) async {
    final checks = await Future.wait([
      _api.fileExists(report.files.heatmap),
      _api.fileExists(report.files.trajectory),
      _api.fileExists(report.files.analysisVideo),
      _api.fileExists(report.files.highlight),
    ]);
    return {
      'heatmap': checks[0],
      'trajectory': checks[1],
      'analysis_video': checks[2],
      'highlight': checks[3],
    };
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.loadDemo ? 'Demo 训练复盘' : '训练复盘报告'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重新加载')),
            ],
            if (report != null) ...[
              Text(
                '核心表现',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _SummaryCard(summary: report.summary),
              const SizedBox(height: 20),
              Text(
                '移动可视化',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _VisualizationSwitcher(
                heatmapUrl: report.files.heatmap,
                trajectoryUrl: report.files.trajectory,
                heatmapAvailable: _fileAvailability['heatmap'] ?? false,
                trajectoryAvailable: _fileAvailability['trajectory'] ?? false,
              ),
              const SizedBox(height: 20),
              _CoachingSection(report: report),
              const SizedBox(height: 20),
              Text('精彩时刻', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _FileLink(
                title: '精彩集锦',
                relativeUrl: report.files.highlight,
                available: _fileAvailability['highlight'] ?? false,
              ),
              if (report.highlightSegments.isNotEmpty)
                ...report.highlightSegments.map(_HighlightCard.new),
              _FileLink(
                title: '分析视频',
                relativeUrl: report.files.analysisVideo,
                available: _fileAvailability['analysis_video'] ?? false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(
                  width: width,
                  label: '总距离',
                  value: '${summary.totalDistanceM.toStringAsFixed(2)} m',
                  icon: Icons.route_outlined,
                ),
                _MetricTile(
                  width: width,
                  label: '最大速度',
                  value: '${summary.maxSpeedMps.toStringAsFixed(2)} m/s',
                  icon: Icons.speed,
                ),
                _MetricTile(
                  width: width,
                  label: '平均速度',
                  value: '${summary.avgSpeedMps.toStringAsFixed(2)} m/s',
                  icon: Icons.timeline,
                ),
                _MetricTile(
                  width: width,
                  label: '强度评分',
                  value: '${summary.intensityScore}',
                  icon: Icons.local_fire_department_outlined,
                ),
                _MetricTile(
                  width: width,
                  label: '检测帧数',
                  value: '${summary.detectedFrames}',
                  icon: Icons.filter_frames_outlined,
                ),
                _MetricTile(
                  width: width,
                  label: '羽毛球帧数',
                  value: '${summary.shuttlecockFrames}',
                  icon: Icons.sports_tennis,
                ),
                _MetricTile(
                  width: width,
                  label: '有效时长',
                  value: '${summary.activeTimeSec.toStringAsFixed(1)} s',
                  icon: Icons.timer_outlined,
                ),
                _MetricTile(
                  width: width,
                  label: '每分钟距离',
                  value: '${summary.distancePerMin.toStringAsFixed(1)} m',
                  icon: Icons.directions_run,
                ),
                _MetricTile(
                  width: width,
                  label: '覆盖面积',
                  value: '${summary.coverageAreaM2.toStringAsFixed(1)} m²',
                  icon: Icons.grid_on_outlined,
                ),
                _MetricTile(
                  width: width,
                  label: '羽毛球识别占比',
                  value:
                      '${(summary.shuttlecockRatio * 100).toStringAsFixed(0)}%',
                  icon: Icons.track_changes,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VisualizationSwitcher extends StatefulWidget {
  const _VisualizationSwitcher({
    required this.heatmapUrl,
    required this.trajectoryUrl,
    required this.heatmapAvailable,
    required this.trajectoryAvailable,
  });

  final String? heatmapUrl;
  final String? trajectoryUrl;
  final bool heatmapAvailable;
  final bool trajectoryAvailable;

  @override
  State<_VisualizationSwitcher> createState() => _VisualizationSwitcherState();
}

class _VisualizationSwitcherState extends State<_VisualizationSwitcher> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final isHeatmap = _selected == 0;
    final relativeUrl = isHeatmap ? widget.heatmapUrl : widget.trajectoryUrl;
    final available =
        isHeatmap ? widget.heatmapAvailable : widget.trajectoryAvailable;
    final url = ApiConfig.absoluteFileUrl(relativeUrl);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.local_fire_department_outlined),
                    label: Text('热力图'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.route_outlined),
                    label: Text('球员轨迹'),
                  ),
                ],
                selected: {_selected},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _selected = selection.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Container(
                key: ValueKey(_selected),
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 210),
                decoration: BoxDecoration(
                  color: const Color(0xFF123C24),
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: url == null
                    ? const Center(
                        child: Text(
                          '暂无可视化文件',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : !available
                        ? const Center(
                            child: Text(
                              '文件未生成或已失效',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, __) => Center(
                              child: Text(
                                '图片加载失败：$error',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachingSection extends StatelessWidget {
  const _CoachingSection({required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    if (report.coaching.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('训练建议', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (report.advice.isEmpty)
            const Text('暂无建议')
          else
            ...report.advice.map(
              (advice) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tips_and_updates_outlined),
                title: Text(advice),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('训练建议', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _CoachingGroup(
          title: '当前优点',
          icon: Icons.thumb_up_alt_outlined,
          items: report.coaching.strengths,
        ),
        _CoachingGroup(
          title: '目前缺点',
          icon: Icons.flag_outlined,
          items: report.coaching.weaknesses,
        ),
        _CoachingGroup(
          title: '改进建议',
          icon: Icons.fitness_center,
          items: report.coaching.improvements,
        ),
      ],
    );
  }
}

class _CoachingGroup extends StatelessWidget {
  const _CoachingGroup({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<CoachingItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFFE8F5E9),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text('暂无')
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (item.basis.isNotEmpty) Text('依据：${item.basis}'),
                        if (item.detail.isNotEmpty) Text(item.detail),
                        if (item.trainingFocus.isNotEmpty)
                          Text('训练重点：${item.trainingFocus}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard(this.segment);

  final HighlightSegment segment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '精彩片段 · ${segment.score} 分',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    '${segment.startSec.toStringAsFixed(1)}s - '
                    '${segment.endSec.toStringAsFixed(1)}s',
                  ),
                  if (segment.reason.isNotEmpty)
                    Text(
                      segment.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: label == '总距离' || label == '最大速度'
              ? const [Color(0xFFE8F5E9), Color(0xFFF7FBF4)]
              : [
                  Theme.of(context).colorScheme.surfaceContainerLow,
                  Colors.white,
                ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E5DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _FileLink extends StatelessWidget {
  const _FileLink({
    required this.title,
    required this.relativeUrl,
    required this.available,
  });

  final String title;
  final String? relativeUrl;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final url = ApiConfig.absoluteFileUrl(relativeUrl);
    final text = url == null
        ? '暂无文件'
        : available
            ? url
            : '文件未生成或已失效';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: SelectableText(text),
      leading: url != null && !available ? const Icon(Icons.link_off) : null,
    );
  }
}
