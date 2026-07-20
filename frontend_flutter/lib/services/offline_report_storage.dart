import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import 'api_service.dart';

class OfflineReportRecord {
  const OfflineReportRecord({
    required this.taskId,
    required this.videoName,
    required this.savedAt,
    required this.reportPath,
    this.heatmapPath,
    this.trajectoryPath,
  });

  final String taskId;
  final String videoName;
  final DateTime savedAt;
  final String reportPath;
  final String? heatmapPath;
  final String? trajectoryPath;

  factory OfflineReportRecord.fromJson(Map<String, dynamic> json) {
    return OfflineReportRecord(
      taskId: json['task_id']?.toString() ?? '',
      videoName: json['video_name']?.toString() ?? '',
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reportPath: json['report_path']?.toString() ?? '',
      heatmapPath: _nullable(json['heatmap_path']),
      trajectoryPath: _nullable(json['trajectory_path']),
    );
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'video_name': videoName,
        'saved_at': savedAt.toIso8601String(),
        'report_path': reportPath,
        'heatmap_path': heatmapPath,
        'trajectory_path': trajectoryPath,
      };

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class OfflineReportStorage {
  Future<Directory> _root() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory =
        Directory('${documents.path}/GoodBadminton/offline_reports');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _indexFile() async => File('${(await _root()).path}/index.json');

  Future<List<OfflineReportRecord>> list() async {
    final index = await _indexFile();
    if (!await index.exists()) return const [];
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is! List) return const [];
      final records = decoded
          .whereType<Map>()
          .map(
            (item) => OfflineReportRecord.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where(
            (record) =>
                record.taskId.isNotEmpty &&
                record.reportPath.isNotEmpty &&
                File(record.reportPath).existsSync(),
          )
          .toList();
      records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return records;
    } on FormatException {
      return const [];
    }
  }

  Future<OfflineReportRecord> save({
    required ApiService api,
    required String taskId,
    required String videoName,
    void Function(double progress, String stage)? onProgress,
  }) async {
    onProgress?.call(0.05, '正在读取训练报告');
    final payload = await api.getReportPayload(taskId);
    onProgress?.call(0.2, '正在保存图表');
    final root = await _root();
    final directory = Directory('${root.path}/$taskId');
    await directory.create(recursive: true);

    final files = payload['files'];
    final fileMap = files is Map
        ? files.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    var heatmapProgress = 0.0;
    var trajectoryProgress = 0.0;
    void reportDownloadProgress() {
      final combined = (heatmapProgress + trajectoryProgress) / 2;
      onProgress?.call(0.2 + combined * 0.65, '正在下载热力图和轨迹图');
    }

    final paths = await Future.wait([
      _downloadImage(
        api,
        fileMap['heatmap'],
        directory,
        'heatmap.png',
        onProgress: (value) {
          heatmapProgress = value;
          reportDownloadProgress();
        },
      ),
      _downloadImage(
        api,
        fileMap['trajectory'],
        directory,
        'trajectory.png',
        onProgress: (value) {
          trajectoryProgress = value;
          reportDownloadProgress();
        },
      ),
    ]);
    final heatmapPath = paths[0];
    final trajectoryPath = paths[1];
    onProgress?.call(0.9, '正在写入手机存储');
    final reportFile = File('${directory.path}/report.json');
    await reportFile.writeAsString(jsonEncode(payload), flush: true);

    final record = OfflineReportRecord(
      taskId: taskId,
      videoName: videoName,
      savedAt: DateTime.now(),
      reportPath: reportFile.path,
      heatmapPath: heatmapPath,
      trajectoryPath: trajectoryPath,
    );
    final records = (await list())
        .where((item) => item.taskId != taskId)
        .toList()
      ..insert(0, record);
    await _writeIndex(records);
    onProgress?.call(1, '离线保存完成');
    return record;
  }

  Future<Map<String, dynamic>> readReport(OfflineReportRecord record) async {
    final decoded = jsonDecode(await File(record.reportPath).readAsString());
    if (decoded is! Map) throw const FormatException('离线报告格式无效');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> delete(OfflineReportRecord record) async {
    final directory = File(record.reportPath).parent;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    final records =
        (await list()).where((item) => item.taskId != record.taskId).toList();
    await _writeIndex(records);
  }

  Future<void> clearAll() async {
    final root = await _root();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  Future<String?> _downloadImage(
    ApiService api,
    dynamic relativeUrl,
    Directory directory,
    String filename, {
    void Function(double progress)? onProgress,
  }) async {
    final url = ApiConfig.absoluteFileUrl(relativeUrl?.toString());
    if (url == null) {
      onProgress?.call(1);
      return null;
    }
    try {
      return await api.downloadFile(
        url,
        '${directory.path}/$filename',
        onProgress: onProgress,
      );
    } on Exception {
      // The text report remains useful when an optional chart is unavailable.
      onProgress?.call(1);
      return null;
    }
  }

  Future<void> _writeIndex(List<OfflineReportRecord> records) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(records.map((record) => record.toJson()).toList()),
      flush: true,
    );
  }
}
