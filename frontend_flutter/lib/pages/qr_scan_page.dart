import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

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
  bool _handled = false;
  bool _checkingPermission = true;
  bool _cameraReady = false;
  int _scannerGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareScanner());
  }

  Future<void> _openVenue(VenueInfo venue) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VenueVideoPage(venue: venue)),
    );
  }

  Future<void> _handleBarcode(Result result) async {
    if (_handled) return;
    final rawValue = result.text.trim();
    if (rawValue.isEmpty) return;

    setState(() => _handled = true);
    try {
      final VenueInfo venue = widget.service.parseVenueQr(rawValue);
      await _openVenue(venue);
    } on VenueQrException catch (error) {
      if (!mounted) return;
      setState(() {
        _handled = false;
        _error = error.message;
      });
    }
  }

  Future<bool> _requestCameraPermission() async {
    setState(() => _checkingPermission = true);
    final status = await Permission.camera.status;
    final result =
        status.isGranted ? status : await Permission.camera.request();
    if (!mounted) return false;
    if (result.isGranted) {
      setState(() {
        _checkingPermission = false;
        _cameraReady = true;
      });
      return true;
    }
    final permanentlyDenied = result.isPermanentlyDenied || result.isRestricted;
    setState(() {
      _checkingPermission = false;
      _cameraReady = false;
      _error = permanentlyDenied
          ? '相机权限被系统关闭。请到设置里允许“智羽”使用相机。'
          : '相机权限未开启，请允许后再扫描球馆二维码。';
    });
    return false;
  }

  Future<void> _prepareScanner() async {
    final allowed = await _requestCameraPermission();
    if (!allowed || !mounted) return;
    setState(() {
      _scannerGeneration += 1;
      _error = null;
    });
  }

  Future<void> _retryScanner() async {
    setState(() {
      _handled = false;
      _error = null;
      _cameraReady = false;
    });
    await _prepareScanner();
  }

  void _handleCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _cameraReady = false;
      _checkingPermission = false;
      _error = _cameraErrorMessage(message);
    });
  }

  Future<void> _openCameraSettings() async {
    await openAppSettings();
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
      await _openVenue(venue);
    } on VenueQrException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _openDemoVenue() async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const VenueVideoPage(
          venue: VenueInfo(
            id: '24',
            name: '演示球馆',
            serverUrl: 'https://venue.example.com',
          ),
          showDemoOnOpen: true,
        ),
      ),
    );
  }

  String _cameraErrorMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('accessdenied') ||
        normalized.contains('permission')) {
      return '相机权限未开启，请到系统设置中允许“智羽”使用相机';
    }
    if (normalized.contains('camera_not_found')) {
      return '没有找到可用的后置相机';
    }
    if (normalized.contains('cameraaccess') || normalized.contains('in_use')) {
      return '相机正在被其他应用占用，请关闭其他相机应用后重试';
    }
    return '相机初始化失败（$message）';
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
            if (_cameraReady && !_checkingPermission)
              QRCodeDartScanView(
                key: ValueKey(_scannerGeneration),
                typeCamera: TypeCamera.back,
                typeScan: TypeScan.live,
                formats: const [BarcodeFormat.qrCode],
                resolutionPreset: QRCodeDartScanResolutionPreset.medium,
                intervalScan: const Duration(milliseconds: 700),
                onCapture: _handleBarcode,
                onCameraError: _handleCameraError,
              )
            else
              const ColoredBox(color: Colors.black),
            if (_cameraReady && !_checkingPermission)
              Center(
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.72,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: IgnorePointer(
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
              ),
            if (_cameraReady && !_checkingPermission)
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
            if (!_cameraReady || _checkingPermission)
              _CameraPermissionPanel(
                checking: _checkingPermission,
                title: _error?.contains('权限') == true
                    ? '需要开启相机权限'
                    : _error != null
                        ? '相机启动遇到问题'
                        : '准备启动相机',
                message: _error ?? '需要相机权限才能扫描球馆二维码',
                onRetry: _retryScanner,
                onOpenSettings: _openCameraSettings,
                onManualInput: _showManualInput,
                onDemo: _openDemoVenue,
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraPermissionPanel extends StatelessWidget {
  const _CameraPermissionPanel({
    required this.checking,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onManualInput,
    required this.onDemo,
  });

  final bool checking;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
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
                Icon(
                  checking ? Icons.camera_alt_outlined : Icons.no_photography,
                  size: 42,
                  color: const Color(0xFF1B5E20),
                ),
                const SizedBox(height: 12),
                Text(
                  checking ? '正在检查相机权限' : title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  checking ? '如果系统弹出权限窗口，请选择允许。' : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 18),
                if (checking)
                  const CircularProgressIndicator()
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重新请求权限'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('打开系统设置'),
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
