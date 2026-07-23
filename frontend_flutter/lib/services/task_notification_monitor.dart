import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'task_storage.dart';

class TaskNotificationMonitor with WidgetsBindingObserver {
  TaskNotificationMonitor._();

  static final TaskNotificationMonitor instance = TaskNotificationMonitor._();

  final TaskStorage _storage = TaskStorage();
  Timer? _timer;
  bool _checking = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => checkNow(),
    );
    checkNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkNow();
  }

  /// Returns true while at least one task still needs a later status check.
  Future<bool> checkNow() async {
    if (_checking) return true;
    _checking = true;
    var hasPendingTasks = false;
    final api = ApiService();
    try {
      for (final taskId in await _storage.getActiveTaskIds()) {
        try {
          final task = await api.getTask(taskId);
          if (task.isRunning) {
            hasPendingTasks = true;
            continue;
          }
          final notificationHandled =
              await NotificationService.instance.notifyTaskFinished(
            taskId: task.taskId,
            videoName: task.videoName,
            completed: task.isCompleted,
          );
          if (!notificationHandled) continue;
          if (task.isCompleted) {
            await _storage.removeUpload(taskId);
          } else {
            await _storage.clearActiveTask(taskId);
          }
        } catch (_) {
          // 网络短暂中断时保留任务，下一轮继续检查。
          hasPendingTasks = true;
        }
      }
    } finally {
      api.close();
      _checking = false;
    }
    return hasPendingTasks;
  }
}
