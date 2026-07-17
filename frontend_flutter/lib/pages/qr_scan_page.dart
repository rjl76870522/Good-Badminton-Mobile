import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/venue.dart';
import '../services/venue_service.dart';
import 'venue_video_page.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.service = const VenueService()});

  final VenueService service;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _error;

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_handled) return;
    String? rawValue;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        rawValue = value;
        break;
      }
    }
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _handled = true);
    await _controller.stop();
    try {
      final VenueInfo venue = widget.service.parseVenueQr(rawValue);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VenueVideoPage(venue: venue)),
      );
    } on VenueQrException catch (error) {
      if (!mounted) return;
      setState(() {
        _handled = false;
        _error = error.message;
      });
      await _controller.start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描球馆二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _handleBarcode),
            Center(
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.72,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 28,
              child: Column(
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB42318)),
                      ),
                    ),
                  const Text(
                    '将球馆提供的二维码放入取景框内',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
