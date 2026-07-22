import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:good_badminton_mobile/pages/daily_check_in_page.dart';

void main() {
  testWidgets('daily check-in only increments once per day', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: DailyCheckInPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('连续 0 天  ·  累计 0 天'), findsOneWidget);
    expect(find.text('签到后解锁今日内容'), findsOneWidget);
    expect(find.text('今日羽球故事'), findsNothing);
    await tester.tap(find.text('签到并领取今日故事'));
    await tester.pumpAndSettle();

    expect(find.text('今天已签到'), findsOneWidget);
    expect(find.text('连续 1 天  ·  累计 1 天'), findsOneWidget);
    expect(find.text('明天再来'), findsOneWidget);
    expect(find.text('今日羽球故事'), findsOneWidget);
    expect(find.textContaining('项目团队'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(home: DailyCheckInPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('连续 1 天  ·  累计 1 天'), findsOneWidget);
  });
}
