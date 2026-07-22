import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const _notifiedPrefix = 'task_notification_sent_';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? true;
  }

  Future<void> notifyTaskFinished({
    required String taskId,
    required String videoName,
    required bool completed,
  }) async {
    if (!await AppPreferences.instance.notificationsEnabled()) return;
    final preferences = await SharedPreferences.getInstance();
    final key = '$_notifiedPrefix$taskId';
    if (preferences.getBool(key) ?? false) return;
    await initialize();
    await _plugin.show(
      taskId.hashCode & 0x7fffffff,
      completed ? '训练分析已完成' : '训练分析未完成',
      completed
          ? '${videoName.isEmpty ? '训练视频' : videoName}的报告已经生成'
          : '${videoName.isEmpty ? '训练视频' : videoName}分析失败，请打开智羽查看原因',
      _notificationDetails,
    );
    await preferences.setBool(key, true);
  }

  Future<void> showTestNotification() async {
    await initialize();
    await _plugin.show(
      10001,
      '智羽通知测试',
      '通知功能可以正常显示，训练分析完成后会在这里提醒你',
      _notificationDetails,
    );
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'analysis_results',
      '分析结果',
      channelDescription: '视频分析完成或失败时发送提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );
}
