import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {
  UserStorage({Random? random}) : _random = random ?? Random.secure();

  static const _userIdKey = 'guest_user_id';
  static const _nicknameKey = 'guest_nickname';
  static const _avatarPathKey = 'profile_avatar_path';
  static const _autoPlayVideosKey = 'auto_play_report_videos';
  final Random _random;

  Future<String> getOrCreateUserId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_userIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    final id =
        'guest_${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
    await preferences.setString(_userIdKey, id);
    return id;
  }

  /// Get local nickname (fallback values are just display hints).
  Future<String> getNickname() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_nicknameKey) ?? '';
  }

  /// Save locally. Caller should also push to server via
  /// ApiService.updateDisplayName().
  Future<void> setNickname(String nickname) async {
    final value = nickname.trim();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nicknameKey, value);
  }

  /// Convenience: clear local nickname cache.
  Future<void> clearNickname() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_nicknameKey);
  }

  Future<String?> getAvatarPath() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_avatarPathKey);
  }

  Future<void> setAvatarPath(String path) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_avatarPathKey, path);
  }

  Future<bool> getAutoPlayVideos() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_autoPlayVideosKey) ?? false;
  }

  Future<void> setAutoPlayVideos(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoPlayVideosKey, value);
  }
}
