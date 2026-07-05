import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class UserStorage {
  UserStorage({Random? random}) : _random = random ?? Random.secure();

  static const _userIdKey = 'guest_user_id';
  static const _nicknameKey = 'guest_nickname';
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

  Future<String> getNickname() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_nicknameKey) ?? '羽球访客';
  }

  Future<void> setNickname(String nickname) async {
    final value = nickname.trim().isEmpty ? '羽球访客' : nickname.trim();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nicknameKey, value);
  }
}
