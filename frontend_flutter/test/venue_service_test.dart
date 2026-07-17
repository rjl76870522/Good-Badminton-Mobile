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

  test('parses a venue QR link with query parameters', () {
    final venue = service.parseVenueQr(
      'goodbadminton://venue?venue_id=NEU_001&venue_name=%E4%B8%9C%E5%A4%A7%E7%BE%BD%E6%AF%9B%E7%90%83%E9%A6%86&server_url=http%3A%2F%2F192.168.31.8%3A8091',
    );

    expect(venue.id, 'NEU_001');
    expect(venue.name, '东大羽毛球馆');
    expect(venue.serverUrl, 'http://192.168.31.8:8091');
  });

  test('parses a plain venue server URL', () {
    final venue = service.parseVenueQr('https://venue.example.com:8443');

    expect(venue.id, 'venue.example.com');
    expect(venue.name, 'venue.example.com');
    expect(venue.serverUrl, 'https://venue.example.com:8443');
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
