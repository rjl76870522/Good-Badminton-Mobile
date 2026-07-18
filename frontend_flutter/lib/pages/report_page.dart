import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../models/report.dart';
import '../services/api_service.dart';
import '../services/offline_report_storage.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_background.dart';
import '../widgets/inline_network_video.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.taskId})
      : loadDemo = false,
        offlineRecord = null;

  const ReportPage.demo({super.key})
      : taskId = null,
        loadDemo = true,
        offlineRecord = null;

  const ReportPage.offline({
    super.key,
    required OfflineReportRecord record,
  })  : taskId = null,
        loadDemo = false,
        offlineRecord = record;

  final String? taskId;
  final bool loadDemo;
  final OfflineReportRecord? offlineRecord;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final ApiService _api = ApiService();
  final OfflineReportStorage _offlineStorage = OfflineReportStorage();
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
      final offlineRecord = widget.offlineRecord;
      final report = offlineRecord != null
          ? AnalysisReport.fromJson(
              await _offlineStorage.readReport(offlineRecord),
            )
          : widget.loadDemo
              ? await _api.getDemoReport()
              : await _api.getReport(widget.taskId!);
      if (!mounted) return;
      setState(() {
        _report = report;
        _fileAvailability = const {};
        _loading = false;
      });
      if (offlineRecord != null) {
        setState(() {
          _fileAvailability = {
            'heatmap': _localFileExists(offlineRecord.heatmapPath),
            'trajectory': _localFileExists(offlineRecord.trajectoryPath),
            'analysis_video': false,
            'highlight': false,
          };
        });
        _checkRemoteVideosInBackground(report);
      } else {
        _checkReportFilesInBackground(report);
      }
    } on ReportPendingException {
      if (!mounted) return;
      setState(() => _error = '报告还未生成完成');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = userFacingError(
          error,
          fallback: '暂时无法读取训练报告，请稍后重试。',
        ),
      );
    } finally {
      if (mounted && _report == null) {
        setState(() => _loading = false);
      }
    }
  }

  bool _localFileExists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  Future<void> _checkRemoteVideosInBackground(AnalysisReport report) async {
    final checks = await Future.wait([
      _api.fileExists(report.files.analysisVideo),
      _api.fileExists(report.files.highlight),
    ]);
    if (!mounted || _report != report) return;
    setState(() {
      _fileAvailability = {
        ..._fileAvailability,
        'analysis_video': checks[0],
        'highlight': checks[1],
      };
    });
  }

  Future<void> _checkReportFilesInBackground(AnalysisReport report) async {
    final availability = await _checkReportFiles(report);
    if (!mounted || _report != report) return;
    setState(() => _fileAvailability = availability);
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
        title: Text(
          widget.offlineRecord != null
              ? '离线训练复盘'
              : widget.loadDemo
                  ? 'Demo 训练复盘'
                  : '训练复盘报告',
        ),
        actions: [
          IconButton(
            tooltip: '退出',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: AppBackground(
        imageOpacity: 0.11,
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('重新加载')),
                ],
                if (report != null) ...[
                  if (report.reportSummary.isNotEmpty) ...[
                    _ReportConclusion(text: report.reportSummary),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    '核心表现',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _SummaryCard(
                    summary: report.summary,
                    highlightCount: report.highlightSegments.length,
                  ),
                  const SizedBox(height: 12),
                  _MovementQualityCard(summary: report.summary),
                  if (report.players.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      '球员表现',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    ...report.players.map(_PlayerPerformanceCard.new),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '移动可视化',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  _VisualizationSwitcher(
                    heatmapUrl: widget.offlineRecord?.heatmapPath ??
                        report.files.heatmap,
                    trajectoryUrl: widget.offlineRecord?.trajectoryPath ??
                        report.files.trajectory,
                    heatmapAvailable: _fileAvailability['heatmap'] ?? false,
                    trajectoryAvailable:
                        _fileAvailability['trajectory'] ?? false,
                  ),
                  const SizedBox(height: 20),
                  _CoachingSection(report: report),
                  if (report.adviceSources.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _AdviceSourcesCard(sources: report.adviceSources),
                  ],
                  const SizedBox(height: 20),
                  Text('精彩时刻', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (widget.offlineRecord != null) ...[
                    const _OfflineVideoNotice(),
                    const SizedBox(height: 10),
                  ],
                  _VideoResult(
                    title: '精彩集锦',
                    relativeUrl: report.files.highlight,
                    available: _fileAvailability['highlight'] ?? false,
                  ),
                  if (report.highlightError != null) ...[
                    const SizedBox(height: 8),
                    _HighlightWarning(message: report.highlightError!),
                  ],
                  if (report.highlightSegments.isNotEmpty)
                    ...report.highlightSegments.map(_HighlightCard.new),
                  const SizedBox(height: 12),
                  _VideoResult(
                    title: '分析视频',
                    relativeUrl: report.files.analysisVideo,
                    available: _fileAvailability['analysis_video'] ?? false,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPerformanceCard extends StatelessWidget {
  const _PlayerPerformanceCard(this.player);

  final ReportPlayer player;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.directions_run),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    player.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text('${player.trackingQualityScore.round()} 分追踪质量'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PlayerMetric(
                  label: '跑动距离',
                  value: '${player.totalDistanceM.toStringAsFixed(1)} m',
                ),
                _PlayerMetric(
                  label: '最高速度',
                  value: '${player.maxSpeedMps.toStringAsFixed(1)} m/s',
                ),
                _PlayerMetric(
                  label: '覆盖面积',
                  value: '${player.coverageAreaM2.toStringAsFixed(1)} m²',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMetric extends StatelessWidget {
  const _PlayerMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _HighlightWarning extends StatelessWidget {
  const _HighlightWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF9A6700)),
          const SizedBox(width: 8),
          Expanded(child: Text('精彩集锦暂不可用：$message')),
        ],
      ),
    );
  }
}

class _ReportConclusion extends StatelessWidget {
  const _ReportConclusion({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFC8E3CA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本次分析结论',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(text, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.highlightCount,
  });

  final ReportSummary summary;
  final int highlightCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 375 ? 190 : 210,
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: _BentoMetric(
                  label: '最高瞬时速度',
                  value: summary.maxSpeedMps,
                  decimals: 2,
                  suffix: ' m/s',
                  icon: Icons.north_east_rounded,
                  emphasized: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(
                      child: _BentoMetric(
                        label: '总跑动距离',
                        value: summary.totalDistanceM,
                        decimals: 2,
                        suffix: ' m',
                        icon: Icons.route_outlined,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _BentoMetric(
                        label: '精彩片段',
                        value: highlightCount.toDouble(),
                        decimals: 0,
                        suffix: ' 个',
                        icon: Icons.movie_filter_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
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
        ),
      ],
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

class _MovementQualityCard extends StatelessWidget {
  const _MovementQualityCard({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '稳定运动指标',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            _QualityProgress(
              label: '追踪质量',
              value:
                  (summary.trackingQualityScore / 100).clamp(0, 1).toDouble(),
              trailing: '${summary.trackingQualityScore.round()} 分',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QualityProgress(
                    label: '前场活动',
                    value: summary.frontCourtRatio.clamp(0, 1).toDouble(),
                    trailing: '${(summary.frontCourtRatio * 100).round()}%',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _QualityProgress(
                    label: '后场活动',
                    value: summary.backCourtRatio.clamp(0, 1).toDouble(),
                    trailing: '${(summary.backCourtRatio * 100).round()}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('稳定定位帧：${summary.stablePositionFrames}'),
                ),
                Expanded(
                  child: Text('高强度移动：${summary.highIntensityMoves} 次'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityProgress extends StatelessWidget {
  const _QualityProgress({
    required this.label,
    required this.value,
    required this.trailing,
  });

  final String label;
  final double value;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(trailing, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: value,
          minHeight: 7,
          borderRadius: BorderRadius.circular(7),
        ),
      ],
    );
  }
}

class _VisualizationSwitcherState extends State<_VisualizationSwitcher> {
  var _selected = 0;
  var _downloading = false;

  Future<void> _saveImage(String url, String title) async {
    setState(() => _downloading = true);
    File? temporaryFile;
    try {
      String path;
      if (_isLocalPath(url)) {
        path = url;
      } else {
        final directory = await getTemporaryDirectory();
        temporaryFile = File(
          '${directory.path}/good_badminton_'
          '${DateTime.now().millisecondsSinceEpoch}.png',
        );
        final api = ApiService();
        try {
          path = await api.downloadFile(url, temporaryFile.path);
        } finally {
          api.close();
        }
      }
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      final granted = hasAccess || await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw StateError('未获得系统相册访问权限');
      }
      await Gal.putImage(path, album: 'Good-Badminton');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title 已保存到系统相册')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存图片失败：$error')),
        );
      }
    } finally {
      try {
        await temporaryFile?.delete();
      } on FileSystemException {
        // 临时文件清理失败不影响图片保存结果。
      }
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHeatmap = _selected == 0;
    final relativeUrl = isHeatmap ? widget.heatmapUrl : widget.trajectoryUrl;
    final available =
        isHeatmap ? widget.heatmapAvailable : widget.trajectoryAvailable;
    final url = _resolveMediaUrl(relativeUrl);
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
                        : GestureDetector(
                            onTap: () => _showImagePreview(
                              context,
                              url,
                              isHeatmap ? '热力图' : '球员轨迹',
                            ),
                            child: _FadeNetworkImage(url: url),
                          ),
              ),
            ),
            if (url != null && available) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '点击图片全屏查看，支持双指缩放',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _downloading
                        ? null
                        : () => _saveImage(
                              url,
                              isHeatmap ? '热力图' : '球员轨迹',
                            ),
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(_downloading ? '保存中' : '保存图片'),
                  ),
                ],
              ),
            ],
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
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            height: 1.6,
                          ),
                        ),
                        if (item.basis.isNotEmpty)
                          Text('依据：${item.basis}',
                              style: const TextStyle(height: 1.6)),
                        if (item.detail.isNotEmpty)
                          Text(item.detail,
                              style: const TextStyle(height: 1.6)),
                        if (item.trainingFocus.isNotEmpty)
                          Text(
                            '训练重点：${item.trainingFocus}',
                            style: const TextStyle(height: 1.6),
                          ),
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

class _AdviceSourcesCard extends StatelessWidget {
  const _AdviceSourcesCard({required this.sources});

  final List<AdviceSource> sources;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.menu_book_outlined),
      title: const Text('训练建议参考来源'),
      subtitle: Text('${sources.length} 项资料'),
      children: sources
          .map(
            (source) => ListTile(
              dense: true,
              title: Text(source.title.isEmpty ? source.id : source.title),
              subtitle: source.url == null ? null : SelectableText(source.url!),
            ),
          )
          .toList(growable: false),
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
                      segment.reasonZh.isNotEmpty
                          ? segment.reasonZh
                          : segment.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (segment.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: segment.tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          )
                          .toList(growable: false),
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

class _BentoMetric extends StatelessWidget {
  const _BentoMetric({
    required this.label,
    required this.value,
    required this.decimals,
    required this.suffix,
    required this.icon,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final int decimals;
  final String suffix;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = !emphasized && constraints.maxHeight < 115;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(emphasized
              ? 20
              : compact
                  ? 10
                  : 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: emphasized
                  ? const [Color(0xFF1B5E20), Color(0xFF43A047)]
                  : const [Color(0xFFFFFFFF), Color(0xFFF1F7EE)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: emphasized ? Colors.transparent : const Color(0xFFE0E5DD),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 14,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                size: compact ? 22 : 24,
                color: emphasized ? Colors.white : primary,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: emphasized ? Colors.white70 : Colors.black54,
                      fontSize: compact ? 12 : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 4),
                  _AnimatedNumberText(
                    value: value,
                    decimals: decimals,
                    suffix: suffix,
                    color: emphasized ? Colors.white : Colors.black87,
                    fontSize: emphasized
                        ? 32
                        : compact
                            ? 18
                            : 22,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedNumberText extends StatelessWidget {
  const _AnimatedNumberText({
    required this.value,
    required this.decimals,
    required this.suffix,
    required this.color,
    required this.fontSize,
  });

  final double value;
  final int decimals;
  final String suffix;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) => Text(
        '${animatedValue.toStringAsFixed(decimals)}$suffix',
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8,
        ),
      ),
    );
  }
}

class _FadeNetworkImage extends StatelessWidget {
  const _FadeNetworkImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (_isLocalPath(url)) {
      return Image.file(
        File(url),
        fit: BoxFit.contain,
        errorBuilder: (_, error, __) => _imageError(error),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, synchronous) {
        if (synchronous) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 380),
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (_, error, __) => _imageError(error),
    );
  }

  Widget _imageError(Object error) => Center(
        child: Text(
          '图片加载失败：$error',
          style: const TextStyle(color: Colors.white70),
        ),
      );
}

String? _resolveMediaUrl(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final path = value.trim();
  return _isLocalPath(path) ? path : ApiConfig.absoluteFileUrl(path);
}

bool _isLocalPath(String value) =>
    value.startsWith('/') && File(value).existsSync();

Future<void> _showImagePreview(
  BuildContext context,
  String url,
  String title,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: const Color(0xFF07100A),
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text(title, style: const TextStyle(color: Colors.white)),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(child: _FadeNetworkImage(url: url)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VideoResult extends StatefulWidget {
  const _VideoResult({
    required this.title,
    required this.relativeUrl,
    required this.available,
  });

  final String title;
  final String? relativeUrl;
  final bool available;

  @override
  State<_VideoResult> createState() => _VideoResultState();
}

class _VideoResultState extends State<_VideoResult> {
  final ApiService _api = ApiService();
  bool _downloading = false;
  double _downloadProgress = 0;

  String _filename(String url) {
    final segments = url.split('/');
    final name = segments.last;
    if (name.contains('.')) return name;
    return '${name}_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  Future<void> _downloadVideo() async {
    final url = ApiConfig.absoluteFileUrl(widget.relativeUrl);
    if (url == null) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      // Show indeterminate first
      await Future.delayed(const Duration(milliseconds: 100));

      final dir = await getTemporaryDirectory();
      final videoDir = Directory('${dir.path}/GoodBadminton');
      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }

      final localPath = '${videoDir.path}/${_filename(url)}';

      if (!mounted) return;
      setState(() => _downloadProgress = 0.3);
      final savedPath = await _api.downloadFile(url, localPath);
      if (!mounted) return;
      setState(() => _downloadProgress = 1.0);

      final file = File(savedPath);
      final fileSize = await file.length();
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      final granted = hasAccess || await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw StateError('未获得系统相册访问权限，请在系统设置中允许照片权限后重试。');
      }
      await Gal.putVideo(savedPath, album: 'Good-Badminton');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ 已保存到系统相册：${fileSize > 1024 * 1024 ? '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB' : '${(fileSize / 1024).toStringAsFixed(0)} KB'}'),
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '分享',
            textColor: Colors.white,
            onPressed: () async {
              final xFile = XFile(savedPath);
              await Share.shareXFiles([xFile]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 下载失败：$e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 0;
        });
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
    final url = ApiConfig.absoluteFileUrl(widget.relativeUrl);

    if (url != null && widget.available) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineNetworkVideo(title: widget.title, url: url),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _downloading ? null : _downloadVideo,
            icon: _downloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      value: _downloadProgress < 0.5 ? null : _downloadProgress,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_downloading ? '正在下载视频' : '下载到系统相册'),
          ),
        ],
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.videocam_off_outlined),
        title: Text(widget.title),
        subtitle: Text(url == null ? '暂无文件' : '文件未生成或已失效'),
      ),
    );
  }
}

class _OfflineVideoNotice extends StatelessWidget {
  const _OfflineVideoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              '为了节省手机存储空间，离线报告不会保存分析视频'
              '，服务器在线时仍可播放，有需要可自行下载到系统相册',
            ),
          ),
        ],
      ),
    );
  }
}
