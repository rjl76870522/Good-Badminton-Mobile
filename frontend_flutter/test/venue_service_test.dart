import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/services/venue_service.dart';

void main() {
  const service = VenueService();

  test('parses a valid venue QR payload', () {
    final venue = service.parseVenueQr('''
      {"type":"venue","venue_id":"SZ_BADMINTON_001","venue_name":"深圳XX羽毛球馆","server_url":"http://192.168.1.100"}
    ''');

    expect(venue.id, 'SZ_BADMINTON_001');
    expect(venue.name, '深圳XX羽毛球馆');
    expect(venue.serverUrl, 'http://192.168.1.100');
  });

  test('rejects invalid venue QR payload', () {
    expect(
      () => service.parseVenueQr('{"type":"not-venue"}'),
      throwsA(isA<VenueQrException>()),
    );
  });

  test('returns mock venue videos', () {
    final videos = service.getMockVideos();

    expect(videos, hasLength(2));
    expect(videos.first.court, '1号场');
  });
}
