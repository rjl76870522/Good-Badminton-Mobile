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
    expect(find.text('开始上传视频'), findsOneWidget);
    expect(find.text('进入示例球场'), findsOneWidget);
    expect(find.text('扫描合作球馆'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('宣传页面'), 160);
    expect(find.text('宣传页面'), findsOneWidget);
    expect(find.text('Demo'), findsNothing);
    expect(find.text('附近羽毛球馆'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('我的'), findsWidgets);

    await tester.tap(find.text('发现'));
    await tester.pump();
    expect(find.text('附近羽毛球馆'), findsOneWidget);
    expect(find.text('高德地图'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('校园场馆示例'), 220);
    expect(find.text('东北大学南湖校区羽乒馆'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('浙江大学紫金港校区风雨操场'),
      220,
    );
    expect(find.text('浙江大学紫金港校区风雨操场'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pump();

    expect(find.text('我的'), findsWidgets);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('点击头像可以从相册更换'), findsOneWidget);
    expect(find.text('训练与球馆'), findsOneWidget);
    expect(find.text('数据身份'), findsNothing);
    expect(find.text('检查数据身份'), findsNothing);
    expect(find.textContaining('guest_'), findsNothing);
    expect(find.textContaining('无需登录'), findsNothing);
    await tester.scrollUntilVisible(find.text('版本 0.1.2'), 180);
    expect(find.text('版本 0.1.2'), findsOneWidget);
    expect(find.textContaining('Build'), findsNothing);
  });

  for (final device in <String, Size>{
    'iPhone 14': const Size(390, 844),
    'iPhone 15 Pro': const Size(393, 852),
  }.entries) {
    testWidgets('${device.key} portrait layout has no overflow',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(device.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const GoodBadmintonApp());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('发现'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('附近羽毛球馆'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('我的').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('我的'), findsWidgets);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('数据身份'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
