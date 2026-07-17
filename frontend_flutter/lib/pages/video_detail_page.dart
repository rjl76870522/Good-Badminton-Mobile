import 'dart:io';

import 'package:flutter/material.dart';
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

  String get _downloadUrl =>
      widget.video.downloadUrl ??
      Uri.parse(widget.venue.serverUrl)
          .resolve('/videos/${widget.video.id}/download')
          .toString();

  @override
  void initState() {
    super.initState();
    _initializePreview();
  }

  Future<void> _initializePreview() async {
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(_downloadUrl));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _previewError = '视频预览暂时不可用，请检查球馆网络。');
      }
    }
  }

  Future<File> _downloadToCache() async {
    final directory = await getTemporaryDirectory();
    final videoDirectory =
        Directory('${directory.path}/GoodBadminton/venue_videos');
    if (!await videoDirectory.exists()) {
      await videoDirectory.create(recursive: true);
    }
    final fileName =
        '${widget.video.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final savedPath = await _api.downloadFile(
      _downloadUrl,
      '${videoDirectory.path}/$fileName',
    );
    return File(savedPath);
  }

  Future<void> _selectDownloadAction() async {
    final action = await showModalBottomSheet<_VideoAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('获取比赛视频', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('请选择视频下载后的操作。'),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('保存到系统相册'),
                subtitle: const Text('可在手机相册的 Good-Badminton 相簿中查看'),
                onTap: () => Navigator.pop(context, _VideoAction.saveToGallery),
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: const Text('直接进行分析'),
                subtitle: const Text('带入现有的视频上传与分析流程'),
                onTap: () => Navigator.pop(context, _VideoAction.analyze),
              ),
            ],
          ),
        ),
      ),
    );
    switch (action) {
      case _VideoAction.saveToGallery:
        await _saveToGallery();
        return;
      case _VideoAction.analyze:
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
      final file = await _downloadToCache();
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
        // 已成功导入系统相册；清理临时文件失败不影响保存结果。
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到系统相册：Good-Badminton')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingError(error, fallback: '保存视频失败，请检查网络后重试。')),
          ),
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
      final file = await _downloadToCache();
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
            content:
                Text(userFacingError(error, fallback: '下载视频失败，请检查球馆网络后重试。')),
          ),
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
    _controller?.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('选择视频')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _previewCard(controller),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('球馆：${widget.venue.name}'),
                    const SizedBox(height: 8),
                    Text('视频：${widget.video.court}'),
                    const SizedBox(height: 8),
                    Text('时间：${widget.video.time}'),
                    const SizedBox(height: 8),
                    Text('时长：${widget.video.duration}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_downloading) ...[
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              const Text('正在获取球馆视频…'),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _downloading ? null : _selectDownloadAction,
              icon: const Icon(Icons.download_rounded),
              label: const Text('获取视频'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(VideoPlayerController? controller) {
    if (_previewError != null) {
      return _placeholder(const Icon(Icons.wifi_off_outlined), _previewError!);
    }
    if (controller == null) {
      return _placeholder(const CircularProgressIndicator(), '正在加载视频预览…');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              IconButton.filled(
                iconSize: 34,
                onPressed: () {
                  setState(() {
                    controller.value.isPlaying
                        ? controller.pause()
                        : controller.play();
                  });
                },
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
        ),
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

enum _VideoAction { saveToGallery, analyze }
