import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../models/preview_frame.dart';
import '../utils/corner_mapper.dart';

class CornerPickerPage extends StatefulWidget {
  const CornerPickerPage({super.key, required this.preview});

  final PreviewFrame preview;

  @override
  State<CornerPickerPage> createState() => _CornerPickerPageState();
}

class _CornerPickerPageState extends State<CornerPickerPage> {
  static const _labels = ['左上角', '右上角', '右下角', '左下角'];
  late List<CourtPoint> _points;

  @override
  void initState() {
    super.initState();
    _points = widget.preview.autoCorners.length == 4
        ? List.of(widget.preview.autoCorners)
        : [];
  }

  Size get _videoSize => Size(
        widget.preview.video.width.toDouble(),
        widget.preview.video.height.toDouble(),
      );

  void _addPoint(TapDownDetails details, Size displaySize) {
    if (_points.length >= 4) return;
    setState(() {
      _points.add(
        CornerMapper.displayToVideo(
          displayPoint: details.localPosition,
          displaySize: displaySize,
          videoSize: _videoSize,
        ),
      );
    });
  }

  void _useAutoCorners() {
    setState(() => _points = List.of(widget.preview.autoCorners));
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.absoluteFileUrl(widget.preview.imageUrl)!;
    final nextLabel =
        _points.length < 4 ? '请点击：${_labels[_points.length]}' : '四个角点已设置';
    return Scaffold(
      appBar: AppBar(title: const Text('设置球场角点')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nextLabel,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('顺序：左上角 → 右上角 → 右下角 → 左下角'),
                  const Text('可双指缩放预览图；坐标会自动换算为原视频像素。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: widget.preview.video.width > 0 &&
                    widget.preview.video.height > 0
                ? widget.preview.video.width / widget.preview.video.height
                : 16 / 9,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _addPoint(details, size),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            imageUrl,
                            fit: BoxFit.fill,
                            errorBuilder: (_, error, __) => ColoredBox(
                              color: Colors.black12,
                              child: Center(child: Text('预览图加载失败：$error')),
                            ),
                          ),
                          CustomPaint(
                            painter: _CornerPainter(
                              points: _points,
                              videoSize: _videoSize,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _points.isEmpty ? null : () => setState(() => _points = []),
                icon: const Icon(Icons.refresh),
                label: const Text('重新选择'),
              ),
              OutlinedButton.icon(
                onPressed: widget.preview.autoCorners.length == 4
                    ? _useAutoCorners
                    : null,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('使用自动角点'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_points.isNotEmpty)
            ...List.generate(
              _points.length,
              (index) => Text(
                '${_labels[index]}：'
                '(${_points[index].x.round()}, ${_points[index].y.round()})',
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _points.length == 4
                ? () => Navigator.of(context).pop(List<CourtPoint>.of(_points))
                : null,
            icon: const Icon(Icons.check),
            label: const Text('确认角点并继续'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(<CourtPoint>[]),
            child: const Text('跳过手动角点'),
          ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.points, required this.videoSize});

  final List<CourtPoint> points;
  final Size videoSize;

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
    return oldDelegate.points != points || oldDelegate.videoSize != videoSize;
  }
}
