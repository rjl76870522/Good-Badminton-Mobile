import 'package:flutter_test/flutter_test.dart';
import 'package:good_badminton_mobile/services/venue_service.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

void main() {
  test('decodes the demo venue QR image', () async {
    final decoder = QRCodeDartScanDecoder(
      formats: const [BarcodeFormat.qrCode],
    );
    addTearDown(decoder.dispose);

    final result = await decoder.decodeFile(
      XFile('../mock_venue_server/venue_qr.png'),
    );

    final venue = const VenueService().parseVenueQr(result!.text);
    expect(venue.id, 'example');
    expect(venue.name, '示例球场');
    expect(
      venue.serverUrl,
      'https://api.audacity6441.kdns.fr/venue-demo',
    );
  });
}
