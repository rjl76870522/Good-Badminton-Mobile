import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/pages/badminton_knowledge_page.dart';

void main() {
  testWidgets('knowledge module switches between all four sections',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BadmintonKnowledgePage()),
    );

    expect(find.text('观赛日历'), findsOneWidget);

    await tester.tap(find.text('世界排名'));
    await tester.pump();
    expect(find.text('认识世界排名'), findsOneWidget);

    await tester.tap(find.text('球星资料'));
    await tester.pump();
    expect(find.text('现役球员观察'), findsOneWidget);
    expect(find.text('石宇奇'), findsOneWidget);
    expect(find.text('郑思维 / 黄雅琼'), findsNothing);

    await tester.tap(find.text('装备库'));
    await tester.pump();
    expect(find.text('按需求选择装备'), findsOneWidget);
  });
}
