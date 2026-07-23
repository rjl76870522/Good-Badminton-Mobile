import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/venue.dart';
import '../services/api_service.dart';
import '../services/user_storage.dart';
import '../utils/user_facing_error.dart';
import 'upload_page.dart';

const _buildRevision = String.fromEnvironment(
  'BUILD_REVISION',
  defaultValue: 'local',
);

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({super.key, required this.venue, required this.video});

  final VenueInfo venue;
  final VenueVideo video;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final ApiService _api = ApiService();
  final UserStorage _userStorage = UserStorage();
  VideoPlayerController? _controller;
  String? _previewError;
  bool _downloading = false;
  bool _resettingAtClipEnd = false;
  bool _playingSelectedClip = false;
  bool _scrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  double _scrubSeconds = 0;
  double? _pendingScrubSeconds;
  Future<void>? _scrubSeekWorker;
  double _previewLoadingProgress = 0;
  double _downloadProgress = 0;
  double _videoDurationSeconds = 1;
  RangeValues _clipRange = const RangeValues(0, 0);

  bool get _isBundledDemo => widget.video.assetPath?.isNotEmpty == true;
  String? get _bundledServerVideoId => switch (widget.video.id) {
        'example-court1-demo01' => 'court1-full-recording',
        'example-court2-demo02' => 'court2-full-recording',
        _ => null,
      };
  bool get _videoReady =>
      _controller != null &&
      _controller!.value.isInitialized &&
      _previewLoadingProgress >= 1 &&
      _previewError == null;

  String get _downloadUrl =>
      widget.video.downloadUrl ??
      _venueVideoUrl('videos/${widget.video.id}/download');

  String _venueVideoUrl(String path) {
    final base = Uri.parse(widget.venue.serverUrl);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base
        .replace(path: '$basePath$path', query: null, fragment: null)
        .toString();
  }

  Duration get _duration => _controller?.value.duration ?? Duration.zero;
  double get _maximumSeconds => _videoDurationSeconds;
  int get _startMs =>
      (_clipRange.start * Duration.millisecondsPerSecond).round();
  int get _endMs => (_clipRange.end * Duration.millisecondsPerSecond).round();
  bool get _isFullSelection =>
      _startMs <= 0 && _endMs >= _duration.inMilliseconds - 150;
  Uri get _clipUri {
    final download = Uri.parse(_downloadUrl);
    final clipPath = download.path.endsWith('/download')
        ? '${download.path.substring(0, download.path.length - '/download'.length)}/clip'
        : '${download.path}/clip';
    return download.replace(path: clipPath, queryParameters: {
      'start_ms': _startMs.toString(),
      'end_ms': _endMs.toString(),
    });
  }

  @override
  void initState() {
    super.initState();
    _initializePreview();
  }

  Future<void> _initializePreview() async {
    VideoPlayerController? controller;
    try {
      if (_isBundledDemo) {
        controller = VideoPlayerController.asset(widget.video.assetPath!);
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(_downloadUrl));
      }
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoChanged);
      final durationSeconds = math
          .max(
            1,
            controller.value.duration.inMilliseconds /
                Duration.millisecondsPerSecond,
          )
          .toDouble();
      setState(() {
        _controller = controller;
        _videoDurationSeconds = durationSeconds;
        _clipRange = RangeValues(0, durationSeconds);
        _previewLoadingProgress = 1;
      });
    } catch (_) {
      await controller?.dispose();
      if (mounted) {
        setState(() => _previewError = '视频预览暂时不可用，请检查球馆网络。');
      }
    }
  }

  void _onVideoChanged() {
    final controller = _controller;
    if (controller != null &&
        _playingSelectedClip &&
        controller.value.isPlaying &&
        !_resettingAtClipEnd &&
        controller.value.position.inMilliseconds >= _endMs) {
      _resettingAtClipEnd = true;
      controller.pause().then(
            (_) => controller
                .seekTo(Duration(milliseconds: _startMs))
                .whenComplete(() {
              _playingSelectedClip = false;
              _resettingAtClipEnd = false;
            }),
          );
    }
    if (mounted) setState(() {});
  }

  Future<File> _downloadToCache({
    void Function(double progress)? onProgress,
  }) async {
    if (!_videoReady) {
      throw StateError('完整视频仍在缓存，请稍候。');
    }
    final directory = await getTemporaryDirectory();
    final videoDirectory =
        Directory('${directory.path}/GoodBadminton/venue_videos');
    if (!await videoDirectory.exists()) {
      await videoDirectory.create(recursive: true);
    }
    final fileName = '${widget.video.id}_${_startMs}_$_endMs.mp4';
    final targetPath = '${videoDirectory.path}/$fileName';
    if (_isBundledDemo) {
      final serverVideoId = _bundledServerVideoId;
      if (!_isFullSelection && serverVideoId != null) {
        final clipUrl = Uri.parse(
          _venueVideoUrl('videos/$serverVideoId/clip'),
        ).replace(queryParameters: {
          'start_ms': _startMs.toString(),
          'end_ms': _endMs.toString(),
        }).toString();
        final savedPath = await _api.downloadFile(
          clipUrl,
          targetPath,
          onProgress: onProgress,
        );
        return File(savedPath);
      }
      final data = await rootBundle.load(widget.video.assetPath!);
      final file = File(targetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      onProgress?.call(1);
      return file;
    }
    final url = _isFullSelection ? _downloadUrl : _clipUri.toString();
    final savedPath = await _api.downloadFile(
      url,
      targetPath,
      onProgress: onProgress,
    );
    return File(savedPath);
  }

  void _showDownloadProgress(double progress) {
    if (!mounted) return;
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    setState(() => _downloadProgress = .05 + normalized * .85);
  }

  String _formatTime(int milliseconds) {
    final totalSeconds = milliseconds ~/ Duration.millisecondsPerSecond;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _resetClip() async {
    setState(() => _clipRange = RangeValues(0, _maximumSeconds));
    await _controller?.seekTo(Duration.zero);
  }

  Future<void> _updateClipRange(RangeValues values) async {
    const minimumSpan = 1.0;
    var start = values.start;
    var end = values.end;
    if (end - start < minimumSpan) {
      if (start + minimumSpan <= _maximumSeconds) {
        end = start + minimumSpan;
      } else {
        start = end - minimumSpan;
      }
    }
    final previous = _clipRange;
    final startMoved = (start - previous.start).abs();
    final endMoved = (end - previous.end).abs();
    final seekSeconds = startMoved >= endMoved ? start : end;
    setState(() => _clipRange = RangeValues(start, end));
    final controller = _controller;
    if (controller != null) {
      await controller.pause();
      await controller.seekTo(
        Duration(
          milliseconds: (seekSeconds * Duration.millisecondsPerSecond).round(),
        ),
      );
    }
  }

  Future<void> _previewSelectedClip() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    await controller.seekTo(Duration(milliseconds: _startMs));
    _playingSelectedClip = true;
    await controller.play();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      _playingSelectedClip = false;
      await controller.pause();
      return;
    }
    _playingSelectedClip = false;
    final position = controller.value.position.inMilliseconds;
    if (position < _startMs || position >= _endMs) {
      await controller.seekTo(Duration(milliseconds: _startMs));
    }
    await controller.play();
  }

  void _startScrubbing(double value) {
    final controller = _controller;
    if (controller == null) return;
    _playingSelectedClip = false;
    _wasPlayingBeforeScrub = controller.value.isPlaying;
    controller.pause();
    setState(() {
      _scrubbing = true;
      _scrubSeconds = value;
    });
    _queueScrubSeek(value);
  }

  void _scrubTo(double value) {
    if (_controller == null) return;
    setState(() => _scrubSeconds = value);
    _queueScrubSeek(value);
  }

  void _queueScrubSeek(double value) {
    _pendingScrubSeconds = value;
    _scrubSeekWorker ??= _drainScrubSeeks().whenComplete(
      () => _scrubSeekWorker = null,
    );
  }

  Future<void> _drainScrubSeeks() async {
    while (_pendingScrubSeconds != null) {
      final target = _pendingScrubSeconds!;
      _pendingScrubSeconds = null;
      final controller = _controller;
      if (controller == null) return;
      await controller.seekTo(
        Duration(
          milliseconds: (target * Duration.millisecondsPerSecond).round(),
        ),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _finishScrubbing(double value) async {
    final controller = _controller;
    if (controller == null) return;
    _queueScrubSeek(value);
    await _scrubSeekWorker;
    if (_wasPlayingBeforeScrub) await controller.play();
    if (mounted) {
      setState(() {
        _scrubbing = false;
        _scrubSeconds = value;
      });
    }
  }

  Future<void> _selectDownloadAction() async {
    if (!_videoReady || _downloading) return;
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
              Text(
                _isFullSelection
                    ? '当前选择完整视频'
                    : '当前片段：${_formatTime(_startMs)} - ${_formatTime(_endMs)}',
              ),
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
      _downloadProgress = .05;
    });
    try {
      final file = await _downloadToCache(onProgress: _showDownloadProgress);
      if (!mounted) return;
      setState(() => _downloadProgress = .95);
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
          const SnackBar(
            content: Text('已保存到系统相册：Good-Badminton'),
            duration: Duration(seconds: 2),
          ),
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
      _downloadProgress = .05;
    });
    try {
      if (_isBundledDemo) {
        final file = await _downloadToCache(onProgress: _showDownloadProgress);
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
        return;
      }
      setState(() => _downloadProgress = .35);
      final userId = await _userStorage.getOrCreateUserId();
      final preview = await _api.previewVenueClip(
        videoId: widget.video.id,
        startMs: _startMs,
        endMs: _endMs,
        userId: userId,
      );
      if (!mounted) return;
      setState(() => _downloadProgress = 1);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UploadPage(
            initialPreview: preview,
            initialVideoName: '${widget.video.id}_${_startMs}_$_endMs.mp4',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(userFacingError(error, fallback: '准备球馆视频失败，请检查网络后重试。')),
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
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          kDebugMode ? '选择视频 · ${_shortBuildRevision(_buildRevision)}' : '选择视频',
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _previewCard(controller),
            const SizedBox(height: 16),
            if (controller != null) ...[
              _clipSelector(context),
              const SizedBox(height: 16),
            ],
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
                    if (widget.video.isPreparedClip) ...[
                      const SizedBox(height: 12),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.content_cut_rounded,
                              size: 20, color: Color(0xFF2E7D32)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已从球馆存储的完整视频中截取出准备分析的视频片段',
                              style: TextStyle(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ],
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
              onPressed:
                  _downloading || !_videoReady ? null : _selectDownloadAction,
              icon: _videoReady
                  ? const Icon(Icons.download_rounded)
                  : const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              label: Text(
                _videoReady
                    ? '获取视频'
                    : _previewError != null
                        ? '视频暂不可用'
                        : '正在加载视频',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipSelector(BuildContext context) => Card(
        key: const Key('venue-clip-selector'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut_rounded),
                  const SizedBox(width: 8),
                  Text(
                    '选择要分析的回合',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetClip,
                    child: const Text('完整视频'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('拖动左右端点选择片段，避开捡球与休息时间'),
              const SizedBox(height: 8),
              _ClipRangeTrack(
                key: const Key('venue-custom-clip-track'),
                values: _clipRange,
                maximum: _maximumSeconds,
                enabled: !_downloading,
                onInteractionStart: () => _controller?.pause(),
                onChanged: _updateClipRange,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatTime(_startMs)),
                  OutlinedButton.icon(
                    onPressed: _downloading ? null : _previewSelectedClip,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('预览所选片段'),
                  ),
                  Text(_formatTime(_endMs)),
                ],
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
      return _placeholder(
        const CircularProgressIndicator(),
        '正在加载视频预览…',
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          GestureDetector(
            onTap: _togglePlayback,
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
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: controller.value.isPlaying ? '暂停' : '播放',
                      color: Colors.white,
                      onPressed: _togglePlayback,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: (_scrubbing
                                ? _scrubSeconds
                                : controller.value.position.inMilliseconds /
                                    Duration.millisecondsPerSecond)
                            .clamp(0, _maximumSeconds),
                        min: 0,
                        max: _maximumSeconds,
                        label: _formatTime(
                          ((_scrubbing
                                      ? _scrubSeconds
                                      : controller
                                              .value.position.inMilliseconds /
                                          Duration.millisecondsPerSecond) *
                                  Duration.millisecondsPerSecond)
                              .round(),
                        ),
                        onChangeStart: _startScrubbing,
                        onChanged: _scrubTo,
                        onChangeEnd: _finishScrubbing,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 16, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(
                          ((_scrubbing
                                      ? _scrubSeconds
                                      : controller
                                              .value.position.inMilliseconds /
                                          Duration.millisecondsPerSecond) *
                                  Duration.millisecondsPerSecond)
                              .round(),
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        _formatTime(_duration.inMilliseconds),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
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

enum _VideoAction { saveToGallery, analyze }

String _shortBuildRevision(String revision) {
  if (revision.isEmpty) return 'unknown';
  return revision.length <= 7 ? revision : revision.substring(0, 7);
}

class _ClipRangeTrack extends StatefulWidget {
  const _ClipRangeTrack({
    super.key,
    required this.values,
    required this.maximum,
    required this.enabled,
    required this.onInteractionStart,
    required this.onChanged,
  });

  final RangeValues values;
  final double maximum;
  final bool enabled;
  final VoidCallback onInteractionStart;
  final ValueChanged<RangeValues> onChanged;

  @override
  State<_ClipRangeTrack> createState() => _ClipRangeTrackState();
}

class _ClipRangeTrackState extends State<_ClipRangeTrack> {
  bool _movingStart = true;

  void _begin(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    widget.onInteractionStart();
    final startX = widget.values.start / widget.maximum * width;
    final endX = widget.values.end / widget.maximum * width;
    _movingStart = (dx - startX).abs() <= (dx - endX).abs();
    _update(dx, width);
  }

  void _update(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    const minimumSpan = 1.0;
    final value =
        (dx / width * widget.maximum).clamp(0.0, widget.maximum).toDouble();
    if (_movingStart) {
      widget.onChanged(
        RangeValues(
          math
              .min(value, widget.values.end - minimumSpan)
              .clamp(0.0, widget.maximum)
              .toDouble(),
          widget.values.end,
        ),
      );
    } else {
      widget.onChanged(
        RangeValues(
          widget.values.start,
          math
              .max(value, widget.values.start + minimumSpan)
              .clamp(0.0, widget.maximum)
              .toDouble(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(1.0, widget.maximum);
    final start = widget.values.start.clamp(0.0, maximum).toDouble();
    final end = widget.values.end.clamp(start, maximum).toDouble();
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '分析片段范围',
      value: '${start.toStringAsFixed(1)} 到 ${end.toStringAsFixed(1)} 秒',
      child: SizedBox(
        height: 58,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const handleRadius = 12.0;
            final trackWidth =
                math.max(1.0, constraints.maxWidth - handleRadius * 2);
            final startX = handleRadius + start / maximum * trackWidth;
            final endX = handleRadius + end / maximum * trackWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled
                  ? (details) => _begin(
                      details.localPosition.dx - handleRadius, trackWidth)
                  : null,
              onHorizontalDragStart: widget.enabled
                  ? (details) => _begin(
                      details.localPosition.dx - handleRadius, trackWidth)
                  : null,
              onHorizontalDragUpdate: widget.enabled
                  ? (details) => _update(
                      details.localPosition.dx - handleRadius, trackWidth)
                  : null,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: handleRadius,
                    right: handleRadius,
                    top: 26,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: startX,
                    top: 26,
                    width: math.max(0, endX - startX),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  for (final x in [startX, endX])
                    Positioned(
                      left: x - handleRadius,
                      top: 17,
                      child: Container(
                        width: handleRadius * 2,
                        height: handleRadius * 2,
                        decoration: BoxDecoration(
                          color: widget.enabled ? color : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
