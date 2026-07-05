import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:good_badminton_mobile/services/api_service.dart';

void main() {
  test('upload reports byte progress and keeps Mobile API fields', () async {
    final directory = await Directory.systemTemp.createTemp('gb_upload_test_');
    final file = File('${directory.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes(List<int>.filled(4096, 7));
    final client = _SuccessfulUploadClient();
    final progress = <double>[];
    final service = ApiService(client: client);

    try {
      final result = await service.uploadVideo(
        file.path,
        userId: 'guest_test',
        onProgress: progress.add,
      );

      expect(result.taskId, 'test-task-id');
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(progress.any((value) => value > 0 && value < 1), isTrue);
      expect(client.request, isA<http.MultipartRequest>());
      final request = client.request! as http.MultipartRequest;
      expect(request.files.single.field, 'file');
      expect(request.fields['language'], 'zh');
      expect(request.fields['user_id'], 'guest_test');
      expect(request.fields['pose_mode'], 'balanced');
      expect(request.fields['keep_audio'], 'true');
    } finally {
      service.close();
      await directory.delete(recursive: true);
    }
  });

  test('upload timeout returns a readable error', () async {
    final directory = await Directory.systemTemp.createTemp('gb_timeout_test_');
    final file = File('${directory.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes([1, 2, 3]);
    final service = ApiService(client: _NeverRespondingClient());

    try {
      await expectLater(
        service.uploadVideo(
          file.path,
          userId: 'guest_test',
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('上传超时'),
          ),
        ),
      );
    } finally {
      service.close();
      await directory.delete(recursive: true);
    }
  });

  test('report file availability accepts 2xx and rejects missing files',
      () async {
    final service = ApiService(client: _FileStatusClient());
    try {
      expect(await service.fileExists('/outputs/available.png'), isTrue);
      expect(await service.fileExists('/outputs/missing.png'), isFalse);
      expect(await service.fileExists(null), isFalse);
    } finally {
      service.close();
    }
  });

  test('source upload id avoids uploading the video twice', () async {
    final client = _SuccessfulUploadClient();
    final service = ApiService(client: client);
    try {
      await service.uploadVideo(
        null,
        userId: 'guest_test',
        sourceUploadId: 'source-1',
      );
      final request = client.request! as http.MultipartRequest;
      expect(request.files, isEmpty);
      expect(request.fields['source_upload_id'], 'source-1');
      expect(request.fields['user_id'], 'guest_test');
    } finally {
      service.close();
    }
  });

  test('preview frame sends file and stable guest user id', () async {
    final directory = await Directory.systemTemp.createTemp('gb_preview_test_');
    final file = File('${directory.path}${Platform.pathSeparator}sample.mp4');
    await file.writeAsBytes(List<int>.filled(64, 1));
    final client = _PreviewClient();
    final service = ApiService(client: client);
    try {
      final preview = await service.previewVideo(
        file.path,
        userId: 'guest_stable',
      );
      final request = client.request! as http.MultipartRequest;
      expect(request.url.path, '/api/videos/preview-frame');
      expect(request.fields['user_id'], 'guest_stable');
      expect(request.files.single.field, 'file');
      expect(preview.sourceUploadId, 'source-1');
      expect(preview.autoCorners, hasLength(4));
    } finally {
      service.close();
      await directory.delete(recursive: true);
    }
  });

  test('structured backend error exposes code, message and hint', () async {
    final service = ApiService(client: _StructuredErrorClient());
    try {
      await expectLater(
        service.checkHealth(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'VIDEO_TOO_LONG')
              .having((error) => error.message, 'message', '视频太长')
              .having((error) => error.hint, 'hint', '请先裁剪'),
        ),
      );
    } finally {
      service.close();
    }
  });
}

class _SuccessfulUploadClient extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    await request.finalize().toBytes();
    final body = jsonEncode({
      'task_id': 'test-task-id',
      'status': 'queued',
      'status_url': '/api/tasks/test-task-id',
      'report_url': '/api/tasks/test-task-id/report',
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _NeverRespondingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

class _FileStatusClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final status = request.url.path.endsWith('available.png') ? 200 : 404;
    return http.StreamedResponse(const Stream.empty(), status);
  }
}

class _StructuredErrorClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'detail': {
        'code': 'VIDEO_TOO_LONG',
        'message': '视频太长',
        'hint': '请先裁剪',
      },
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 400);
  }
}

class _PreviewClient extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    await request.finalize().toBytes();
    final body = jsonEncode({
      'source_upload_id': 'source-1',
      'image_url': '/preview-frames/source-1.jpg',
      'frame_index': 12,
      'time_sec': 0.4,
      'selection_reason': 'auto_court_detected',
      'quality': {'brightness': 90},
      'auto_corners': [
        [10, 10],
        [90, 10],
        [90, 90],
        [10, 90],
      ],
      'video': {
        'width': 100,
        'height': 100,
        'duration_sec': 30,
        'fps': 30,
        'total_frames': 900,
      },
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}
