import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/services/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('notifications default on but respect an explicit opt out', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppPreferences.instance.notificationsEnabled(), isTrue);
    expect(
      await AppPreferences.instance.hasNotificationsPreference(),
      isFalse,
    );

    await AppPreferences.instance.setNotificationsEnabled(false);
    expect(await AppPreferences.instance.notificationsEnabled(), isFalse);
    expect(
      await AppPreferences.instance.hasNotificationsPreference(),
      isTrue,
    );
  });
}
