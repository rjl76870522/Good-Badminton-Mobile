import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/wallpaper_storage.dart';
import 'wallpaper_crop_page.dart';

class WallpaperSettingsPage extends StatefulWidget {
  const WallpaperSettingsPage({super.key});

  @override
  State<WallpaperSettingsPage> createState() => _WallpaperSettingsPageState();
}

class _WallpaperSettingsPageState extends State<WallpaperSettingsPage> {
  final _storage = WallpaperStorage();
  final _imagePicker = ImagePicker();
  WallpaperTarget _target = WallpaperTarget.global;
  String? _specificPath;
  String? _effectivePath;
  double _opacity = WallpaperTarget.global.defaultOpacity;
  double _scale = 1;
  final _opacityPreview = ValueNotifier<double>(
    WallpaperTarget.global.defaultOpacity,
  );
  final _scalePreview = ValueNotifier<double>(1);
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _opacityPreview.dispose();
    _scalePreview.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _storage.getSpecificPath(_target),
      _storage.getPresentation(
        _target,
        fallbackOpacity: _target.defaultOpacity,
      ),
    ]);
    final presentation = results[1] as WallpaperPresentation;
    if (!mounted) return;
    setState(() {
      _specificPath = results[0] as String?;
      _effectivePath = presentation.imagePath;
      _opacity = presentation.opacity;
      _scale = presentation.scale;
      _opacityPreview.value = presentation.opacity;
      _scalePreview.value = presentation.scale;
      _loading = false;
    });
  }

  Future<void> _selectTarget(WallpaperTarget target) async {
    if (target == _target) return;
    setState(() {
      _target = target;
      _loading = true;
    });
    await _load();
  }

  Future<void> _pickPhoto() async {
    final selected = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 88,
    );
    if (selected == null || !mounted) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => WallpaperCropPage(
          sourcePath: selected.path,
          pageAspectRatio: _pageAspectRatio(context),
        ),
      ),
    );
    if (bytes == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory('${documents.path}/GoodBadminton/wallpapers');
      await directory.create(recursive: true);
      // A fresh filename is intentional. Replacing bytes at the same path can
      // leave Flutter's ImageCache showing the previous wallpaper.
      final previousPath = _specificPath;
      final targetFile = File(
        '${directory.path}/${_target.storageKey}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await targetFile.writeAsBytes(bytes, flush: true);
      await _storage.setPath(_target, targetFile.path);
      if (previousPath != null && previousPath != targetFile.path) {
        try {
          await FileImage(File(previousPath)).evict();
          await File(previousPath).delete();
        } on FileSystemException {
          // A removed or non-image old wallpaper does not block replacement.
        }
      }
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreDefault() async {
    final previousPath = _specificPath;
    await _storage.clear(_target);
    await _storage.clearAppearance(_target);
    if (previousPath != null) {
      try {
        await File(previousPath).delete();
      } on FileSystemException {
        // Removing a missing local wallpaper is harmless.
      }
    }
    await _load();
  }

  Future<void> _restoreAllDefaults() async {
    setState(() => _saving = true);
    try {
      final paths = await _storage.clearAll();
      for (final path in paths) {
        try {
          await FileImage(File(path)).evict();
          await File(path).delete();
        } on FileSystemException {
          // A deleted local image needs no further handling.
        }
      }
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAppearance() async {
    _opacity = _opacityPreview.value;
    _scale = _scalePreview.value;
    await _storage.setAppearance(
      _target,
      opacity: _opacity,
      scale: _scale,
    );
  }

  Alignment get _previewAlignment => switch (_target) {
        WallpaperTarget.discover => const Alignment(0.15, -0.2),
        WallpaperTarget.profile => const Alignment(0.1, -0.35),
        _ => Alignment.topCenter,
      };

  double _pageAspectRatio(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final pageHeight = screen.height - topInset - kToolbarHeight;
    return screen.width / pageHeight;
  }

  @override
  Widget build(BuildContext context) {
    final previewFile = _effectivePath == null ? null : File(_effectivePath!);
    final hasPreview = previewFile?.existsSync() ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('自定义背景')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            '选择页面',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _TargetSelector(
            selected: _target,
            onSelected: _selectTarget,
          ),
          const SizedBox(height: 20),
          Text(
            _target == WallpaperTarget.global
                ? '全局默认背景'
                : '${_target.label}的背景预览',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final aspectRatio = _pageAspectRatio(context);
              final height =
                  (constraints.maxWidth / aspectRatio).clamp(310.0, 540.0);
              final width = height * aspectRatio;
              return Center(
                child: SizedBox(
                  height: height,
                  width: width,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFF9FCF4),
                                Color(0xFFF0F7EC),
                                Color(0xFFE8F1E4),
                              ],
                            ),
                          ),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: _scalePreview,
                          builder: (context, scale, _) =>
                              ValueListenableBuilder<double>(
                            valueListenable: _opacityPreview,
                            builder: (context, opacity, _) => ClipRect(
                              child: Transform.scale(
                                scale: scale,
                                child: hasPreview
                                    ? Image.file(
                                        previewFile!,
                                        fit: BoxFit.cover,
                                        alignment: _previewAlignment,
                                        opacity:
                                            AlwaysStoppedAnimation(opacity),
                                      )
                                    : Image.asset(
                                        _target.defaultImageAsset,
                                        fit: BoxFit.cover,
                                        alignment: _previewAlignment,
                                        opacity:
                                            AlwaysStoppedAnimation(opacity),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(-0.75, -0.92),
                              radius: 1.25,
                              colors: [Color(0x66C8E6C9), Color(0x00C8E6C9)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Text(
                            _specificPath != null
                                ? '已为${_target.label}设置本地背景'
                                : _target == WallpaperTarget.global
                                    ? '正在使用内置默认背景'
                                    : '未单独设置，将使用全局默认背景',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
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
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _pickPhoto,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(_saving ? '正在保存…' : '从相册选择照片'),
          ),
          const SizedBox(height: 10),
          Text(
            '背景显示效果',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<double>(
            valueListenable: _opacityPreview,
            builder: (context, value, _) => _AdjustmentSlider(
              icon: Icons.opacity_rounded,
              label: '背景图透明度',
              valueLabel: '${(value * 100).round()}%',
              value: value,
              min: 0,
              max: 1,
              onChanged: (nextValue) => _opacityPreview.value = nextValue,
              onChangeEnd: (_) => _saveAppearance(),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _scalePreview,
            builder: (context, value, _) => _AdjustmentSlider(
              icon: Icons.zoom_out_map_rounded,
              label: '背景大小',
              valueLabel: '${value.toStringAsFixed(1)}×',
              value: value,
              min: 1,
              max: 2.5,
              onChanged: (nextValue) => _scalePreview.value = nextValue,
              onChangeEnd: (_) => _saveAppearance(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading || _saving ? null : _restoreDefault,
            icon: const Icon(Icons.restore_rounded),
            label: Text(
              _target == WallpaperTarget.global ? '恢复内置默认背景' : '恢复该页默认背景',
            ),
          ),
          if (_target == WallpaperTarget.global) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loading || _saving ? null : _restoreAllDefaults,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('恢复全部默认背景'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '照片仅保存在本机。背景大小用于放大并裁切图片，透明度用于调节图片在页面中的显眼程度。'
            '页面没有单独设置时，会自动使用“全局默认背景”。'
            '扫码和角点标记等需要显示相机或视频画面的页面不会应用壁纸。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _TargetSelector extends StatelessWidget {
  const _TargetSelector({required this.selected, required this.onSelected});

  final WallpaperTarget selected;
  final ValueChanged<WallpaperTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chips(List<WallpaperTarget> targets) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final target in targets)
              ChoiceChip(
                label: Text(target.label),
                selected: selected == target,
                onSelected: (_) => onSelected(target),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips(const [
          WallpaperTarget.global,
          WallpaperTarget.home,
          WallpaperTarget.discover,
          WallpaperTarget.profile,
        ]),
        const SizedBox(height: 14),
        const _WallpaperGroupTitle('分析与报告'),
        const SizedBox(height: 8),
        chips(const [
          WallpaperTarget.history,
          WallpaperTarget.taskStatus,
          WallpaperTarget.report,
          WallpaperTarget.upload,
        ]),
      ],
    );
  }
}

class _WallpaperGroupTitle extends StatelessWidget {
  const _WallpaperGroupTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF2E7D32),
              fontWeight: FontWeight.w800,
            ),
      );
}

class _AdjustmentSlider extends StatelessWidget {
  const _AdjustmentSlider({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE8DA)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
