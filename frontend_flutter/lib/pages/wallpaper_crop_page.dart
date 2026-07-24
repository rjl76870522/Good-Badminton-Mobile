import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lets the user keep exactly the part of a photo that will be visible behind
/// a portrait app page.  The image is moved underneath a fixed page-ratio
/// frame, then exported as a local PNG so the normal page background is cheap
/// to paint afterwards.
class WallpaperCropPage extends StatefulWidget {
  const WallpaperCropPage({
    super.key,
    required this.sourcePath,
    required this.pageAspectRatio,
  });

  final String sourcePath;
  final double pageAspectRatio;

  @override
  State<WallpaperCropPage> createState() => _WallpaperCropPageState();
}

class _WallpaperCropPageState extends State<WallpaperCropPage> {
  ui.Image? _image;
  Offset _offset = Offset.zero;
  double _zoom = 1;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final bytes = await File(widget.sourcePath).readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (mounted) setState(() => _image = image);
  }

  Offset _boundedOffset(Offset proposed, Size viewport) {
    final image = _image!;
    final base = _coverScale(image, viewport);
    final displayedWidth = image.width * base * _zoom;
    final displayedHeight = image.height * base * _zoom;
    final maxX =
        (displayedWidth - viewport.width).clamp(0.0, double.infinity) / 2;
    final maxY =
        (displayedHeight - viewport.height).clamp(0.0, double.infinity) / 2;
    return Offset(
      proposed.dx.clamp(-maxX, maxX),
      proposed.dy.clamp(-maxY, maxY),
    );
  }

  double _coverScale(ui.Image image, Size viewport) => [
        viewport.width / image.width,
        viewport.height / image.height
      ].reduce((a, b) => a > b ? a : b);

  Future<void> _finish(Size viewport) async {
    final image = _image;
    if (image == null) return;
    setState(() => _saving = true);
    try {
      final base = _coverScale(image, viewport);
      final displayedScale = base * _zoom;
      final left =
          (viewport.width - image.width * displayedScale) / 2 + _offset.dx;
      final top =
          (viewport.height - image.height * displayedScale) / 2 + _offset.dy;
      final source = Rect.fromLTWH(
        (-left / displayedScale).clamp(0.0, image.width.toDouble()),
        (-top / displayedScale).clamp(0.0, image.height.toDouble()),
        viewport.width / displayedScale,
        viewport.height / displayedScale,
      );
      final clippedSource = source.intersect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
      const outputHeight = 1800;
      final outputWidth = (outputHeight * widget.pageAspectRatio).round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        clippedSource,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final rendered =
          await recorder.endRecording().toImage(outputWidth, outputHeight);
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted || data == null) return;
      Navigator.of(context).pop(data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('选择背景画面')),
      body: image == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = constraints.maxHeight - 166;
                  final height = maxHeight.clamp(280.0, 560.0);
                  final width = height * widget.pageAspectRatio;
                  final viewport = Size(width, height);
                  final base = _coverScale(image, viewport);
                  final displayedWidth = image.width * base * _zoom;
                  final displayedHeight = image.height * base * _zoom;
                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                        child: Text(
                          '拖动照片，保留框内会显示在页面背景中',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: RepaintBoundary(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: GestureDetector(
                                  onPanUpdate: (details) => setState(() {
                                    _offset = _boundedOffset(
                                      _offset + details.delta,
                                      viewport,
                                    );
                                  }),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      const ColoredBox(
                                          color: Color(0xFF152018)),
                                      Positioned(
                                        left: (width - displayedWidth) / 2 +
                                            _offset.dx,
                                        top: (height - displayedHeight) / 2 +
                                            _offset.dy,
                                        width: displayedWidth,
                                        height: displayedHeight,
                                        child: Image.file(
                                          File(widget.sourcePath),
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                      IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.9),
                                              width: 2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(22),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.zoom_out_map_rounded,
                                    color: Color(0xFF2E7D32)),
                                Expanded(
                                  child: Slider(
                                    value: _zoom,
                                    min: 1,
                                    max: 3,
                                    onChanged: (value) => setState(() {
                                      _zoom = value;
                                      _offset =
                                          _boundedOffset(_offset, viewport);
                                    }),
                                  ),
                                ),
                                const Icon(Icons.zoom_in_rounded,
                                    color: Color(0xFF2E7D32)),
                              ],
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    _saving ? null : () => _finish(viewport),
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(_saving ? '正在保存…' : '使用此背景画面'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}
