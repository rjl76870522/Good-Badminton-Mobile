import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/models/venue.dart';
import 'package:good_badminton_mobile/pages/venue_video_page.dart';
import 'package:good_badminton_mobile/services/venue_service.dart';

class _FakeVenueService extends VenueService {
  const _FakeVenueService();

  @override
  Future<List<VenueVideo>> getVideos(VenueInfo venue) async => getMockVideos();
}

void main() {
  testWidgets('renders every venue video card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VenueVideoPage(
          venue: VenueInfo(
            id: 'SZ_BADMINTON_001',
            name: '智慧羽毛球馆',
            serverUrl: 'https://venue.example.com',
          ),
          service: _FakeVenueService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('共 2 条'), findsOneWidget);
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('1号场'), findsNWidgets(2));
    expect(find.text('2号场'), findsNWidgets(2));
    expect(find.text('选择'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, '1号场'));
    await tester.pumpAndSettle();
    expect(find.text('共 1 条'), findsOneWidget);
    expect(find.text('选择'), findsOneWidget);
  });

  testWidgets('demo venue shows venue 24 and prepared clip notice',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VenueVideoPage(
          venue: VenueInfo(
            id: '24',
            name: '演示球馆',
            serverUrl: 'https://venue.example.com',
          ),
          showDemoOnOpen: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('球馆编号：24'), findsOneWidget);
    expect(
      find.text('已从球馆存储的完整视频中截取出准备分析的视频片段'),
      findsOneWidget,
    );
    expect(find.text('时间：球馆录像片段 01'), findsOneWidget);
    expect(find.text('时间：球馆录像片段 02'), findsOneWidget);
  });
}
