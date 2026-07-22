import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();
  static const _eyeCareKey = 'eye_care_mode';
  static const _notificationsKey = 'analysis_notifications';

  final ValueNotifier<bool> eyeCareEnabled = ValueNotifier(false);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    eyeCareEnabled.value = preferences.getBool(_eyeCareKey) ?? false;
  }

  Future<void> setEyeCareEnabled(bool value) async {
    eyeCareEnabled.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_eyeCareKey, value);
  }

  Future<bool> notificationsEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_notificationsKey) ?? true;
  }

  Future<bool> hasNotificationsPreference() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.containsKey(_notificationsKey);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_notificationsKey, value);
  }
}
