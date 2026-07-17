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
    expect(find.text('1号场'), findsOneWidget);
    expect(find.text('2号场'), findsOneWidget);
    expect(find.text('选择'), findsNWidgets(2));
  });
}
