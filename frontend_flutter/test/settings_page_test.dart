import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:good_badminton_mobile/pages/settings_page.dart';
import 'package:good_badminton_mobile/services/app_preferences.dart';

void main() {
  testWidgets('settings expose privacy controls and eye care mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppPreferences.instance.eyeCareEnabled.value = false;
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('分析完成通知'), findsOneWidget);
    expect(find.text('护眼模式'), findsOneWidget);
    await tester.tap(find.text('护眼模式'));
    await tester.pumpAndSettle();
    expect(AppPreferences.instance.eyeCareEnabled.value, isTrue);

    await tester.scrollUntilVisible(find.text('用户协议'), 260);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('个人信息收集清单'), findsOneWidget);
    expect(find.text('第三方信息共享清单'), findsOneWidget);
    expect(find.text('商务合作'), findsOneWidget);
  });
}
