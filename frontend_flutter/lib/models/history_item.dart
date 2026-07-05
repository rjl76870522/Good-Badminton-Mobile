import 'report.dart';

class HistoryItem {
  const HistoryItem({
    required this.taskId,
    required this.userId,
    required this.status,
    required this.videoName,
    required this.summary,
    required this.files,
    this.thumbnail,
    this.reportUrl,
    this.progress = 0,
    this.stage = '',
    this.error,
  });

  final String taskId;
  final String userId;
  final String status;
  final String videoName;
  final ReportSummary summary;
  final ReportFiles files;
  final String? thumbnail;
  final String? reportUrl;
  final double progress;
  final String stage;
  final String? error;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  int get progressPercent => (progress.clamp(0, 1) * 100).round();

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      taskId: json['task_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      videoName: json['video_name']?.toString() ?? '',
      summary: ReportSummary.fromJson(mapValue(json['summary'])),
      files: ReportFiles.fromJson(mapValue(json['files'])),
      thumbnail: nullableString(json['thumbnail']),
      reportUrl: nullableString(json['report_url']),
      progress: numberValue(json['progress']),
      stage: json['stage']?.toString() ?? '',
      error: nullableString(json['error']),
    );
  }
}
