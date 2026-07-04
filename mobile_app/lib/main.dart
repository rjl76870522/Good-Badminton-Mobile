import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const defaultBaseUrl = 'http://172.29.72.218:8001';
const appDisplayName = 'AI羽毛球';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GoodBadmintonApp());
}

class GoodBadmintonApp extends StatelessWidget {
  const GoodBadmintonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B7A75),
          primary: const Color(0xFF0B7A75),
          secondary: const Color(0xFFD6513B),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FB),
          foregroundColor: Color(0xFF17201F),
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFEAF3F1),
          indicatorColor: const Color(0xFFC9EBE5),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        useMaterial3: true,
      ),
      home: const ReviewHomePage(),
    );
  }
}

class ReviewHomePage extends StatefulWidget {
  const ReviewHomePage({super.key});

  @override
  State<ReviewHomePage> createState() => _ReviewHomePageState();
}

class _ReviewHomePageState extends State<ReviewHomePage> {
  final _baseUrlController = TextEditingController(text: defaultBaseUrl);
  final _userIdController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _cornersJsonController = TextEditingController();

  late ApiClient _api;
  int _tabIndex = 0;
  bool _busy = false;
  bool _preparingPreview = false;
  bool _backendOk = false;
  PlatformFile? _videoFile;
  Map<String, dynamic>? _previewFrame;
  List<Offset> _cornerPoints = [];
  List<Offset> _autoCornerPoints = [];
  Map<String, dynamic>? _task;
  Map<String, dynamic>? _report;
  List<dynamic> _history = [];
  String? _message;
  Timer? _pollTimer;
  int _pollNetworkFailures = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(defaultBaseUrl);
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _baseUrlController.dispose();
    _userIdController.dispose();
    _nicknameController.dispose();
    _cornersJsonController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('base_url') ?? defaultBaseUrl;
    final userId =
        prefs.getString('user_id') ??
        'guest_${DateTime.now().millisecondsSinceEpoch}';
    final nickname = prefs.getString('nickname') ?? '羽毛球用户';
    _baseUrlController.text = baseUrl;
    _userIdController.text = userId;
    _nicknameController.text = nickname;
    _api = ApiClient(baseUrl);
    await prefs.setString('user_id', userId);
    await prefs.setString('nickname', nickname);
    await _checkHealth();
    await _loadHistory();
  }

  Future<void> _saveConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = _baseUrlController.text.trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    final userId = _sanitizeUserId(_userIdController.text);
    await prefs.setString('base_url', baseUrl);
    await prefs.setString('user_id', userId);
    setState(() {
      _api = ApiClient(baseUrl);
      _userIdController.text = userId;
    });
    await _checkHealth();
    await _loadHistory();
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = _nicknameController.text.trim().isEmpty
        ? '羽毛球用户'
        : _nicknameController.text.trim();
    await prefs.setString('nickname', nickname);
    setState(() {
      _nicknameController.text = nickname;
      _message = '个人信息已保存。';
    });
  }

  Future<void> _resetLocalUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本地用户'),
        content: const Text('这会在本机生成新的游客身份。服务器上的历史记录不会删除，但旧身份的历史不会再自动显示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('user_id', userId);
    await prefs.setString('nickname', '羽毛球用户');
    setState(() {
      _userIdController.text = userId;
      _nicknameController.text = '羽毛球用户';
      _history = [];
      _task = null;
      _report = null;
      _message = '已生成新的游客身份。';
      _tabIndex = 3;
    });
    await _loadHistory();
  }

  Future<void> _checkHealth() async {
    try {
      await _api.get('/api/health');
      setState(() {
        _backendOk = true;
        _message = null;
      });
    } catch (error) {
      setState(() {
        _backendOk = false;
        _message = _friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _videoFile = result.files.single;
      _previewFrame = null;
      _cornerPoints = [];
      _autoCornerPoints = [];
      _cornersJsonController.clear();
      _message = null;
    });
    await _preparePreviewFrame();
  }

  Future<void> _preparePreviewFrame() async {
    final path = _videoFile?.path;
    if (path == null) {
      setState(() => _message = '请先选择视频。');
      return;
    }

    setState(() {
      _preparingPreview = true;
      _message = null;
    });

    try {
      final preview = await _api.createPreviewFrame(
        path: path,
        filename: _videoFile?.name ?? 'training_video.mp4',
        userId: _sanitizeUserId(_userIdController.text),
      );
      final autoCorners = _parseCornerPoints(preview['auto_corners']);
      setState(() {
        _previewFrame = preview;
        _autoCornerPoints = autoCorners;
        _cornerPoints = autoCorners;
        _preparingPreview = false;
        _message = autoCorners.length == 4 ? '已自动检测并标注球场四角点。' : null;
      });
      _syncCornerJson();
    } catch (error) {
      setState(() {
        _preparingPreview = false;
        _message = _friendlyErrorMessage(error);
      });
    }
  }

  void _addCornerPoint(Offset point) {
    if (_cornerPoints.length >= 4) {
      setState(() => _message = '已经有 4 个角点，如需修改请先重选角点。');
      return;
    }
    setState(() {
      _cornerPoints = [..._cornerPoints, point];
      _message = null;
    });
    _syncCornerJson();
  }

  void _undoCornerPoint() {
    if (_cornerPoints.isEmpty) return;
    setState(
      () => _cornerPoints = _cornerPoints.sublist(0, _cornerPoints.length - 1),
    );
    _syncCornerJson();
  }

  void _resetCornerPoints() {
    setState(() {
      _cornerPoints = [];
      _message = null;
    });
    _syncCornerJson();
  }

  void _useAutoCornerPoints() {
    if (_autoCornerPoints.length != 4) {
      setState(() => _message = '当前预览帧没有可用的自动角点，请手动点选四个角点。');
      return;
    }
    setState(() {
      _cornerPoints = List<Offset>.from(_autoCornerPoints);
      _message = '已恢复自动检测角点。';
    });
    _syncCornerJson();
  }

  void _syncCornerJson() {
    _cornersJsonController.text = _cornerPoints.length == 4
        ? jsonEncode(
            _cornerPoints.map((p) => [p.dx.round(), p.dy.round()]).toList(),
          )
        : '';
  }

  Future<void> _uploadVideo() async {
    final path = _videoFile?.path;
    if (path == null) {
      setState(() => _message = '请先选择视频。');
      return;
    }

    if (_cornerPoints.isNotEmpty && _cornerPoints.length != 4) {
      setState(() => _message = '请点选四个角点，或重置后使用自动识别。');
      return;
    }
    final cornersJson = _cornerPoints.length == 4
        ? jsonEncode(
            _cornerPoints.map((p) => [p.dx.round(), p.dy.round()]).toList(),
          )
        : null;
    final sourceUploadId = _previewFrame?['source_upload_id']?.toString();

    setState(() {
      _busy = true;
      _message = null;
      _pollNetworkFailures = 0;
      _task = {'status': 'uploading', 'progress': 0.0, 'stage': 'uploading'};
      _tabIndex = 2;
    });

    try {
      final upload = await _api.uploadVideo(
        path: sourceUploadId == null ? path : null,
        filename: _videoFile?.name ?? 'training_video.mp4',
        userId: _sanitizeUserId(_userIdController.text),
        sourceUploadId: sourceUploadId,
        cornersJson: cornersJson,
      );
      final taskId = upload['task_id'] as String;
      await _pollTask(taskId);
    } catch (error) {
      setState(() {
        _message = _friendlyErrorMessage(error);
        _busy = false;
      });
    }
  }

  Future<void> _pollTask(String taskId) async {
    _pollTimer?.cancel();
    try {
      final task = await _api.get('/api/tasks/$taskId');
      _pollNetworkFailures = 0;
      setState(() => _task = task);

      final status = task['status'];
      if (status == 'completed') {
        final report = await _api.get('/api/tasks/$taskId/report');
        setState(() {
          _report = report;
          _busy = false;
          _tabIndex = 2;
        });
        await _loadHistory();
        return;
      }
      if (status == 'failed') {
        setState(() {
          _message = task['error']?.toString() ?? '视频分析失败。';
          _busy = false;
        });
        await _loadHistory();
        return;
      }

      _pollTimer = Timer(const Duration(seconds: 3), () => _pollTask(taskId));
    } catch (error) {
      if (_shouldRetryPolling(error)) {
        _pollNetworkFailures += 1;
        setState(() {
          _message = '网络连接短暂中断，正在自动重试（第 $_pollNetworkFailures 次）。';
          _busy = true;
        });
        _pollTimer = Timer(const Duration(seconds: 3), () => _pollTask(taskId));
        return;
      }
      setState(() {
        _message = _friendlyErrorMessage(error);
        _busy = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final userId = Uri.encodeQueryComponent(
        _sanitizeUserId(_userIdController.text),
      );
      final data = await _api.get('/api/history?user_id=$userId&limit=30');
      setState(() => _history = data['items'] as List<dynamic>? ?? []);
    } catch (error) {
      setState(() => _message = _friendlyErrorMessage(error));
    }
  }

  Future<void> _deleteHistoryTask(String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史记录'),
        content: const Text('会删除这条历史、上传视频和后端生成的分析文件。此操作不能恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final userId = Uri.encodeQueryComponent(
        _sanitizeUserId(_userIdController.text),
      );
      await _api.delete('/api/tasks/$taskId?user_id=$userId');
      if (!mounted) return;
      setState(() {
        _message = '已删除历史记录。';
        if (_task?['task_id']?.toString() == taskId) {
          _task = null;
          _report = null;
        }
      });
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyErrorMessage(error));
    }
  }

  Future<void> _openTask(String taskId) async {
    setState(() {
      _tabIndex = 2;
      _message = null;
      _pollNetworkFailures = 0;
    });
    try {
      final task = await _api.get('/api/tasks/$taskId');
      setState(() => _task = task);
      if (task['status'] == 'completed') {
        final report = await _api.get('/api/tasks/$taskId/report');
        setState(() => _report = report);
      } else if (task['status'] == 'failed') {
        setState(() => _message = task['error']?.toString() ?? '该任务失败。');
      } else {
        await _pollTask(taskId);
      }
    } catch (error) {
      if (_shouldRetryPolling(error)) {
        setState(() {
          _message = '网络连接短暂中断，正在重新获取任务。';
          _busy = true;
        });
        _pollTimer = Timer(const Duration(seconds: 3), () => _pollTask(taskId));
        return;
      }
      setState(() => _message = _friendlyErrorMessage(error));
    }
  }

  Future<void> _loadDemo() async {
    try {
      final data = await _api.get('/api/demo/sample');
      setState(() {
        _report = data['report'] as Map<String, dynamic>?;
        _task = data['task'] as Map<String, dynamic>?;
        _tabIndex = 2;
        _message = null;
      });
    } catch (error) {
      setState(() => _message = _friendlyErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _UploadPage(
        backendOk: _backendOk,
        baseUrlController: _baseUrlController,
        userIdController: _userIdController,
        baseUrl: _api.baseUrl,
        historyItems: _history,
        videoFile: _videoFile,
        previewFrame: _previewFrame,
        cornerPoints: _cornerPoints,
        autoCornerPoints: _autoCornerPoints,
        busy: _busy,
        preparingPreview: _preparingPreview,
        message: _message,
        onSaveConnection: _saveConnection,
        onPickVideo: _pickVideo,
        onPreparePreview: _preparePreviewFrame,
        onAddCornerPoint: _addCornerPoint,
        onUndoCornerPoint: _undoCornerPoint,
        onResetCornerPoints: _resetCornerPoints,
        onUseAutoCornerPoints: _useAutoCornerPoints,
        onUpload: _uploadVideo,
        onLoadDemo: _loadDemo,
      ),
      _HistoryPage(
        items: _history,
        baseUrl: _api.baseUrl,
        onRefresh: _loadHistory,
        onOpenTask: _openTask,
        onDeleteTask: _deleteHistoryTask,
      ),
      _ReportPage(
        task: _task,
        report: _report,
        message: _message,
        baseUrl: _api.baseUrl,
      ),
      _ProfilePage(
        nicknameController: _nicknameController,
        userId: _sanitizeUserId(_userIdController.text),
        backendOk: _backendOk,
        baseUrl: _api.baseUrl,
        historyItems: _history,
        historyCount: _history.length,
        completedCount: _history
            .where(
              (item) =>
                  item is Map && item['status']?.toString() == 'completed',
            )
            .length,
        onSaveProfile: _saveProfile,
        onResetLocalUser: _resetLocalUser,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(appDisplayName),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () async {
              await _checkHealth();
              await _loadHistory();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _tabIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: '上传',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: '报告',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _UploadPage extends StatelessWidget {
  const _UploadPage({
    required this.backendOk,
    required this.baseUrlController,
    required this.userIdController,
    required this.baseUrl,
    required this.historyItems,
    required this.videoFile,
    required this.previewFrame,
    required this.cornerPoints,
    required this.autoCornerPoints,
    required this.busy,
    required this.preparingPreview,
    required this.message,
    required this.onSaveConnection,
    required this.onPickVideo,
    required this.onPreparePreview,
    required this.onAddCornerPoint,
    required this.onUndoCornerPoint,
    required this.onResetCornerPoints,
    required this.onUseAutoCornerPoints,
    required this.onUpload,
    required this.onLoadDemo,
  });

  final bool backendOk;
  final TextEditingController baseUrlController;
  final TextEditingController userIdController;
  final String baseUrl;
  final List<dynamic> historyItems;
  final PlatformFile? videoFile;
  final Map<String, dynamic>? previewFrame;
  final List<Offset> cornerPoints;
  final List<Offset> autoCornerPoints;
  final bool busy;
  final bool preparingPreview;
  final String? message;
  final Future<void> Function() onSaveConnection;
  final Future<void> Function() onPickVideo;
  final Future<void> Function() onPreparePreview;
  final void Function(Offset point) onAddCornerPoint;
  final VoidCallback onUndoCornerPoint;
  final VoidCallback onResetCornerPoints;
  final VoidCallback onUseAutoCornerPoints;
  final Future<void> Function() onUpload;
  final Future<void> Function() onLoadDemo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _Section(
          title: '连接后端',
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    backendOk ? Icons.check_circle : Icons.error,
                    color: backendOk
                        ? const Color(0xFF23865D)
                        : const Color(0xFFD6513B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(backendOk ? '后端已连接' : '后端未连接')),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: baseUrlController,
                decoration: const InputDecoration(
                  labelText: '后端地址',
                  hintText: 'http://电脑IP:8001',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userIdController,
                decoration: const InputDecoration(
                  labelText: 'user_id',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onSaveConnection,
                  icon: const Icon(Icons.link),
                  label: const Text('保存并测试连接'),
                ),
              ),
            ],
          ),
        ),
        if (historyItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          _RecentTrainingOverview(items: historyItems),
        ],
        const SizedBox(height: 16),
        _Section(
          title: '上传视频',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                videoFile?.name ?? '尚未选择视频',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '选择视频后，后端会自动挑一帧完整球场画面用于点选角点。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              _CornerPicker(
                baseUrl: baseUrl,
                videoFile: videoFile,
                previewFrame: previewFrame,
                points: cornerPoints,
                autoPoints: autoCornerPoints,
                busy: busy,
                preparingPreview: preparingPreview,
                onPreparePreview: onPreparePreview,
                onAddPoint: onAddCornerPoint,
                onUndo: onUndoCornerPoint,
                onReset: onResetCornerPoints,
                onUseAuto: onUseAutoCornerPoints,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onPickVideo,
                      icon: const Icon(Icons.video_file_outlined),
                      label: const Text('选择视频'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onUpload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('开始分析'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: busy ? null : onLoadDemo,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('载入样例报告'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '拍摄规范',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GuidanceRow(
                icon: Icons.stay_current_landscape,
                text: '横屏拍摄，手机或相机固定，不要跟拍。',
              ),
              _GuidanceRow(
                icon: Icons.grid_on_outlined,
                text: '画面尽量包含完整球场四条边线，球场线要清楚。',
              ),
              _GuidanceRow(
                icon: Icons.timer_outlined,
                text: '正式复盘建议上传 30 秒到 3 分钟，短视频更适合功能测试。',
              ),
              _GuidanceRow(
                icon: Icons.wb_sunny_outlined,
                text: '光线稳定，球和背景反差越明显，球速和集锦越可靠。',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '分析失败处理',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GuidanceRow(
                icon: Icons.crop_free_outlined,
                text: '角点不准时，先生成预览帧，再双指放大手动点选四个球场角。',
              ),
              _GuidanceRow(
                icon: Icons.videocam_off_outlined,
                text: '视频太短、黑屏、球场没拍完整时，换一段更稳定的视频。',
              ),
              _GuidanceRow(
                icon: Icons.wifi_tethering_error_outlined,
                text: '公网访问中断时，保持后端和内网穿透窗口运行，App 会自动重连。',
              ),
            ],
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          _MessageBox(message: message!),
        ],
      ],
    );
  }
}

class _RecentTrainingOverview extends StatelessWidget {
  const _RecentTrainingOverview({required this.items});

  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    final item = items.firstWhere(
      (item) => item is Map && item['summary'] is Map,
      orElse: () => items.first,
    );
    final data = item is Map ? item : <dynamic, dynamic>{};
    final summary = data['summary'] is Map
        ? data['summary'] as Map<dynamic, dynamic>
        : <dynamic, dynamic>{};
    return _Section(
      title: '最近训练概览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['video_name']?.toString() ?? '最近一次训练',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(data['created_at']),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IntensityChip(score: _number(summary['intensity_score'])),
              _InfoPill(
                icon: Icons.route_outlined,
                label: '${_value(summary['total_distance_m'])} m',
              ),
              _InfoPill(
                icon: Icons.speed_outlined,
                label: '${_value(summary['max_speed_mps'])} m/s',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CornerPicker extends StatefulWidget {
  const _CornerPicker({
    required this.baseUrl,
    required this.videoFile,
    required this.previewFrame,
    required this.points,
    required this.autoPoints,
    required this.busy,
    required this.preparingPreview,
    required this.onPreparePreview,
    required this.onAddPoint,
    required this.onUndo,
    required this.onReset,
    required this.onUseAuto,
  });

  final String baseUrl;
  final PlatformFile? videoFile;
  final Map<String, dynamic>? previewFrame;
  final List<Offset> points;
  final List<Offset> autoPoints;
  final bool busy;
  final bool preparingPreview;
  final Future<void> Function() onPreparePreview;
  final void Function(Offset point) onAddPoint;
  final VoidCallback onUndo;
  final VoidCallback onReset;
  final VoidCallback onUseAuto;

  @override
  State<_CornerPicker> createState() => _CornerPickerState();
}

class _CornerPickerState extends State<_CornerPicker> {
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewFrame;
    if (widget.videoFile == null) {
      return _CornerInfoBox(
        icon: Icons.control_point_duplicate_outlined,
        text: '选择视频后可在清晰预览帧上点选四个球场角点。',
      );
    }

    if (widget.preparingPreview) {
      return const _CornerInfoBox(
        icon: Icons.auto_awesome,
        text: '正在上传视频并自动挑选完整球场预览帧...',
        loading: true,
      );
    }

    if (preview == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.busy ? null : widget.onPreparePreview,
          icon: const Icon(Icons.auto_awesome_motion_outlined),
          label: const Text('生成角点预览帧'),
        ),
      );
    }

    final video = preview['video'] as Map<String, dynamic>? ?? {};
    final imageWidth = (video['width'] as num?)?.toDouble() ?? 1.0;
    final imageHeight = (video['height'] as num?)?.toDouble() ?? 1.0;
    final imageUrl = _absoluteUrl(
      widget.baseUrl,
      preview['image_url'].toString(),
    );
    final nextName = _cornerName(widget.points.length);
    final hasFour = widget.points.length == 4;
    final hasAuto = widget.autoPoints.length == 4;
    final usingAuto =
        hasAuto && _sameCornerPoints(widget.points, widget.autoPoints);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasFour
                    ? (usingAuto ? '已自动检测球场角点' : '已手动选择四个角点')
                    : '请点选$nextName',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${widget.points.length}/4',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hasAuto
              ? '后端选帧：${_value(preview['time_sec'])} 秒。绿色框为自动检测结果；不贴合边线时点“手动校正”。'
              : '后端选帧：${_value(preview['time_sec'])} 秒。未检测到稳定角点，请双指放大后手动点选四个角点。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: imageWidth / imageHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final displayWidth = constraints.maxWidth;
                  final displayHeight = constraints.maxHeight;
                  return InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1,
                    maxScale: 16,
                    boundaryMargin: const EdgeInsets.all(600),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: hasFour
                          ? null
                          : (details) {
                              final local = details.localPosition;
                              if (local.dx < 0 ||
                                  local.dy < 0 ||
                                  local.dx > displayWidth ||
                                  local.dy > displayHeight) {
                                return;
                              }
                              widget.onAddPoint(
                                Offset(
                                  local.dx / displayWidth * imageWidth,
                                  local.dy / displayHeight * imageHeight,
                                ),
                              );
                            },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(imageUrl, fit: BoxFit.fill),
                          CustomPaint(
                            painter: _CornerOverlayPainter(
                              points: widget.points,
                              imageWidth: imageWidth,
                              imageHeight: imageHeight,
                              isAuto: usingAuto,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (hasAuto)
              OutlinedButton.icon(
                onPressed: usingAuto ? null : widget.onUseAuto,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('使用自动角点'),
              ),
            OutlinedButton.icon(
              onPressed: widget.points.isEmpty ? null : widget.onReset,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('手动校正'),
            ),
            OutlinedButton.icon(
              onPressed: widget.points.isEmpty || usingAuto
                  ? null
                  : widget.onUndo,
              icon: const Icon(Icons.undo),
              label: const Text('撤销手动点'),
            ),
            OutlinedButton.icon(
              onPressed: () => _transformController.value = Matrix4.identity(),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('重置缩放'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '手动校正顺序：左上、右上、右下、左下。上传时会使用当前画面上的四个角点。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }

  String _cornerName(int index) {
    const names = ['左上角', '右上角', '右下角', '左下角'];
    if (index < 0 || index >= names.length) return '角点';
    return names[index];
  }
}

class _CornerInfoBox extends StatelessWidget {
  const _CornerInfoBox({
    required this.icon,
    required this.text,
    this.loading = false,
  });

  final IconData icon;
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E1E8)),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: const Color(0xFF0B7A75)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CornerOverlayPainter extends CustomPainter {
  _CornerOverlayPainter({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
    required this.isAuto,
  });

  final List<Offset> points;
  final double imageWidth;
  final double imageHeight;
  final bool isAuto;

  @override
  void paint(Canvas canvas, Size size) {
    final scaled = points
        .map(
          (point) => Offset(
            point.dx / imageWidth * size.width,
            point.dy / imageHeight * size.height,
          ),
        )
        .toList();
    final linePaint = Paint()
      ..color = isAuto ? const Color(0xFF21B36B) : const Color(0xFFFFD54F)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = isAuto ? const Color(0xFF21B36B) : const Color(0xFFD6513B)
      ..style = PaintingStyle.fill;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    if (scaled.length > 1) {
      final path = Path()..moveTo(scaled.first.dx, scaled.first.dy);
      for (final point in scaled.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (scaled.length == 4) {
        path.close();
      }
      canvas.drawPath(path, linePaint);
    }

    for (var i = 0; i < scaled.length; i++) {
      final point = scaled[i];
      canvas.drawCircle(point, 8, fillPaint);
      canvas.drawCircle(point, 8, linePaint);
      textPainter.text = TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, point + const Offset(11, -17));
    }
  }

  @override
  bool shouldRepaint(covariant _CornerOverlayPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.isAuto != isAuto;
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({
    required this.items,
    required this.baseUrl,
    required this.onRefresh,
    required this.onOpenTask,
    required this.onDeleteTask,
  });

  final List<dynamic> items;
  final String baseUrl;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String taskId) onOpenTask;
  final Future<void> Function(String taskId) onDeleteTask;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 52, color: Colors.black38),
            const SizedBox(height: 10),
            const Text('暂无历史记录'),
            TextButton(onPressed: onRefresh, child: const Text('刷新')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index] as Map<String, dynamic>;
          final summary = item['summary'] as Map<String, dynamic>? ?? {};
          final thumb = item['thumbnail']?.toString();
          final taskId = item['task_id'].toString();
          final createdAt = _formatTimestamp(item['created_at']);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onOpenTask(taskId),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD8E1E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (thumb != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          _absoluteUrl(baseUrl, thumb),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['video_name']?.toString() ?? taskId,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              createdAt,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '删除历史',
                        onPressed: () => onDeleteTask(taskId),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const SizedBox(width: 4),
                      _StatusChip(status: item['status']?.toString() ?? '-'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _IntensityChip(
                        score: _number(summary['intensity_score']),
                      ),
                      _InfoPill(
                        icon: Icons.route_outlined,
                        label: '${_value(summary['total_distance_m'])} m',
                      ),
                      _InfoPill(
                        icon: Icons.speed_outlined,
                        label: '${_value(summary['max_speed_mps'])} m/s',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniMetric(
                          label: '强度',
                          value: _value(summary['intensity_score']),
                        ),
                      ),
                      Expanded(
                        child: _MiniMetric(
                          label: '最高速度',
                          value: '${_value(summary['max_speed_mps'])} m/s',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReportPage extends StatelessWidget {
  const _ReportPage({
    required this.task,
    required this.report,
    required this.message,
    required this.baseUrl,
  });

  final Map<String, dynamic>? task;
  final Map<String, dynamic>? report;
  final String? message;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final progress = ((task?['progress'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      1.0,
    );
    final status = task?['status']?.toString();
    final summary = report?['summary'] as Map<String, dynamic>? ?? {};
    final video = report?['video'] as Map<String, dynamic>? ?? {};
    final files = report?['files'] as Map<String, dynamic>? ?? {};
    final coaching = report?['coaching'] as Map<String, dynamic>?;
    final advice = report?['advice'] as List<dynamic>? ?? [];
    final reportSummary =
        report?['report_summary']?.toString() ??
        _localReportSummary(summary: summary, video: video);
    final highlightSegments =
        report?['highlight_segments'] as List<dynamic>? ?? [];

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (!_isEmptySummary(summary)) ...[
          _Section(title: '本次总结', child: Text(reportSummary)),
          const SizedBox(height: 16),
        ],
        _Section(
          title: '任务状态',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusChip(status: status ?? 'waiting'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_stageText(task?['stage']?.toString(), status)),
                  ),
                  Text('${(progress * 100).round()}%'),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
            ],
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          _MessageBox(message: message!),
        ],
        const SizedBox(height: 16),
        _Section(
          title: '核心指标',
          child: _MetricGrid(
            metrics: [
              _Metric(
                label: '总距离',
                value: '${_value(summary['total_distance_m'])} m',
                note: '两名球员稳定轨迹距离合计，不是单个球员距离。',
              ),
              _Metric(
                label: '最高速度',
                value: '${_value(summary['max_speed_mps'])} m/s',
                note: '取稳定速度样本的高位值，减少单帧误检影响。',
              ),
              _Metric(
                label: '平均速度',
                value: '${_value(summary['avg_speed_mps'])} m/s',
                note: '按每名球员有效时长加权后的平均移动速度，不把两人速度相加。',
              ),
              _Metric(
                label: '训练强度',
                value: _value(summary['intensity_score']),
                note: '综合单位时间移动强度、最高稳定速度和有效时长的 0-100 分。',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '进阶指标',
          child: _MetricGrid(
            metrics: [
              _Metric(
                label: '有效分析时长',
                value: '${_value(_effectiveDuration(summary, video))} s',
                note: '真正检测到稳定球员轨迹的时间。短视频结果波动会更大。',
              ),
              _Metric(
                label: '场地覆盖面积',
                value: '${_value(summary['coverage_area_m2'])} m²',
                note: '按轨迹横向跨度和纵向跨度估算，用于判断覆盖范围。',
              ),
              _Metric(
                label: '前后场比例',
                value:
                    '${_percent(summary['front_court_ratio'])} / ${_percent(summary['back_court_ratio'])}',
                note: '前场与后场停留比例，帮助判断训练落点是否均衡。',
              ),
              _Metric(
                label: '左右场比例',
                value:
                    '${_percent(summary['left_court_ratio'])} / ${_percent(summary['right_court_ratio'])}',
                note: '左半场与右半场覆盖比例，帮助发现偏侧训练。',
              ),
              _Metric(
                label: '高强度移动次数',
                value: _value(summary['high_intensity_moves']),
                note: '速度超过阈值的移动样本数量，可代表启动和冲刺频次。',
              ),
              _Metric(
                label: '羽毛球识别占比',
                value: _percent(summary['shuttlecock_ratio']),
                note: '球识别越稳定，球速和精彩集锦判断越可靠。',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _VideoPanel(
          title: '精彩集锦',
          url: _optionalUrl(baseUrl, files['highlight']),
        ),
        if (highlightSegments.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            title: '集锦入选理由',
            child: _HighlightSegmentsPanel(segments: highlightSegments),
          ),
        ],
        const SizedBox(height: 16),
        _VideoPanel(
          title: '分析视频',
          url: _optionalUrl(baseUrl, files['analysis_video']),
        ),
        const SizedBox(height: 16),
        _ImagePanel(title: '热力图', url: _optionalUrl(baseUrl, files['heatmap'])),
        const SizedBox(height: 16),
        _ImagePanel(
          title: '轨迹图',
          url: _optionalUrl(baseUrl, files['trajectory']),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '训练建议',
          child: _CoachingPanel(
            coaching: coaching,
            legacyAdvice: advice,
            summary: summary,
            video: video,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E1E8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F203833),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2EAEE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              note,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics
              .map((metric) => SizedBox(width: width, child: metric))
              .toList(),
        );
      },
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF0B7A75)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _HighlightSegmentsPanel extends StatelessWidget {
  const _HighlightSegmentsPanel({required this.segments});

  final List<dynamic> segments;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: segments.map((segment) {
        final data = segment is Map ? segment : <dynamic, dynamic>{};
        final metrics = data['display_metrics'] is Map
            ? data['display_metrics'] as Map<dynamic, dynamic>
            : data['metrics'] is Map
            ? data['metrics'] as Map<dynamic, dynamic>
            : <dynamic, dynamic>{};
        final tags = data['tags'] is List
            ? (data['tags'] as List).map((item) => item.toString()).toList()
            : _localHighlightTags(metrics);
        final start = _number(data['start_sec']);
        final end = _number(data['end_sec']);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2EAEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_value(start)}s - ${_value(end)}s',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                data['reason_zh']?.toString() ?? '该片段综合速度和移动距离较高，因此被选入精彩集锦。',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tags.map((tag) => Chip(label: Text(tag))).toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.speed_outlined,
                    label: '最高速度 ${_value(metrics['player_peak_mps'])} m/s',
                  ),
                  _InfoPill(
                    icon: Icons.route_outlined,
                    label: '移动距离 ${_value(metrics['player_distance_m'])} m',
                  ),
                  _InfoPill(
                    icon: Icons.sports_tennis_outlined,
                    label: '球速样本 ${_value(metrics['shuttle_peak_px_s'])} px/s',
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.nicknameController,
    required this.userId,
    required this.backendOk,
    required this.baseUrl,
    required this.historyItems,
    required this.historyCount,
    required this.completedCount,
    required this.onSaveProfile,
    required this.onResetLocalUser,
  });

  final TextEditingController nicknameController;
  final String userId;
  final bool backendOk;
  final String baseUrl;
  final List<dynamic> historyItems;
  final int historyCount;
  final int completedCount;
  final Future<void> Function() onSaveProfile;
  final Future<void> Function() onResetLocalUser;

  @override
  Widget build(BuildContext context) {
    final archive = _trainingArchive(historyItems);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _Section(
          title: '训练档案',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nicknameController.text.trim().isEmpty
                    ? '游客训练档案'
                    : '${nicknameController.text.trim()} 的训练档案',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  hintText: '羽毛球用户',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSaveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存昵称'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '训练概览',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ArchiveTile(label: '完成训练', value: '$completedCount 次'),
              _ArchiveTile(
                label: '累计移动',
                value: '${_value(archive.totalDistance)} m',
              ),
              _ArchiveTile(
                label: '速度纪录',
                value: '${_value(archive.maxSpeed)} m/s',
              ),
              _ArchiveTile(label: '平均强度', value: _value(archive.avgIntensity)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '游客身份',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: '用户 ID', value: userId),
              const SizedBox(height: 10),
              _InfoRow(
                label: '训练记录',
                value: '$completedCount 次完成 / $historyCount 条历史',
              ),
              const SizedBox(height: 10),
              _InfoRow(label: '后端状态', value: backendOk ? '已连接' : '未连接'),
              const SizedBox(height: 10),
              _InfoRow(label: '后端地址', value: baseUrl),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onResetLocalUser,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('清空本地用户并重新生成'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '隐私说明',
          child: Text(
            '当前版本使用游客模式，不需要手机号和密码。App 会把游客 ID 和昵称保存在本机；上传的视频会发送到用户填写的后端服务器，用于生成训练报告、热力图、轨迹图和精彩集锦。清空本地用户只会更换本机游客身份，不会删除服务器已保存的历史文件。',
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF4F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2EAEE)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachingPanel extends StatelessWidget {
  const _CoachingPanel({
    required this.coaching,
    required this.legacyAdvice,
    required this.summary,
    required this.video,
  });

  final Map<String, dynamic>? coaching;
  final List<dynamic> legacyAdvice;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> video;

  @override
  Widget build(BuildContext context) {
    final groups = [
      _CoachingGroupSpec('strengths', '当前优点', '暂无明显优点。'),
      _CoachingGroupSpec('weaknesses', '目前缺点', '暂无明显缺点。'),
      _CoachingGroupSpec('improvements', '改进建议', '暂无改进建议。'),
    ];
    final hasStructured = groups.any((group) {
      final items = coaching?[group.key];
      return items is List && items.isNotEmpty;
    });
    final effectiveCoaching = hasStructured
        ? coaching!
        : _fallbackCoaching(summary: summary, video: video);

    if (!hasStructured && legacyAdvice.isEmpty && _isEmptySummary(summary)) {
      return const Text('暂无训练建议。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups
          .map(
            (group) => _CoachingGroup(
              spec: group,
              items: effectiveCoaching[group.key],
            ),
          )
          .toList(),
    );
  }
}

class _CoachingGroup extends StatelessWidget {
  const _CoachingGroup({required this.spec, required this.items});

  final _CoachingGroupSpec spec;
  final Object? items;

  @override
  Widget build(BuildContext context) {
    final itemList = items is List ? items as List<dynamic> : <dynamic>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF4F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spec.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (itemList.isEmpty)
                Text(spec.emptyText)
              else
                ...itemList.map((item) => _CoachingItem(item: item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachingItem extends StatelessWidget {
  const _CoachingItem({required this.item});

  final Object? item;

  @override
  Widget build(BuildContext context) {
    final data = item is Map
        ? item as Map<dynamic, dynamic>
        : <dynamic, dynamic>{};
    final title = data['title']?.toString() ?? '';
    final detail = data['detail']?.toString() ?? '';
    final basis = data['basis']?.toString() ?? '';
    final trainingFocus = data['training_focus']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? '建议' : title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (basis.isNotEmpty) Text(basis),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          if (trainingFocus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(trainingFocus),
            ),
        ],
      ),
    );
  }
}

class _CoachingGroupSpec {
  const _CoachingGroupSpec(this.key, this.title, this.emptyText);

  final String key;
  final String title;
  final String emptyText;
}

Map<String, dynamic> _fallbackCoaching({
  required Map<String, dynamic> summary,
  required Map<String, dynamic> video,
}) {
  final distance = _number(summary['total_distance_m']);
  final maxSpeed = _number(summary['max_speed_mps']);
  final avgSpeed = _number(summary['avg_speed_mps']);
  final intensity = _number(summary['intensity_score']);
  final duration = _number(summary['active_time_sec']) > 0
      ? _number(summary['active_time_sec'])
      : _number(video['duration_sec']);
  final coverage = _number(summary['coverage_area_m2']);
  final shuttleRatio = _number(summary['shuttlecock_ratio']);

  final strengths = <Map<String, String>>[];
  final weaknesses = <Map<String, String>>[];
  final improvements = <Map<String, String>>[];

  if (distance > 0) {
    strengths.add({
      'title': maxSpeed >= 4.5 ? '爆发启动较明显' : '已形成有效运动轨迹',
      'basis': maxSpeed >= 4.5
          ? '本次最高速度约 ${_value(maxSpeed)} m/s，说明短距离启动和抢点有表现。'
          : '本次记录到约 ${_value(distance)} m 的移动距离，可用于基础复盘。',
      'detail': '报告已能从视频中提取移动距离、速度和轨迹数据。',
      'training_focus': '后续重点看每次击球后的回中是否稳定，而不只看单次速度。',
    });
  }
  if (coverage > 0) {
    strengths.add({
      'title': '场地覆盖可观察',
      'basis': '轨迹覆盖约 ${_value(coverage)} 平方米。',
      'detail': '热力图和轨迹图可以帮助判断训练是否集中在局部区域。',
      'training_focus': '观察前后场、左右侧是否均衡，避免长期只练习固定落点。',
    });
  }
  if (strengths.isEmpty) {
    strengths.add({
      'title': '已完成一次视频分析',
      'basis': '当前报告包含基础指标和可视化结果。',
      'detail': '这份历史报告缺少新版训练建议字段，App 已按指标做本地解读。',
      'training_focus': '重新上传同一视频可获得后端新版三段式建议。',
    });
  }

  if (duration > 0 && duration < 25) {
    weaknesses.add({
      'title': '样本时长偏短',
      'basis': '本次有效片段约 ${_value(duration)} 秒。',
      'detail': '短视频更适合功能测试，训练强度和覆盖范围判断会不够稳定。',
      'training_focus': '正式复盘建议上传 30 秒到 3 分钟的连续训练片段。',
    });
  }
  if (maxSpeed >= 4.5 && avgSpeed > 0 && avgSpeed < 2.0) {
    weaknesses.add({
      'title': '爆发后连续衔接还可提升',
      'basis': '最高速度 ${_value(maxSpeed)} m/s，平均速度 ${_value(avgSpeed)} m/s。',
      'detail': '单次启动速度不错，但连续回位和下一拍启动可能还有提升空间。',
      'training_focus': '训练时关注“启动、到位、回中、再启动”的完整链条。',
    });
  }
  if (intensity > 0 && intensity < 50) {
    weaknesses.add({
      'title': '整体训练强度偏低',
      'basis': '训练强度评分为 ${_value(intensity)}。',
      'detail': '当前片段更像轻量练习或短片段测试，负荷不足以反映完整训练状态。',
      'training_focus': '可以增加连续多拍、前后场衔接和左右调动。',
    });
  }
  if (shuttleRatio > 0 && shuttleRatio < 0.45) {
    weaknesses.add({
      'title': '羽毛球识别稳定性不足',
      'basis': '羽毛球识别占比约 ${_value(shuttleRatio * 100)}%。',
      'detail': '球识别不足会影响球速和精彩集锦判断。',
      'training_focus': '尽量使用光线稳定、球和背景反差明显、完整覆盖球场的视频。',
    });
  }
  if (weaknesses.isEmpty) {
    weaknesses.add({
      'title': '旧报告缺少更细分判断',
      'basis': '这份历史报告没有新版 coaching 字段。',
      'detail': 'App 已按核心指标补充解读，但重新分析会更准确。',
      'training_focus': '后端重启到最新版后重新上传视频，可生成更完整建议。',
    });
  }

  improvements.add({
    'title': '分腿垫步 + 回中衔接',
    'basis': maxSpeed >= 4.5 ? '适合把爆发速度转成连续回合能力。' : '适合建立稳定启动节奏。',
    'detail': '重点练从上一拍恢复到下一拍启动的衔接。',
    'training_focus': '做六点影子步：每次到点后回中，30 秒训练、30 秒休息，做 4 组。',
  });
  improvements.add({
    'title': '多方向连续移动',
    'basis': intensity < 60 ? '用于提升整体训练强度。' : '用于保持高强度下的移动质量。',
    'detail': '比赛移动通常是多个方向连续切换，不能只练单点启动。',
    'training_focus': '做 30-60 秒多方向喂球或抛球，休息 60-90 秒，做 4 组。',
  });
  improvements.add({
    'title': '固定机位和角点校准',
    'basis': '拍摄角度会直接影响距离、速度、热力图和轨迹判断。',
    'detail': '完整球场和准确角点是训练报告可信的前提。',
    'training_focus': '横屏固定拍摄，尽量拍到完整双打边线和底线；自动角点不准时手动放大点选四角。',
  });

  return {
    'strengths': strengths.take(3).toList(),
    'weaknesses': weaknesses.take(3).toList(),
    'improvements': improvements.take(3).toList(),
  };
}

bool _isEmptySummary(Map<String, dynamic> summary) {
  return _number(summary['total_distance_m']) == 0 &&
      _number(summary['max_speed_mps']) == 0 &&
      _number(summary['avg_speed_mps']) == 0 &&
      _number(summary['intensity_score']) == 0;
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _VideoPanel extends StatefulWidget {
  const _VideoPanel({required this.title, required this.url});

  final String title;
  final String? url;

  @override
  State<_VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<_VideoPanel> {
  VideoPlayerController? _controller;
  Future<void>? _initialize;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant _VideoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _setup();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _setup() {
    final url = widget.url;
    if (url == null) {
      _controller = null;
      _initialize = null;
      return;
    }
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _initialize = _controller!.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: widget.title,
      child: widget.url == null
          ? const AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(child: Text('暂无视频')),
            )
          : FutureBuilder(
              future: _initialize,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _VideoLoadingHint(),
                  );
                }
                final controller = _controller!;
                return Column(
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              controller.value.isPlaying
                                  ? controller.pause()
                                  : controller.play();
                            });
                          },
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _VideoLoadingHint extends StatelessWidget {
  const _VideoLoadingHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text(
            '正在加载视频，切换页面回来时可能需要几秒缓冲。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({required this.title, required this.url});

  final String title;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      child: url == null
          ? const AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(child: Text('暂无图片')),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url!, fit: BoxFit.contain),
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => const Color(0xFF23865D),
      'processing' || 'queued' || 'uploading' => const Color(0xFFB7791F),
      'failed' => const Color(0xFFD6513B),
      _ => Colors.black45,
    };
    return Chip(
      label: Text(
        _statusText(status),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IntensityChip extends StatelessWidget {
  const _IntensityChip({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 70
        ? const Color(0xFFD6513B)
        : score >= 45
        ? const Color(0xFFB7791F)
        : const Color(0xFF23865D);
    final label = score >= 70
        ? '高强度'
        : score >= 45
        ? '中等强度'
        : '轻强度';
    return Chip(
      label: Text(score > 0 ? '$label ${_value(score)}' : '暂无强度'),
      avatar: Icon(Icons.local_fire_department, color: color, size: 18),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2EAEE)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF0B7A75)),
            const SizedBox(width: 5),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = _messageTone(message);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tone.icon, color: tone.foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: tone.foreground)),
          ),
        ],
      ),
    );
  }
}

class _MessageTone {
  const _MessageTone({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
}

_MessageTone _messageTone(String message) {
  final isRecovering =
      message.contains('自动重试') ||
      message.contains('重新获取任务') ||
      message.contains('短暂中断');
  final isSuccess =
      message.startsWith('已') ||
      message.contains('成功') ||
      message.contains('后端已连接');
  if (isRecovering) {
    return const _MessageTone(
      background: Color(0xFFEFF8F3),
      border: Color(0xFF55B87A),
      foreground: Color(0xFF1F7A4B),
      icon: Icons.sync,
    );
  }
  if (isSuccess) {
    return const _MessageTone(
      background: Color(0xFFEFF8F3),
      border: Color(0xFF55B87A),
      foreground: Color(0xFF1F7A4B),
      icon: Icons.check_circle_outline,
    );
  }
  return const _MessageTone(
    background: Color(0xFFFFF1EE),
    border: Color(0xFFD6513B),
    foreground: Color(0xFF8F2E20),
    icon: Icons.error_outline,
  );
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;

  Future<Map<String, dynamic>> get(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'));
    return _decodeResponse(response.statusCode, response.bodyBytes);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await http.delete(Uri.parse('$baseUrl$path'));
    return _decodeResponse(response.statusCode, response.bodyBytes);
  }

  Future<Map<String, dynamic>> uploadVideo({
    String? path,
    required String filename,
    required String userId,
    String? sourceUploadId,
    String? cornersJson,
  }) async {
    if ((path == null || path.isEmpty) &&
        (sourceUploadId == null || sourceUploadId.isEmpty)) {
      throw ApiException('请先选择视频。');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/videos/upload'),
    );
    request.fields['user_id'] = userId;
    request.fields['language'] = 'zh';
    request.fields['pose_mode'] = 'balanced';
    request.fields['keep_audio'] = 'true';
    if (sourceUploadId != null && sourceUploadId.isNotEmpty) {
      request.fields['source_upload_id'] = sourceUploadId;
    }
    if (cornersJson != null && cornersJson.isNotEmpty) {
      request.fields['corners_json'] = cornersJson;
    }
    if (path != null && path.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('file', path, filename: filename),
      );
    }
    final streamed = await request.send();
    final bytes = await streamed.stream.toBytes();
    return _decodeResponse(streamed.statusCode, bytes);
  }

  Future<Map<String, dynamic>> createPreviewFrame({
    required String path,
    required String filename,
    required String userId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/videos/preview-frame'),
    );
    request.fields['user_id'] = userId;
    request.files.add(
      await http.MultipartFile.fromPath('file', path, filename: filename),
    );
    final streamed = await request.send();
    final bytes = await streamed.stream.toBytes();
    return _decodeResponse(streamed.statusCode, bytes);
  }

  Map<String, dynamic> _decodeResponse(int statusCode, List<int> bodyBytes) {
    final text = utf8.decode(bodyBytes);
    final data = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (statusCode >= 400) {
      final detail = data['detail'];
      if (detail is Map<String, dynamic>) {
        final parts = [
          detail['message']?.toString(),
          detail['hint']?.toString(),
          detail['code'] == null ? null : '错误码：${detail['code']}',
        ].whereType<String>();
        throw ApiException(parts.join(' '));
      }
      throw ApiException('请求失败，HTTP $statusCode');
    }
    return data;
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _shouldRetryPolling(Object error) {
  if (error is ApiException) return false;
  return _isNetworkInterruption(error);
}

bool _isNetworkInterruption(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('handshake') ||
      text.contains('connection terminated') ||
      text.contains('connection abort') ||
      text.contains('connection reset') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('timed out') ||
      text.contains('timeout');
}

String _friendlyErrorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (_isNetworkInterruption(error)) {
    return '网络连接中断，请确认后端和内网穿透窗口仍在运行，然后稍后重试。';
  }
  return error.toString();
}

String _sanitizeUserId(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^\w.-]'), '_');
  if (normalized.isEmpty) return 'guest';
  return normalized.length > 64 ? normalized.substring(0, 64) : normalized;
}

List<Offset> _parseCornerPoints(Object? value) {
  if (value is! List || value.length != 4) return [];
  final points = <Offset>[];
  for (final item in value) {
    if (item is! List || item.length < 2) return [];
    final x = item[0];
    final y = item[1];
    if (x is! num || y is! num) return [];
    points.add(Offset(x.toDouble(), y.toDouble()));
  }
  return points;
}

bool _sameCornerPoints(List<Offset> a, List<Offset> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i].dx - b[i].dx).abs() > 0.5 || (a[i].dy - b[i].dy).abs() > 0.5) {
      return false;
    }
  }
  return true;
}

String _absoluteUrl(String baseUrl, String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '$baseUrl${path.startsWith('/') ? path : '/$path'}';
}

String? _optionalUrl(String baseUrl, Object? path) {
  final text = path?.toString();
  if (text == null || text.isEmpty || text == 'null') return null;
  return _absoluteUrl(baseUrl, text);
}

String _value(Object? value) {
  if (value == null) return '-';
  if (value is num) {
    if (value.abs() >= 100) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return value.toString();
}

String _percent(Object? value) {
  final number = _number(value);
  if (number <= 0) return '-';
  return '${_value(number * 100)}%';
}

double _effectiveDuration(
  Map<String, dynamic> summary,
  Map<String, dynamic> video,
) {
  final active = _number(summary['active_time_sec']);
  if (active > 0) return active;
  return _number(video['duration_sec']);
}

String _localReportSummary({
  required Map<String, dynamic> summary,
  required Map<String, dynamic> video,
}) {
  final intensity = _number(summary['intensity_score']);
  final maxSpeed = _number(summary['max_speed_mps']);
  final duration = _effectiveDuration(summary, video);
  final intensityText = intensity >= 70
      ? '较高'
      : intensity >= 45
      ? '中等'
      : '偏低';
  final speedText = maxSpeed >= 4.5 ? '爆发移动明显' : '移动节奏较平稳';
  if (duration > 0 && duration < 25) {
    return '本次片段较短，训练强度$intensityText，$speedText，可作为快速复盘样例。';
  }
  return '本次训练强度$intensityText，$speedText，建议结合热力图和轨迹图观察场地覆盖是否均衡。';
}

String _formatTimestamp(Object? value) {
  final seconds = _number(value);
  if (seconds <= 0) return '时间未知';
  final dateTime = DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
  );
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}

List<String> _localHighlightTags(Map<dynamic, dynamic> metrics) {
  final tags = <String>[];
  if (_number(metrics['player_peak_mps']) >= 5.0) tags.add('快速启动');
  if (_number(metrics['player_distance_m']) >= 12.0) tags.add('高强度跑动');
  if (_number(metrics['player_distance_m']) >= 18.0) tags.add('覆盖范围大');
  if (_number(metrics['shuttle_peak_px_s']) >= 1000.0) tags.add('高速来球');
  return tags.isEmpty ? ['精彩回合'] : tags;
}

_TrainingArchive _trainingArchive(List<dynamic> items) {
  var totalDistance = 0.0;
  var maxSpeed = 0.0;
  var intensityTotal = 0.0;
  var intensityCount = 0;
  for (final item in items) {
    if (item is! Map) continue;
    final summary = item['summary'];
    if (summary is! Map) continue;
    totalDistance += _number(summary['total_distance_m']);
    maxSpeed = maxSpeed < _number(summary['max_speed_mps'])
        ? _number(summary['max_speed_mps'])
        : maxSpeed;
    final intensity = _number(summary['intensity_score']);
    if (intensity > 0) {
      intensityTotal += intensity;
      intensityCount += 1;
    }
  }
  return _TrainingArchive(
    totalDistance: totalDistance,
    maxSpeed: maxSpeed,
    avgIntensity: intensityCount == 0 ? 0.0 : intensityTotal / intensityCount,
  );
}

class _TrainingArchive {
  const _TrainingArchive({
    required this.totalDistance,
    required this.maxSpeed,
    required this.avgIntensity,
  });

  final double totalDistance;
  final double maxSpeed;
  final double avgIntensity;
}

String _statusText(String status) {
  return switch (status) {
    'queued' => '排队',
    'processing' => '分析中',
    'completed' => '完成',
    'failed' => '失败',
    'uploading' => '上传中',
    'waiting' => '等待',
    _ => status,
  };
}

String _stageText(String? stage, String? status) {
  return switch (stage) {
    'queued' => '任务排队中',
    'preparing_court' => '识别球场',
    'analyzing_video' => '分析视频',
    'building_highlight' => '生成精彩集锦',
    'building_report' => '生成训练报告',
    'completed' => '分析完成',
    'failed' => '分析失败',
    'uploading' => '上传视频',
    _ => _statusText(status ?? 'waiting'),
  };
}
