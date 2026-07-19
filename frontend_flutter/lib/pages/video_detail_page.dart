import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/venue.dart';
import '../services/api_service.dart';
import '../utils/user_facing_error.dart';
import 'upload_page.dart';

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({super.key, required this.venue, required this.video});

  final VenueInfo venue;
  final VenueVideo video;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final ApiService _api = ApiService();
  VideoPlayerController? _controller;
  String? _previewError;
  bool _downloading = false;
  double _downloadProgress = 0;
  RangeValues _clipRange = const RangeValues(0, 0);

  bool get _isBundledDemo => widget.video.assetPath?.isNotEmpty == true;

  String get _downloadUrl =>
      widget.video.downloadUrl ??
      Uri.parse(widget.venue.serverUrl)
          .resolve('/videos/${widget.video.id}/download')
          .toString();

  Duration get _duration => _controller?.value.duration ?? Duration.zero;

  double get _maximumSeconds => math
      .max(1, _duration.inMilliseconds / Duration.millisecondsPerSecond)
      .toDouble();

  int get _startMs =>
      (_clipRange.start * Duration.millisecondsPerSecond).round();
  int get _endMs => (_clipRange.end * Duration.millisecondsPerSecond).round();

  bool get _isFullSelection =>
      _startMs <= 0 && _endMs >= _duration.inMilliseconds - 150;

  @override
  void initState() {
    super.initState();
    _initializePreview();
  }

  Future<void> _initializePreview() async {
    final controller = _isBundledDemo
        ? VideoPlayerController.asset(widget.video.assetPath!)
        : VideoPlayerController.networkUrl(Uri.parse(_downloadUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoChanged);
      setState(() {
        _controller = controller;
        _clipRange = RangeValues(0, _maximumSeconds);
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _previewError = '视频预览暂时不可用，请检查球馆网络。');
      }
    }
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  String _formatTime(int milliseconds) {
    final totalSeconds = milliseconds ~/ Duration.millisecondsPerSecond;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Uri get _clipUri => Uri.parse(widget.venue.serverUrl)
          .resolve('/videos/${widget.video.id}/clip')
          .replace(queryParameters: {
        'start_ms': _startMs.toString(),
        'end_ms': _endMs.toString(),
      });

  Future<File> _downloadSelectedClip() async {
    if (_isBundledDemo && !_isFullSelection) {
      throw StateError('内置演示视频暂不支持截取，请选择完整视频保存或分析。');
    }
    final directory = await getTemporaryDirectory();
    final videoDirectory =
        Directory('${directory.path}/GoodBadminton/venue_videos');
    if (!await videoDirectory.exists()) {
      await videoDirectory.create(recursive: true);
    }
    final suffix = '$_startMs' '_' '$_endMs';
    final targetPath = '${videoDirectory.path}/${widget.video.id}_$suffix.mp4';
    if (_isBundledDemo) {
      final data = await rootBundle.load(widget.video.assetPath!);
      final file = File(targetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return file;
    }
    final url = _isFullSelection ? _downloadUrl : _clipUri.toString();
    final savedPath = await _api.downloadFile(url, targetPath);
    return File(savedPath);
  }

  void _resetClip() {
    setState(() => _clipRange = RangeValues(0, _maximumSeconds));
  }

  Future<void> _selectClipAction() async {
    if (_duration <= Duration.zero) return;
    final action = await showModalBottomSheet<_ClipAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('使用选中片段', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('片段范围：${_formatTime(_startMs)} - ${_formatTime(_endMs)}'),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('保存到系统相册'),
                subtitle: const Text('保存选中的视频片段'),
                onTap: () => Navigator.pop(context, _ClipAction.saveToGallery),
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('直接进行分析'),
                subtitle: const Text('将选中片段带入现有上传和分析流程'),
                onTap: () => Navigator.pop(context, _ClipAction.analyze),
              ),
            ],
          ),
        ),
      ),
    );
    switch (action) {
      case _ClipAction.saveToGallery:
        await _saveToGallery();
        return;
      case _ClipAction.analyze:
        await _downloadAndAnalyze();
        return;
      case null:
        return;
    }
  }

  Future<void> _saveToGallery() async {
    setState(() {
      _downloading = true;
      _downloadProgress = .2;
    });
    try {
      final file = await _downloadSelectedClip();
      if (!mounted) return;
      setState(() => _downloadProgress = .8);
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      final granted = hasAccess || await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw StateError('未获得系统相册访问权限，请在系统设置中允许照片权限后重试。');
      }
      await Gal.putVideo(file.path, album: 'Good-Badminton');
      try {
        await file.delete();
      } on FileSystemException {
        // 已成功导入系统相册；清理缓存失败不影响保存结果。
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('选中片段已保存到系统相册：Good-Badminton')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(userFacingError(error, fallback: '保存视频片段失败，请检查网络后重试。'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _downloadAndAnalyze() async {
    setState(() {
      _downloading = true;
      _downloadProgress = .2;
    });
    try {
      final file = await _downloadSelectedClip();
      if (!mounted) return;
      setState(() => _downloadProgress = 1);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UploadPage(
            initialVideoPath: file.path,
            initialVideoName: XFile(file.path).name,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  userFacingError(error, fallback: '获取视频片段失败，请检查球馆网络后重试。'))),
        );
      }
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
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('视频预览')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _previewCard(controller),
            const SizedBox(height: 16),
            Text(widget.video.court,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${widget.video.time} · ${widget.video.duration}'),
            const SizedBox(height: 18),
            if (controller != null) _clipSelector(context),
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              const Text('正在准备选中片段…'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clipSelector(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut_rounded),
                  const SizedBox(width: 8),
                  Text('截取视频片段',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(onPressed: _resetClip, child: const Text('完整视频')),
                ],
              ),
              const SizedBox(height: 6),
              Text('拖动两端选择要保存或分析的时间范围。',
                  style: Theme.of(context).textTheme.bodySmall),
              RangeSlider(
                values: _clipRange,
                min: 0,
                max: _maximumSeconds,
                divisions:
                    math.min(120, _maximumSeconds.ceil()).clamp(1, 120).toInt(),
                labels: RangeLabels(_formatTime(_startMs), _formatTime(_endMs)),
                onChanged: _downloading
                    ? null
                    : (values) {
                        final minSpan =
                            _maximumSeconds > 1 ? 1.0 : _maximumSeconds;
                        var start = values.start;
                        var end = values.end;
                        if (end - start < minSpan) {
                          if (end + minSpan <= _maximumSeconds) {
                            end = start + minSpan;
                          } else {
                            start = end - minSpan;
                          }
                        }
                        setState(() => _clipRange = RangeValues(start, end));
                      },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatTime(_startMs)),
                  Text(_formatTime(_endMs))
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloading ? null : _selectClipAction,
                  icon: const Icon(Icons.content_cut_rounded),
                  label: const Text('使用选中片段'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _previewCard(VideoPlayerController? controller) {
    if (_previewError != null) {
      return _placeholder(const Icon(Icons.wifi_off_outlined), _previewError!);
    }
    if (controller == null) {
      return _placeholder(const CircularProgressIndicator(), '正在加载视频预览…');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => controller.value.isPlaying
                ? controller.pause()
                : controller.play(),
            child: ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          ColoredBox(
            color: const Color(0xFF111714),
            child: Row(
              children: [
                IconButton(
                  tooltip: controller.value.isPlaying ? '暂停' : '播放',
                  color: Colors.white,
                  onPressed: () => controller.value.isPlaying
                      ? controller.pause()
                      : controller.play(),
                  icon: Icon(controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF62A76B),
                      bufferedColor: Color(0xFF53645A),
                      backgroundColor: Color(0xFF303A34),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(Widget icon, String message) => Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF172419),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
}

enum _ClipAction { saveToGallery, analyze }
