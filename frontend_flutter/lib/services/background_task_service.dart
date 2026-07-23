import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'task_notification_monitor.dart';

const _taskCheckName = 'analysis-task-status-check';
const _periodicTaskCheckName = 'analysis-task-status-periodic-check';

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final hasPendingTasks = await TaskNotificationMonitor.instance.checkNow();
    // Android retries one-off work while analysis is still running.
    return task == Workmanager.iOSBackgroundTask || !hasPendingTasks;
  });
}

class BackgroundTaskService {
  BackgroundTaskService._();

  static final BackgroundTaskService instance = BackgroundTaskService._();

  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await Workmanager().initialize(backgroundTaskDispatcher);
      if (Platform.isAndroid) {
        await Workmanager().registerPeriodicTask(
          _periodicTaskCheckName,
          _taskCheckName,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('初始化后台任务失败: $error\n$stackTrace');
    }
  }

  Future<void> scheduleTaskCheck(String taskId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().registerOneOffTask(
        'analysis-task-$taskId',
        _taskCheckName,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (error, stackTrace) {
      // 后台提醒属于增强能力，注册失败不能让已创建的分析任务显示为上传失败。
      debugPrint('注册任务后台提醒失败: $error\n$stackTrace');
    }
  }
}
