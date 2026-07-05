import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/task_status.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
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

  bool get _connected => _health?['ok'] == true;

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
      if (mounted) setState(() => _error = '恢复未完成任务失败：$error');
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
      if (mounted) setState(() => _health = health);
    } catch (error) {
      if (mounted) {
        setState(() {
          _health = null;
          _error = error.toString();
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
        child: SizedBox(
          width: double.infinity,
          height: 58,
          child: FloatingActionButton.extended(
            heroTag: 'upload-video-fab',
            onPressed: _openUpload,
            elevation: 8,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            icon: const Icon(Icons.auto_awesome),
            label: const Text(
              '开始上传视频',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/badminton_dashboard_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            opacity: const AlwaysStoppedAnimation(0.19),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFF7F9F4).withValues(alpha: 0.55),
                  const Color(0xFFF7F9F4).withValues(alpha: 0.92),
                  const Color(0xFFF7F9F4),
                ],
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
            children: [
              _HeroCard(onTap: _openUpload),
              const SizedBox(height: 14),
              _ConnectionCard(
                connected: _connected,
                checking: _checking,
                health: _health,
                error: _error,
                onCheck: _checkHealth,
              ),
              if (_restoringTask) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_restoredTask != null) ...[
                const SizedBox(height: 14),
                _ActiveTaskCard(
                  task: _restoredTask!,
                  onTap: _openRestoredTask,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: _BentoActionCard(
                      height: 156,
                      icon: Icons.video_camera_back_outlined,
                      title: '智能分析',
                      subtitle: '上传比赛视频\n生成跑动报告',
                      color: const Color(0xFFE2F3E3),
                      onTap: _openUpload,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: _BentoActionCard(
                      height: 156,
                      icon: Icons.science_outlined,
                      title: 'Demo',
                      subtitle: '预览完整\n分析报告',
                      color: const Color(0xFFFFF4D9),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportPage.demo(),
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
                'AI 自动追踪球员移动、速度、覆盖范围与羽毛球轨迹，'
                '把每一次训练转化为清晰可读的数据。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 202,
      padding: const EdgeInsets.all(22),
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
            const Positioned(
              right: -12,
              top: -10,
              child: Icon(
                Icons.sports_tennis,
                size: 132,
                color: Color(0x22FFFFFF),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.17),
                    borderRadius: BorderRadius.circular(20),
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
                const Text(
                  '羽毛球 AI 视觉分析',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '上传比赛视频，一键生成数字化跑动报告',
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
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
          ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                TextButton(
                  onPressed: checking ? null : onCheck,
                  child: Text(checking ? '连接中' : '测试连接'),
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

class _BentoActionCard extends StatelessWidget {
  const _BentoActionCard({
    required this.height,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final double height;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 31,
                color: Theme.of(context).colorScheme.primary,
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.3,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
