import 'dart:async';

import 'api_service.dart';
import 'notification_service.dart';
import 'task_storage.dart';

class TaskNotificationMonitor {
  TaskNotificationMonitor._();

  static final TaskNotificationMonitor instance = TaskNotificationMonitor._();

  final TaskStorage _storage = TaskStorage();
  Timer? _timer;
  bool _checking = false;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkNow(),
    );
    checkNow();
  }

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    final api = ApiService();
    try {
      for (final taskId in await _storage.getActiveTaskIds()) {
        try {
          final task = await api.getTask(taskId);
          if (task.isRunning) continue;
          await NotificationService.instance.notifyTaskFinished(
            taskId: task.taskId,
            videoName: task.videoName,
            completed: task.isCompleted,
          );
          if (task.isCompleted) {
            await _storage.removeUpload(taskId);
          } else {
            await _storage.clearActiveTask(taskId);
          }
        } catch (_) {
          // 网络短暂中断时保留任务，下一轮继续检查。
        }
      }
    } finally {
      api.close();
      _checking = false;
    }
  }
}
