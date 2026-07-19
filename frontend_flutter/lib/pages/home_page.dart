import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../models/task_status.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
import '../utils/user_facing_error.dart';
import 'history_page.dart';
import 'qr_scan_page.dart';
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
  static final Uri _websiteUri = Uri.parse('https://www.audacity6441.kdns.fr/');
  Map<String, dynamic>? _health;
  List<TaskStatus> _restoredTasks = const [];
  String? _error;
  bool _checking = false;
  bool _restoringTask = true;

  bool get _connected => _health?['ok'] == true;

  @override
  void initState() {
    super.initState();
    _restoreActiveTask();
  }

  Future<void> _restoreActiveTask() async {
    try {
      final taskIds = await _storage.getActiveTaskIds();
      final runningTasks = <TaskStatus>[];
      for (final taskId in taskIds) {
        try {
          final task = await _api.getTask(taskId);
          if (task.isRunning) {
            runningTasks.add(task);
          } else if (task.isCompleted) {
            await _storage.removeUpload(taskId);
          } else {
            await _storage.clearActiveTask(taskId);
          }
        } on ApiException catch (error) {
          if (error.statusCode == 404) {
            await _storage.clearActiveTask(taskId);
            continue;
          }
          rethrow;
        }
      }
      if (mounted) setState(() => _restoredTasks = runningTasks);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            error,
            fallback: '未完成任务暂时无法恢复，请稍后在历史记录中查看。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoringTask = false);
    }
  }

  Future<void> _openRestoredTask(TaskStatus task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskStatusPage(taskId: task.taskId),
      ),
    );
    if (!mounted) return;
    setState(() {
      _restoredTasks = const [];
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
      if (mounted) setState(() => _health = health);
    } catch (error) {
      if (mounted) {
        setState(() {
          _health = null;
          _error = userFacingError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _openUpload() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UploadPage()),
    );
  }

  Future<void> _openWebsite() async {
    final launched = await launchUrl(
      _websiteUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂时无法打开官方网站')),
    );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Good-Badminton',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _UploadActionButton(
          color: colorScheme.primary,
          onPressed: _openUpload,
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/badminton_dashboard_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            opacity: const AlwaysStoppedAnimation(0.52),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFF7F9F4).withValues(alpha: 0.18),
                  const Color(0xFFF7F9F4).withValues(alpha: 0.68),
                  const Color(0xFFF7F9F4).withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
              children: [
                _HeroCard(onTap: _openUpload),
                const SizedBox(height: 14),
                _VenueScanEntry(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QrScanPage()),
                  ),
                ),
                const SizedBox(height: 14),
                Offstage(
                  offstage: true,
                  child: _ConnectionCard(
                    connected: _connected,
                    checking: _checking,
                    health: _health,
                    error: _error,
                    onCheck: _checkHealth,
                  ),
                ),
                if (_restoringTask) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_restoredTasks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final task in _restoredTasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ActiveTaskCard(
                        task: task,
                        onTap: () => _openRestoredTask(task),
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  '快捷入口',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAccessCard(
                        icon: Icons.language_outlined,
                        label: '官网',
                        color: const Color(0xFFFFF4D9),
                        onTap: _openWebsite,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAccessCard(
                        icon: Icons.insights_outlined,
                        label: '历史记录',
                        color: const Color(0xFFE2F3E3),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HistoryPage(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '专业运动数字化复盘',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '每次训练结束后，先看跑动距离、速度变化和前后场活动比例，'
                  '了解这一场的体能投入是否均衡。再通过热力图观察常驻区域，'
                  '通过移动轨迹检查启动、回位、左右衔接以及防守空当。'
                  '\n\n将本场结果和自己的上一场对照，比单独追求某个数值更有意义。'
                  '你可以从站位过深、回中偏慢、某一侧覆盖不足等具体问题开始，'
                  '为下一次训练确定一个清晰目标。精彩片段则帮助你重看关键回合，'
                  '把有效的移动和击球选择保留下来。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 22),
                Text(
                  '主要功能使用指导',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                const _UsageGuide(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageGuide extends StatelessWidget {
  const _UsageGuide();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (
        Icons.video_library_outlined,
        '选择合适片段',
        '上传横屏固定机位视频，建议保留连续 30 至 60 秒，画面应完整覆盖球场'
      ),
      (Icons.crop_free_rounded, '确认球场范围', '查看预览画面，必要时依次标记球场四角，让后续结果更准确'),
      (Icons.hourglass_top_rounded, '等待分析完成', '可以离开任务页面继续使用 App，完成后到历史记录查看结果'),
      (Icons.insights_outlined, '复盘并保存', '查看数据、热力图、轨迹和精彩片段，需要长期保留的内容可下载到手机'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              ListTile(
                leading: CircleAvatar(
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  steps[index].$2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(steps[index].$3),
                trailing: Icon(steps[index].$1),
              ),
              if (index != steps.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 375;
        final height = (constraints.maxWidth * 0.52).clamp(190.0, 220.0);
        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x402E7D32),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.16,
                    child: Image.asset(
                      'assets/images/badminton_dashboard_bg.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      color: Colors.white,
                      colorBlendMode: BlendMode.screen,
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x5C0B4217),
                          Color(0x0D2E7D32),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 18 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const Text(
                          'AI SPORTS VISION',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '羽毛球 AI 视觉分析',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 22 : 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '上传比赛视频，一键生成数字化跑动报告',
                        style: TextStyle(
                          color: Color(0xDFFFFFFF),
                          fontSize: compact ? 13 : 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Text(
                            '开始分析',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 19,
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
      },
    );
  }
}

class _VenueScanEntry extends StatelessWidget {
  const _VenueScanEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扫描球馆二维码',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text('获取合作球馆的可用比赛视频'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connected,
    required this.checking,
    required this.health,
    required this.error,
    required this.onCheck,
  });

  final bool connected;
  final bool checking;
  final Map<String, dynamic>? health;
  final String? error;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFF0F8EF) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected ? const Color(0xFFB8DDBB) : const Color(0xFFE0E5DD),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                _ConnectionDot(active: connected),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? '服务器已连接' : '分析服务器',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ApiConfig.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '测试连接',
                  child: Material(
                    color: connected
                        ? const Color(0xFF2E7D32)
                        : scheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: checking ? null : onCheck,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: checking
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                Icons.power_settings_new_rounded,
                                color: connected
                                    ? Colors.white
                                    : scheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              crossFadeState: connected || error != null
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: connected
                        ? const Color(0xFFE8F5E9)
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    connected
                        ? '服务状态正常 · 模板 '
                            '${health?['default_template'] ?? '已配置'}'
                        : '连接失败：$error',
                    style: TextStyle(
                      color: connected ? const Color(0xFF1B5E20) : scheme.error,
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

class _ConnectionDot extends StatefulWidget {
  const _ConnectionDot({required this.active});

  final bool active;

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = widget.active ? 5 + (_controller.value * 7) : 0.0;
        return Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active ? const Color(0xFF43A047) : Colors.grey,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: const Color(0xFF43A047).withValues(alpha: 0.45),
                      blurRadius: glow,
                      spreadRadius: _controller.value * 2,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _ActiveTaskCard extends StatelessWidget {
  const _ActiveTaskCard({required this.task, required this.onTap});

  final TaskStatus task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF0F7ED),
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(child: Icon(Icons.auto_graph)),
        title: const Text('继续上次分析'),
        subtitle: Text('${task.videoName} · ${task.progressPercent}%'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 115;
        return Material(
          color: color,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: compact ? 96 : 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: compact ? 27 : 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(height: compact ? 7 : 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: compact ? 12 : null,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UploadActionButton extends StatefulWidget {
  const _UploadActionButton({
    required this.color,
    required this.onPressed,
  });

  final Color color;
  final VoidCallback onPressed;

  @override
  State<_UploadActionButton> createState() => _UploadActionButtonState();
}

class _UploadActionButtonState extends State<_UploadActionButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              colors: [widget.color, const Color(0xFF43A047)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x452E7D32),
                blurRadius: 20,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, color: Colors.white),
              SizedBox(width: 10),
              Text(
                '开始上传视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
