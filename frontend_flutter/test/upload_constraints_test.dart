import 'package:flutter_test/flutter_test.dart';

import 'package:good_badminton_mobile/config/upload_constraints.dart';

void main() {
  test('accepts supported video inside all limits', () {
    final result = UploadConstraints.validate(
      fileName: 'match.MP4',
      fileSizeBytes: 120 * 1024 * 1024,
      duration: const Duration(seconds: 90),
    );

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });

  test('rejects unsupported, oversized, under-five-second and long videos', () {
    final unsupported = UploadConstraints.validate(
      fileName: 'match.avi',
      fileSizeBytes: 600 * 1024 * 1024,
      duration: const Duration(seconds: 3),
    );
    expect(unsupported.errors, contains('仅支持 MP4、MOV、M4V 格式'));
    expect(unsupported.errors, contains('视频不能超过 500 MB'));
    expect(unsupported.errors, contains('视频不能短于 5 秒'));

    final longVideo = UploadConstraints.validate(
      fileName: 'match.mov',
      fileSizeBytes: 1,
      duration: const Duration(minutes: 4),
    );
    expect(longVideo.errors, contains('视频不能超过 3 分钟'));
  });

  test('allows short clips but recommends at least 30 seconds', () {
    final result = UploadConstraints.validate(
      fileName: 'short.mp4',
      fileSizeBytes: 1024,
      duration: const Duration(seconds: 10),
    );
    expect(result.isValid, isTrue);
    expect(result.warnings, isNotEmpty);
  });

  test('rejects empty or unreadable videos', () {
    final result = UploadConstraints.validate(
      fileName: 'match.mp4',
      fileSizeBytes: 0,
      duration: null,
    );

    expect(result.errors, contains('视频文件为空'));
    expect(result.errors, contains('无法读取视频时长，文件可能已损坏'));
  });
}
