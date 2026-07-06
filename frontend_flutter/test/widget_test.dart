import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:good_badminton_mobile/main.dart';

void main() {
  testWidgets('App starts on the Good-Badminton home page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodBadmintonApp());

    expect(find.text('Good-Badminton'), findsOneWidget);
    expect(find.text('羽毛球 AI 视觉分析'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
    expect(find.text('开始上传视频'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('历史记录'), findsWidgets);
    expect(find.text('训练档案'), findsWidgets);

    await tester.tap(find.text('训练档案').last);
    await tester.pump();

    expect(find.text('后端游客身份'), findsOneWidget);
    expect(find.text('查询游客身份'), findsOneWidget);
  });
}
