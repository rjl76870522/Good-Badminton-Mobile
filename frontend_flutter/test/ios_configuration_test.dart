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
}
