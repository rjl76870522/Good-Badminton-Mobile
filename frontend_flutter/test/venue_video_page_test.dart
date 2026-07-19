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
  testWidgets('renders the compact venue video list', (tester) async {
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

    expect(find.text('选择比赛视频'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
    expect(find.text('1号场'), findsAtLeastNWidgets(2));
    expect(find.text('2号场'), findsAtLeastNWidgets(2));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
  });

  testWidgets('demo venue uses the same concise list presentation',
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
    expect(find.text('球馆录像片段 01 · 8秒'), findsOneWidget);
    expect(find.text('球馆录像片段 02 · 11秒'), findsOneWidget);
  });
}
