// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:good_badminton_app/main.dart';

void main() {
  testWidgets('App renders upload screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GoodBadmintonApp());
    await tester.pump();

    expect(find.text('AI 羽毛球训练复盘'), findsOneWidget);
    expect(find.text('上传视频'), findsOneWidget);
  });
}
