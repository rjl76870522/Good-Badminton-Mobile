class TaskStatus {
  const TaskStatus({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.stage,
    required this.videoName,
    this.error,
    this.createdAt,
    this.updatedAt,
    this.reportUrl,
  });

  final String taskId;
  final String status;
  final double progress;
  final String stage;
  final String videoName;
  final String? error;
  final double? createdAt;
  final double? updatedAt;
  final String? reportUrl;

  bool get isRunning => status == 'queued' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  int get progressPercent => (progress.clamp(0.0, 1.0) * 100).round();

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    return TaskStatus(
      taskId: json['task_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      progress: _asDouble(json['progress']),
      stage: json['stage']?.toString() ?? '',
      videoName: json['video_name']?.toString() ?? '',
      error: json['error']?.toString(),
      createdAt: _asNullableDouble(json['created_at']),
      updatedAt: _asNullableDouble(json['updated_at']),
      reportUrl: json['report_url']?.toString(),
    );
  }

  static double _asDouble(dynamic value) {
    return _asNullableDouble(value) ?? 0.0;
  }

  static double? _asNullableDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}
