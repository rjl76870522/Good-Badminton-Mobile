import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
        XFile(file.path),
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
          XFile(file.path),
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
    final client = _FileStatusClient();
    final service = ApiService(client: client);
    try {
      expect(await service.fileExists('/outputs/available.png'), isTrue);
      expect(await service.fileExists('/outputs/missing.png'), isFalse);
      expect(await service.fileExists(null), isFalse);
      expect(client.requests, hasLength(2));
      expect(client.requests.first.method, 'GET');
      expect(client.requests.first.headers['range'], 'bytes=0-0');
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
        XFile(file.path),
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

  test('user registration and lookup parse nested user payload', () async {
    final service = ApiService(client: _UserClient());
    try {
      final registered = await service.registerUser('guest_test');
      final loaded = await service.getUser('guest_test');
      expect(registered.userId, 'guest_test');
      expect(loaded.createdAt, 123);
    } finally {
      service.close();
    }
  });

  test('delete task includes stable user id', () async {
    final client = _DeleteTaskClient();
    final service = ApiService(client: client);
    try {
      await service.deleteTask('task-1', userId: 'guest_test');
      expect(client.request?.method, 'DELETE');
      expect(client.request?.url.queryParameters['user_id'], 'guest_test');
    } finally {
      service.close();
    }
  });

  test('download replaces the target only after a complete response', () async {
    final directory =
        await Directory.systemTemp.createTemp('gb_download_test_');
    final target =
        File('${directory.path}${Platform.pathSeparator}analysis.mp4');
    await target.writeAsBytes([9, 9, 9]);
    final progress = <double>[];
    final service = ApiService(client: _DownloadClient());

    try {
      final savedPath = await service.downloadFile(
        'https://example.test/analysis.mp4',
        target.path,
        onProgress: progress.add,
      );

      expect(savedPath, target.path);
      expect(await target.readAsBytes(), [1, 2, 3, 4]);
      expect(await File('${target.path}.part').exists(), isFalse);
      expect(progress.last, 1);
    } finally {
      service.close();
      await directory.delete(recursive: true);
    }
  });

  test('interrupted download removes the partial file and keeps old target',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gb_download_failure_test_');
    final target =
        File('${directory.path}${Platform.pathSeparator}analysis.mp4');
    await target.writeAsBytes([9, 9, 9]);
    final service = ApiService(client: _InterruptedDownloadClient());

    try {
      await expectLater(
        service.downloadFile(
          'https://example.test/analysis.mp4',
          target.path,
        ),
        throwsA(isA<SocketException>()),
      );
      expect(await target.readAsBytes(), [9, 9, 9]);
      expect(await File('${target.path}.part').exists(), isFalse);
    } finally {
      service.close();
      await directory.delete(recursive: true);
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
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
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

class _UserClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'user': {
        'user_id': 'guest_test',
        'created_at': 123,
        'updated_at': 124,
      },
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

class _DeleteTaskClient extends http.BaseClient {
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request;
    final body = jsonEncode({
      'ok': true,
      'task_id': 'task-1',
      'deleted_paths': [],
    });
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

class _DownloadClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
      200,
      contentLength: 4,
    );
  }
}

class _InterruptedDownloadClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.multi((controller) {
      controller.add([1, 2]);
      controller.addError(const SocketException('连接中断'));
      controller.close();
    });
    return http.StreamedResponse(stream, 200, contentLength: 4);
  }
}
