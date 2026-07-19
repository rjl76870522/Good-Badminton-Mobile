import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../config/api_config.dart';
import '../models/preview_frame.dart';
import '../utils/corner_mapper.dart';

class CornerPickerPage extends StatefulWidget {
  const CornerPickerPage({
    super.key,
    required this.preview,
    this.localVideoPath,
  });

  final PreviewFrame preview;
  final String? localVideoPath;

  @override
  State<CornerPickerPage> createState() => _CornerPickerPageState();
}

class _CornerPickerPageState extends State<CornerPickerPage>
    with SingleTickerProviderStateMixin {
  static const _labels = ['左上角', '右上角', '右下角', '左下角'];
  late List<CourtPoint> _points;
  final TransformationController _transformCtrl = TransformationController();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  VideoPlayerController? _localVideoController;
  bool _localVideoReady = false;

  @override
  void initState() {
    super.initState();
    _points = widget.preview.autoCorners.length == 4
        ? List.of(widget.preview.autoCorners)
        : [];
    _initializeLocalVideoPreview();
  }

  Future<void> _initializeLocalVideoPreview() async {
    final path = widget.localVideoPath;
    if (path == null || path.isEmpty || !await File(path).exists()) return;
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final seekTarget = Duration(
        milliseconds: (widget.preview.timeSec * 1000).round(),
      );
      await controller.seekTo(seekTarget);
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _localVideoController = controller;
        _localVideoReady = true;
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  Size get _videoSize => Size(
        widget.preview.video.width.toDouble(),
        widget.preview.video.height.toDouble(),
      );

  void _useAutoCorners() {
    setState(() => _points = List.of(widget.preview.autoCorners));
  }

  void _addPoint(Offset displayPoint, Size displaySize) {
    if (_points.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _points.add(
        CornerMapper.displayToVideo(
          displayPoint: displayPoint,
          displaySize: displaySize,
          videoSize: _videoSize,
        ),
      );
    });
  }

  Widget _buildPreviewImage(String imageUrl) {
    final localController = _localVideoController;
    if (_localVideoReady && localController != null) {
      final size = localController.value.size;
      return ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: size.width == 0 ? _videoSize.width : size.width,
            height: size.height == 0 ? _videoSize.height : size.height,
            child: VideoPlayer(localController),
          ),
        ),
      );
    }

    final dataUrl = widget.preview.imageDataUrl;
    if (dataUrl != null && dataUrl.startsWith('data:image/')) {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex > 0) {
        try {
          final bytes = base64Decode(dataUrl.substring(commaIndex + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
          );
        } on FormatException {
          // Fall through to the network URL below.
        }
      }
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.fill,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return const ColoredBox(
          color: Colors.black38,
          child: Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (_, error, __) => ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '预览图加载失败：$error\n$imageUrl',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transformCtrl.dispose();
    _localVideoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.absoluteFileUrl(widget.preview.imageUrl)!;
    final nextLabel =
        _points.length < 4 ? '请点击：${_labels[_points.length]}' : '四个角点已设置';
    return Scaffold(
      backgroundColor: const Color(0xFF0D1711),
      appBar: AppBar(
        title: const Text('球场智能校准'),
        backgroundColor: const Color(0xFF0D1711),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, viewport) {
                return InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 1,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(360),
                  child: SizedBox(
                    width: viewport.maxWidth,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            color: const Color(0xFF193624),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nextLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '顺序：左上角 → 右上角 → 右下角 → 左下角',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const Text(
                                    '请标记完整双打场地最外侧白线的四个角，不是画面四角。',
                                    style: TextStyle(
                                      color: Color(0xFFFFE0B2),
                                      height: 1.4,
                                    ),
                                  ),
                                  const Text(
                                    '可双指缩放整个页面；单击图片添加角点。',
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                  if (widget.preview.autoCorners.length != 4)
                                    const Text(
                                      '当前没有可用的自动角点，请直接在预览图上手动点击。',
                                      style: TextStyle(
                                        color: Color(0xFFFFE0B2),
                                        height: 1.4,
                                      ),
                                    ),
                                  if (widget.preview.sceneWarning != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.preview.sceneWarning!,
                                      style: const TextStyle(
                                        color: Color(0xFFFFCC80),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AspectRatio(
                            aspectRatio: widget.preview.video.width > 0 &&
                                    widget.preview.video.height > 0
                                ? widget.preview.video.width /
                                    widget.preview.video.height
                                : 16 / 9,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final size = Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFF66BB6A),
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (details) => _addPoint(
                                          details.localPosition, size),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _buildPreviewImage(imageUrl),
                                          AnimatedBuilder(
                                            animation: _pulseController,
                                            builder: (context, _) =>
                                                CustomPaint(
                                              painter: _CornerPainter(
                                                points: _points,
                                                videoSize: _videoSize,
                                                pulse: _pulseController.value,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            color: const Color(0xCC1A261F),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _points.isEmpty
                                        ? null
                                        : () => setState(() => _points = []),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('重新选择'),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFA5D6A7),
                                    ),
                                    onPressed:
                                        widget.preview.autoCorners.length == 4
                                            ? _useAutoCorners
                                            : null,
                                    icon: const Icon(Icons.auto_fix_high),
                                    label: Text(
                                      widget.preview.autoCorners.length == 4
                                          ? '使用自动角点'
                                          : '未识别到自动角点',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_points.isNotEmpty)
                            ...List.generate(
                              _points.length,
                              (index) => Text(
                                '${_labels[index]}：'
                                '(${_points[index].x.round()}, ${_points[index].y.round()})',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _points.length == 4
                                ? () => Navigator.of(context)
                                    .pop(List<CourtPoint>.of(_points))
                                : null,
                            icon: const Icon(Icons.check),
                            label: const Text('确认角点并继续'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white70),
                            onPressed: () =>
                                Navigator.of(context).pop(<CourtPoint>[]),
                            child: const Text('跳过手动角点'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedBuilder(
                animation: _transformCtrl,
                builder: (context, _) {
                  final scale = _transformCtrl.value.getMaxScaleOnAxis();
                  if (scale <= 1.05) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.zoom_in,
                            size: 15,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${scale.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                _transformCtrl.value = Matrix4.identity(),
                            child: const Icon(
                              Icons.refresh,
                              size: 15,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.points,
    required this.videoSize,
    required this.pulse,
  });

  final List<CourtPoint> points;
  final Size videoSize;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final offsets = points
        .map(
          (point) => CornerMapper.videoToDisplay(
            videoPoint: point,
            videoSize: videoSize,
            displaySize: size,
          ),
        )
        .toList();
    final linePaint = Paint()
      ..color = Colors.lightGreenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (offsets.length == 4) path.close();
      canvas.drawPath(path, linePaint);
    }
    final fillPaint = Paint()..color = Colors.redAccent;
    for (var index = 0; index < offsets.length; index++) {
      canvas.drawCircle(
        offsets[index],
        13 + pulse * 7,
        Paint()..color = Colors.redAccent.withValues(alpha: 0.22 * (1 - pulse)),
      );
      canvas.drawCircle(offsets[index], 8, fillPaint);
      final text = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        offsets[index] - Offset(text.width / 2, text.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.videoSize != videoSize ||
        oldDelegate.pulse != pulse;
  }
}
