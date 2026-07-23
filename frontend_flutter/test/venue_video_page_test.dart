import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/models/venue.dart';
import 'package:good_badminton_mobile/pages/venue_video_page.dart';
import 'package:good_badminton_mobile/services/venue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVenueService extends VenueService {
  const _FakeVenueService();

  @override
  Future<List<VenueVideo>> getVideos(VenueInfo venue) async => const [
        VenueVideo(
          id: 'one',
          court: '1号场',
          time: '2026-07-20 00:55',
          duration: '22 秒',
        ),
        VenueVideo(
          id: 'two',
          court: '2号场',
          time: '2026-07-20 01:20',
          duration: '35 秒',
        ),
      ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const page = MaterialApp(
    home: VenueVideoPage(
      venue: VenueInfo(
        id: 'SZ_BADMINTON_001',
        name: '合作球馆',
        serverUrl: 'https://venue.example.com',
      ),
      service: _FakeVenueService(),
    ),
  );

  testWidgets('defaults to a floorplan and groups videos by court',
      (tester) async {
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();

    expect(find.text('场馆地图'), findsOneWidget);
    expect(find.byKey(const Key('court-tile-1号场')), findsOneWidget);
    expect(find.byKey(const Key('court-tile-10号场')), findsOneWidget);
    expect(find.textContaining('2 段录像'), findsOneWidget);

    await tester.tap(find.byKey(const Key('court-tile-1号场')));
    await tester.pumpAndSettle();
    expect(find.text('1号场 录像列表（共 1 条）'), findsOneWidget);
    expect(find.text('00:22'), findsOneWidget);
  });

  testWidgets('switches to the compact grouped list mode', (tester) async {
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('venue-view-switch')));
    await tester.pumpAndSettle();

    expect(find.text('全部录像 · 2 段'), findsOneWidget);
    expect(find.text('1号场 · 1 段录像'), findsOneWidget);
    expect(find.text('2号场 · 1 段录像'), findsOneWidget);
  });

  testWidgets('favorite filter never disables floorplan courts',
      (tester) async {
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('venue-favorites-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('court-tile-1号场')));
    await tester.pumpAndSettle();

    expect(find.text('1号场 录像列表（共 1 条）'), findsOneWidget);
  });
}
