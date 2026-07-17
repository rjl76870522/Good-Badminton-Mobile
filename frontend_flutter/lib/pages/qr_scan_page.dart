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

  Future<void> _openVenue(VenueInfo venue) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VenueVideoPage(venue: venue)),
    );
  }

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
      await _openVenue(venue);
    } on VenueQrException catch (error) {
      if (!mounted) return;
      setState(() {
        _handled = false;
        _error = error.message;
      });
      await _restartScanner();
    }
  }

  Future<void> _restartScanner() async {
    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      if (!mounted) return;
      setState(() => _error = _scannerErrorMessage(error));
    }
  }

  Future<void> _retryScanner() async {
    setState(() {
      _handled = false;
      _error = null;
    });
    await _restartScanner();
  }

  Future<void> _showManualInput() async {
    final textController = TextEditingController();
    final rawValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动输入二维码内容'),
        content: TextField(
          controller: textController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴球馆二维码里的 JSON 或链接',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(textController.text.trim()),
            child: const Text('进入球馆'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (rawValue == null || rawValue.isEmpty) return;
    try {
      final venue = widget.service.parseVenueQr(rawValue);
      await _controller.stop();
      await _openVenue(venue);
    } on VenueQrException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _openDemoVenue() async {
    try {
      await _controller.stop();
    } on MobileScannerException {
      // The demo route should remain available even when camera startup failed.
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const VenueVideoPage(
          venue: VenueInfo(
            id: 'demo-venue',
            name: '演示球馆',
            serverUrl: 'https://venue.example.com',
          ),
          showDemoOnOpen: true,
        ),
      ),
    );
  }

  String _scannerErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return '相机权限未开启。请到系统设置里允许“智羽”使用相机，或使用手动输入。';
      case MobileScannerErrorCode.unsupported:
        return '当前设备不支持相机扫码，请使用手动输入。';
      case MobileScannerErrorCode.controllerAlreadyInitialized:
        return '相机已经在运行，请重新尝试扫码。';
      case MobileScannerErrorCode.controllerDisposed:
        return '扫码页面已经关闭，请返回后重新进入。';
      case MobileScannerErrorCode.controllerUninitialized:
        return '相机还没有启动完成，请点“重新启动相机”。';
      case MobileScannerErrorCode.genericError:
        final detail = error.errorDetails?.message;
        if (detail != null && detail.trim().isNotEmpty) {
          return '相机启动失败：$detail';
        }
        return '相机启动失败，请检查权限、关闭其他占用相机的应用后重试。';
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
            MobileScanner(
              controller: _controller,
              onDetect: _handleBarcode,
              errorBuilder: (context, error, child) => _ScannerErrorPanel(
                message: _scannerErrorMessage(error),
                onRetry: _retryScanner,
                onManualInput: _showManualInput,
                onDemo: _openDemoVenue,
              ),
              placeholderBuilder: (context, child) => const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        '正在启动相机',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showManualInput,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: const Text('手动输入'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openDemoVenue,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                        icon: const Icon(Icons.sports_tennis_outlined),
                        label: const Text('演示球馆'),
                      ),
                    ],
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

class _ScannerErrorPanel extends StatelessWidget {
  const _ScannerErrorPanel({
    required this.message,
    required this.onRetry,
    required this.onManualInput,
    required this.onDemo,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onManualInput;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 42,
                  color: Color(0xFFB42318),
                ),
                const SizedBox(height: 12),
                const Text(
                  '相机扫码暂时不可用',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新启动相机'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onManualInput,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: const Text('手动输入'),
                    ),
                    TextButton(
                      onPressed: onDemo,
                      child: const Text('查看演示球馆'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
