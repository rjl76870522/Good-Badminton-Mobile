import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS project keeps the required runtime permissions and identity', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    for (final key in const [
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
      'NSLocationWhenInUseUsageDescription',
      'NSLocalNetworkUsageDescription',
    ]) {
      expect(plist, contains('<key>$key</key>'));
    }
    for (final scheme in const ['iosamap', 'baidumap', 'imeituan']) {
      expect(plist, contains('<string>$scheme</string>'));
    }
    expect(project, contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;'));
    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.rundon2026.goodbadminton;'),
    );
    expect(appDelegate, contains('import UserNotifications'));
    expect(
      appDelegate,
      contains('UNUserNotificationCenter.current().delegate = self'),
    );
  });

  test('QR scanner keeps the iOS rear-camera path and simulator guidance', () {
    final source = File('lib/pages/qr_scan_page.dart').readAsStringSync();

    expect(source, contains('typeCamera: TypeCamera.back'));
    expect(source, contains('Appetize 等 iOS 模拟器通常不提供真实摄像头'));
  });

  test('venue videos always expose the clip range selector', () {
    final source = File('lib/pages/video_detail_page.dart').readAsStringSync();

    expect(source, contains("Key('venue-clip-selector')"));
    expect(source, isNot(contains('controller != null && !_isBundledDemo')));
    expect(source, contains("_venueVideoUrl('videos/\$serverVideoId/clip')"));
  });
}
