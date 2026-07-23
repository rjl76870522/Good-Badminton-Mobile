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
    expect(find.text('世界第一 · 现役标杆'), findsOneWidget);
    expect(find.text('石宇奇'), findsOneWidget);
    expect(find.text('昆拉武特·维提讪'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('王祉怡'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('王祉怡'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('装备库'),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('装备库'));
    await tester.pump();
    expect(find.text('按需求选择装备'), findsOneWidget);
  });
}
