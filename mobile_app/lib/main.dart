import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

const defaultBaseUrl = 'http://172.29.72.218:8001';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GoodBadmintonApp());
}

class GoodBadmintonApp extends StatelessWidget {
  const GoodBadmintonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 羽毛球复盘',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B7A75),
          primary: const Color(0xFF0B7A75),
          secondary: const Color(0xFFD6513B),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
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
  final _cornersJsonController = TextEditingController();

  late ApiClient _api;
  int _tabIndex = 0;
  bool _busy = false;
  bool _preparingPreview = false;
  bool _backendOk = false;
  PlatformFile? _videoFile;
  Map<String, dynamic>? _previewFrame;
  List<Offset> _cornerPoints = [];
  Map<String, dynamic>? _task;
  Map<String, dynamic>? _report;
  List<dynamic> _history = [];
  String? _message;
  Timer? _pollTimer;

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
    _cornersJsonController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('base_url') ?? defaultBaseUrl;
    final userId =
        prefs.getString('user_id') ??
        'guest_${DateTime.now().millisecondsSinceEpoch}';
    _baseUrlController.text = baseUrl;
    _userIdController.text = userId;
    _api = ApiClient(baseUrl);
    await prefs.setString('user_id', userId);
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
        _message = error.toString();
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
        _cornerPoints = autoCorners;
        _preparingPreview = false;
      });
      _syncCornerJson();
    } catch (error) {
      setState(() {
        _preparingPreview = false;
        _message = error.toString();
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
        _message = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _pollTask(String taskId) async {
    _pollTimer?.cancel();
    try {
      final task = await _api.get('/api/tasks/$taskId');
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
      setState(() {
        _message = error.toString();
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
      setState(() => _message = error.toString());
    }
  }

  Future<void> _openTask(String taskId) async {
    setState(() {
      _tabIndex = 2;
      _message = null;
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
      setState(() => _message = error.toString());
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
      setState(() => _message = error.toString());
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
        videoFile: _videoFile,
        previewFrame: _previewFrame,
        cornerPoints: _cornerPoints,
        busy: _busy,
        preparingPreview: _preparingPreview,
        message: _message,
        onSaveConnection: _saveConnection,
        onPickVideo: _pickVideo,
        onPreparePreview: _preparePreviewFrame,
        onAddCornerPoint: _addCornerPoint,
        onUndoCornerPoint: _undoCornerPoint,
        onResetCornerPoints: _resetCornerPoints,
        onUpload: _uploadVideo,
        onLoadDemo: _loadDemo,
      ),
      _HistoryPage(
        items: _history,
        baseUrl: _api.baseUrl,
        onRefresh: _loadHistory,
        onOpenTask: _openTask,
      ),
      _ReportPage(
        task: _task,
        report: _report,
        message: _message,
        baseUrl: _api.baseUrl,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 羽毛球训练复盘'),
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
      body: SafeArea(child: pages[_tabIndex]),
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
    required this.videoFile,
    required this.previewFrame,
    required this.cornerPoints,
    required this.busy,
    required this.preparingPreview,
    required this.message,
    required this.onSaveConnection,
    required this.onPickVideo,
    required this.onPreparePreview,
    required this.onAddCornerPoint,
    required this.onUndoCornerPoint,
    required this.onResetCornerPoints,
    required this.onUpload,
    required this.onLoadDemo,
  });

  final bool backendOk;
  final TextEditingController baseUrlController;
  final TextEditingController userIdController;
  final String baseUrl;
  final PlatformFile? videoFile;
  final Map<String, dynamic>? previewFrame;
  final List<Offset> cornerPoints;
  final bool busy;
  final bool preparingPreview;
  final String? message;
  final Future<void> Function() onSaveConnection;
  final Future<void> Function() onPickVideo;
  final Future<void> Function() onPreparePreview;
  final void Function(Offset point) onAddCornerPoint;
  final VoidCallback onUndoCornerPoint;
  final VoidCallback onResetCornerPoints;
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
                busy: busy,
                preparingPreview: preparingPreview,
                onPreparePreview: onPreparePreview,
                onAddPoint: onAddCornerPoint,
                onUndo: onUndoCornerPoint,
                onReset: onResetCornerPoints,
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
        if (message != null) ...[
          const SizedBox(height: 16),
          _MessageBox(message: message!),
        ],
      ],
    );
  }
}

class _CornerPicker extends StatefulWidget {
  const _CornerPicker({
    required this.baseUrl,
    required this.videoFile,
    required this.previewFrame,
    required this.points,
    required this.busy,
    required this.preparingPreview,
    required this.onPreparePreview,
    required this.onAddPoint,
    required this.onUndo,
    required this.onReset,
  });

  final String baseUrl;
  final PlatformFile? videoFile;
  final Map<String, dynamic>? previewFrame;
  final List<Offset> points;
  final bool busy;
  final bool preparingPreview;
  final Future<void> Function() onPreparePreview;
  final void Function(Offset point) onAddPoint;
  final VoidCallback onUndo;
  final VoidCallback onReset;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasFour ? '四个角点已选择' : '请点选$nextName',
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
          '后端选帧：${_value(preview['time_sec'])} 秒，双指可放大到 16 倍并拖动画面。',
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
            OutlinedButton.icon(
              onPressed: widget.points.isEmpty ? null : widget.onUndo,
              icon: const Icon(Icons.undo),
              label: const Text('撤销'),
            ),
            OutlinedButton.icon(
              onPressed: widget.points.isEmpty ? null : widget.onReset,
              icon: const Icon(Icons.refresh),
              label: const Text('重选角点'),
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
          '顺序：左上、右上、右下、左下。留空或重置后上传则使用后端自动识别。',
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
  });

  final List<Offset> points;
  final double imageWidth;
  final double imageHeight;

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
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFFD6513B)
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
        oldDelegate.imageHeight != imageHeight;
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({
    required this.items,
    required this.baseUrl,
    required this.onRefresh,
    required this.onOpenTask,
  });

  final List<dynamic> items;
  final String baseUrl;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String taskId) onOpenTask;

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
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onOpenTask(item['task_id'].toString()),
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
                    children: [
                      Expanded(
                        child: Text(
                          item['video_name']?.toString() ??
                              item['task_id'].toString(),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _StatusChip(status: item['status']?.toString() ?? '-'),
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
    final files = report?['files'] as Map<String, dynamic>? ?? {};
    final coaching = report?['coaching'] as Map<String, dynamic>?;
    final advice = report?['advice'] as List<dynamic>? ?? [];

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
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
          child: Wrap(
            runSpacing: 10,
            spacing: 10,
            children: [
              _Metric(
                label: '总距离',
                value: '${_value(summary['total_distance_m'])} m',
              ),
              _Metric(
                label: '最高速度',
                value: '${_value(summary['max_speed_mps'])} m/s',
              ),
              _Metric(
                label: '平均速度',
                value: '${_value(summary['avg_speed_mps'])} m/s',
              ),
              _Metric(label: '训练强度', value: _value(summary['intensity_score'])),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _VideoPanel(
          title: '精彩集锦',
          url: _optionalUrl(baseUrl, files['highlight']),
        ),
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
          child: _CoachingPanel(coaching: coaching, legacyAdvice: advice),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E1E8)),
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
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
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
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachingPanel extends StatelessWidget {
  const _CoachingPanel({required this.coaching, required this.legacyAdvice});

  final Map<String, dynamic>? coaching;
  final List<dynamic> legacyAdvice;

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

    if (!hasStructured) {
      if (legacyAdvice.isEmpty) {
        return const Text('暂无训练建议。');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: legacyAdvice
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• ${item.toString()}'),
              ),
            )
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups
          .map(
            (group) => _CoachingGroup(spec: group, items: coaching?[group.key]),
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
                    child: Center(child: CircularProgressIndicator()),
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

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6513B)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF8F2E20))),
    );
  }
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;

  Future<Map<String, dynamic>> get(String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'));
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
