import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../config/upload_constraints.dart';
import '../models/preview_frame.dart';
import '../services/api_service.dart';
import '../services/task_storage.dart';
import '../services/user_storage.dart';
import '../widgets/app_background.dart';
import 'corner_picker_page.dart';
import 'task_status_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({
    super.key,
    this.retryTaskId,
    this.initialVideoPath,
    this.initialVideoName,
  });

  final String? retryTaskId;
  final String? initialVideoPath;
  final String? initialVideoName;

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ApiService _api = ApiService();
  final TaskStorage _storage = TaskStorage();
  final UserStorage _userStorage = UserStorage();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  int? _selectedFileSize;
  Duration? _selectedDuration;
  List<String> _validationErrors = const [];
  List<String> _validationWarnings = const [];
  PreviewFrame? _preview;
  List<CourtPoint>? _corners;
  bool _inspectingVideo = false;
  bool _previewing = false;
  bool _uploading = false;
  double _previewProgress = 0;
  double _uploadProgress = 0;
  String? _error;

  bool get _canUpload =>
      !_uploading &&
      !_previewing &&
      !_inspectingVideo &&
      _selectedFile != null &&
      _validationErrors.isEmpty;

  @override
  void initState() {
    super.initState();
    _restoreInitialVideo();
  }

  Future<void> _restoreInitialVideo() async {
    final initialPath = widget.initialVideoPath;
    if (initialPath != null) {
      if (!await File(initialPath).exists()) {
        if (mounted) {
          setState(() => _error = '下载的视频缓存不存在，请重新从球馆视频库选择');
        }
        return;
      }
      await _inspectSelectedFile(
        XFile(initialPath, name: widget.initialVideoName ?? 'venue_video.mp4'),
      );
      return;
    }
    await _restoreRetryVideo();
  }

  Future<void> _restoreRetryVideo() async {
    final taskId = widget.retryTaskId;
    if (taskId == null) return;
    final stored = await _storage.getUpload(taskId);
    if (!mounted) return;
    if (stored == null || !await File(stored.videoPath).exists()) {
      setState(() => _error = '原视频缓存不可用，请重新选择视频后重试');
      return;
    }
    await _inspectSelectedFile(
      XFile(stored.videoPath, name: stored.videoName),
    );
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (!mounted || file == null) return;
      await _inspectSelectedFile(file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '选择视频失败：$error');
    }
  }

  Future<void> _inspectSelectedFile(XFile file) async {
    setState(() {
      _selectedFile = file;
      _selectedFileSize = null;
      _selectedDuration = null;
      _validationErrors = const [];
      _validationWarnings = const [];
      _preview = null;
      _corners = null;
      _inspectingVideo = true;
      _error = null;
    });

    final size = await file.length();
    Duration? duration;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(file.path));
      await controller.initialize().timeout(const Duration(seconds: 20));
      duration = controller.value.duration;
    } catch (_) {
      duration = null;
    } finally {
      await controller?.dispose();
    }

    final validation = UploadConstraints.validate(
      fileName: file.name,
      fileSizeBytes: size,
      duration: duration,
    );
    if (!mounted) return;
    setState(() {
      _selectedFileSize = size;
      _selectedDuration = duration;
      _validationErrors = validation.errors;
      _validationWarnings = validation.warnings;
      _inspectingVideo = false;
    });
    if (validation.isValid) {
      await _createPreview();
    }
  }

  Future<void> _createPreview() async {
    final file = _selectedFile;
    if (file == null || _validationErrors.isNotEmpty) return;
    setState(() {
      _previewing = true;
      _previewProgress = 0;
      _error = null;
    });
    try {
      final userId = await _userStorage.getOrCreateUserId();
      final preview = await _api.previewVideo(
        file,
        userId: userId,
        onProgress: (progress) {
          if (mounted) setState(() => _previewProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _preview = preview);
      final corners = await Navigator.of(context).push<List<CourtPoint>>(
        MaterialPageRoute(
          builder: (_) => CornerPickerPage(
            preview: preview,
            localVideoPath: file.path,
          ),
        ),
      );
      if (!mounted) return;
      if (corners != null) {
        setState(() => _corners = corners.length == 4 ? corners : const []);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _corners = null;
        _error = '预览帧提取失败：$error\n仍可跳过角点直接上传原视频。';
      });
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _editCorners() async {
    final preview = _preview;
    if (preview == null) return;
    final corners = await Navigator.of(context).push<List<CourtPoint>>(
      MaterialPageRoute(
        builder: (_) => CornerPickerPage(
          preview: preview,
          localVideoPath: _selectedFile?.path,
        ),
      ),
    );
    if (mounted && corners != null) {
      setState(() => _corners = corners.length == 4 ? corners : const []);
    }
  }

  Future<void> _upload() async {
    final file = _selectedFile;
    if (file == null) {
      setState(() => _error = '请先选择视频');
      return;
    }
    if (file.path.isEmpty) {
      setState(() => _error = '无法读取所选视频的本地路径');
      return;
    }
    if (_inspectingVideo) {
      setState(() => _error = '正在读取视频信息，请稍候');
      return;
    }
    if (_validationErrors.isNotEmpty) {
      setState(() => _error = '视频不符合上传要求，请根据提示重新选择');
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      final userId = await _userStorage.getOrCreateUserId();
      final result = await _api.uploadVideo(
        _preview == null ? file : null,
        userId: userId,
        sourceUploadId: _preview?.sourceUploadId,
        corners: _corners?.length == 4 ? _corners : null,
        language: 'zh',
        poseMode: 'balanced',
        keepAudio: true,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress);
        },
      );
      if (!mounted) return;
      await _storage.saveActiveTask(
        taskId: result.taskId,
        videoPath: file.path,
        videoName: file.name,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TaskStatusPage(taskId: result.taskId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = 0;
        _error = '上传失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传视频'),
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '视频要求',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      SizedBox(height: 8),
                      Text('格式：MP4 / MOV / M4V'),
                      Text('大小：不超过 200 MB'),
                      Text('时长：5 秒～3 分钟（推荐单个完整回合，约 8～20 秒）'),
                      SizedBox(height: 6),
                      Text('建议横屏固定机位拍摄，画面尽量覆盖完整球场。'),
                      Text('请尽量去掉休息、捡球和发球准备时间。'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: const ListTile(
                  leading: Icon(Icons.queue_outlined),
                  title: Text('任务提交说明'),
                  subtitle: Text(
                    '为了维护稳定流畅的使用体验，每位用户最多保留 3 个等待任务，'
                    '每分钟最多创建 2 个任务',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _uploading || _inspectingVideo ? null : _pickVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('选择视频'),
              ),
              const SizedBox(height: 12),
              if (_selectedFile == null)
                const Center(child: Text('尚未选择视频'))
              else
                _SelectedVideoCard(
                  fileName: _selectedFile!.name,
                  fileSize: _selectedFileSize,
                  duration: _selectedDuration,
                  inspecting: _inspectingVideo,
                  errors: _validationErrors,
                  warnings: _validationWarnings,
                ),
              if (_previewing) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _previewProgress),
                const SizedBox(height: 6),
                Text(
                  _previewProgress >= 0.92
                      ? '上传完成，正在生成预览页'
                      : '正在上传并提取预览帧：${(_previewProgress * 100).round()}%',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_preview != null && !_previewing) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.crop_free),
                    title: const Text('球场预览已生成'),
                    subtitle: Text(
                      _corners?.length == 4 ? '已设置 4 个角点' : '未使用手动角点，将由后端自动处理',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _editCorners,
                  ),
                ),
              ],
              if (_preview == null &&
                  !_previewing &&
                  _selectedFile != null &&
                  _validationErrors.isEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _createPreview,
                  icon: const Icon(Icons.image_search),
                  label: const Text('重新提取预览帧'),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _canUpload ? _upload : null,
                icon: _uploading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_uploading ? '正在上传' : '上传视频'),
              ),
              if (_uploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _uploadProgress),
                const SizedBox(height: 6),
                Text(
                  '上传进度：${(_uploadProgress * 100).round()}%',
                  textAlign: TextAlign.center,
                ),
                const Text(
                  '超过 5 分钟将自动停止并提示超时',
                  textAlign: TextAlign.center,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedVideoCard extends StatelessWidget {
  const _SelectedVideoCard({
    required this.fileName,
    required this.fileSize,
    required this.duration,
    required this.inspecting,
    required this.errors,
    required this.warnings,
  });

  final String fileName;
  final int? fileSize;
  final Duration? duration;
  final bool inspecting;
  final List<String> errors;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.movie_outlined,
              label:
                  '格式：${UploadConstraints.extensionOf(fileName).toUpperCase()}',
            ),
            _InfoRow(
              icon: Icons.storage_outlined,
              label: fileSize == null
                  ? '大小：读取中'
                  : '大小：${UploadConstraints.formatBytes(fileSize!)}',
            ),
            _InfoRow(
              icon: Icons.timer_outlined,
              label: duration == null
                  ? '时长：${inspecting ? '读取中' : '无法读取'}'
                  : '时长：${UploadConstraints.formatDuration(duration!)}',
            ),
            if (inspecting) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else if (errors.isEmpty) ...[
              const SizedBox(height: 8),
              const _ValidationMessage(
                icon: Icons.check_circle,
                text: '视频检查通过，可以上传',
                isError: false,
              ),
              ...warnings.map(
                (message) => _ValidationMessage(
                  icon: Icons.info_outline,
                  text: message,
                  isError: false,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              ...errors.map(
                (message) => _ValidationMessage(
                  icon: Icons.error_outline,
                  text: message,
                  isError: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage({
    required this.icon,
    required this.text,
    required this.isError,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color =
        isError ? Theme.of(context).colorScheme.error : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
