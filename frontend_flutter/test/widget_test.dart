import 'package:flutter/foundation.dart';
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
    expect(find.text('社区'), findsOneWidget);
    expect(find.text('我的'), findsWidgets);

    await tester.tap(find.text('发现'));
    await tester.pump();
    expect(find.text('附近羽毛球馆'), findsOneWidget);
    expect(find.text('大赛日历'), findsNothing);

    await tester.tap(find.text('社区'));
    await tester.pump();
    expect(find.text('大赛日历'), findsOneWidget);
    expect(find.text('世界排名'), findsOneWidget);
    expect(find.text('球星资料'), findsOneWidget);
    expect(find.text('装备库'), findsOneWidget);
    expect(find.text('近期赛事与球星新闻'), findsOneWidget);

    await tester.tap(find.text('发现'));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('discover-list')),
      const Offset(0, -650),
    );
    await tester.pump();
    expect(find.text('高德地图'), findsWidgets);
    expect(find.textContaining('中心服务器'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('discover-list')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(find.text('东北大学南湖校区羽乒馆'), findsWidgets);
    await tester.drag(
      find.byKey(const ValueKey('discover-list')),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(find.text('浙江大学紫金港校区风雨操场'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pump();

    expect(find.text('我的'), findsWidgets);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('遇到问题，联系开发者'), findsOneWidget);
    expect(find.text('jialeR01@126.com'), findsOneWidget);
    expect(find.text('查看或编辑个人主页 >'), findsOneWidget);
    expect(find.text('训练与球馆'), findsOneWidget);
    expect(find.text('每日签到'), findsOneWidget);
    expect(find.text('数据身份'), findsNothing);
    expect(find.text('检查数据身份'), findsNothing);
    expect(find.textContaining('guest_'), findsNothing);
    expect(find.textContaining('无需登录'), findsNothing);
    await tester.scrollUntilVisible(find.text('智羽 · 版本 0.1.2'), 180);
    expect(find.text('智羽 · 版本 0.1.2'), findsOneWidget);
    expect(find.textContaining('Build'), findsNothing);
  });

  testWidgets('community uses shared scroll and press feedback',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GoodBadmintonApp());

    await tester.tap(find.text('社区'));
    await tester.pump();

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('community-list')),
    );
    expect(list.physics, isA<AlwaysScrollableScrollPhysics>());

    final card = find.byKey(
      const ValueKey('community-card-calendar'),
    );
    final scale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    final gestureDetector = tester.widget<GestureDetector>(
      find.descendant(
        of: card,
        matching: find.byType(GestureDetector),
      ),
    );
    gestureDetector.onTapDown!(TapDownDetails());
    await tester.pump();
    expect(tester.widget<AnimatedScale>(scale).scale, 0.965);

    gestureDetector.onTapCancel!();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
  });

  testWidgets('editing a Chinese nickname closes cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(const GoodBadmintonApp());
    await tester.tap(find.text('我的').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('修改昵称'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextFormField), '羽球爱好者');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 500));
    debugDefaultTargetPlatformOverride = null;

    expect(find.text('羽球爱好者'), findsOneWidget);
    expect(find.text('修改昵称'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final device in <String, ({Size size, TargetPlatform platform})>{
    'Android compact': (
      size: const Size(360, 640),
      platform: TargetPlatform.android,
    ),
    'Android standard': (
      size: const Size(360, 800),
      platform: TargetPlatform.android,
    ),
    'Android large': (
      size: const Size(412, 915),
      platform: TargetPlatform.android,
    ),
    'iPhone SE': (
      size: const Size(375, 667),
      platform: TargetPlatform.iOS,
    ),
    'iPhone XR': (
      size: const Size(414, 896),
      platform: TargetPlatform.iOS,
    ),
    'iPhone 15 Pro': (
      size: const Size(393, 852),
      platform: TargetPlatform.iOS,
    ),
    'iPhone 15 Pro Max': (
      size: const Size(430, 932),
      platform: TargetPlatform.iOS,
    ),
  }.entries) {
    testWidgets('${device.key} portrait layout has no overflow',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = device.value.platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.binding.setSurfaceSize(device.value.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const GoodBadmintonApp());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('发现'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('附近羽毛球馆'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('社区'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('羽球内容'), findsOneWidget);
      expect(find.text('大赛日历'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.fling(
        find.byKey(const ValueKey('community-list')),
        const Offset(0, -300),
        900,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('我的').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('我的'), findsWidgets);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('数据身份'), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
