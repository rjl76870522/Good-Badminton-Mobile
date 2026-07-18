import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/history_item.dart';
import '../models/mobile_user.dart';
import '../models/preview_frame.dart';
import '../models/report.dart';
import '../models/task_status.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration defaultUploadTimeout = Duration(minutes: 5);

  final http.Client _client;

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _client
        .get(ApiConfig.uri('/api/health'))
        .timeout(const Duration(seconds: 15));
    return _decodeMap(response);
  }

  Future<MobileUser> registerUser(String userId) async {
    final response = await _client
        .post(
          ApiConfig.uri('/api/users/register'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(const Duration(seconds: 20));
    final payload = _decodeMap(response);
    return MobileUser.fromJson(_nestedMap(payload, 'user'));
  }

  Future<MobileUser> getUser(String userId) async {
    final response = await _client
        .get(ApiConfig.uri('/api/users/$userId'))
        .timeout(const Duration(seconds: 20));
    final payload = _decodeMap(response);
    return MobileUser.fromJson(_nestedMap(payload, 'user'));
  }

  Future<MobileUser> updateDisplayName(
    String userId,
    String displayName,
  ) async {
    final response = await _client
        .put(
          ApiConfig.uri('/api/users/$userId/display-name'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'display_name': displayName}),
        )
        .timeout(const Duration(seconds: 20));
    final payload = _decodeMap(response);
    return MobileUser.fromJson(_nestedMap(payload, 'user'));
  }

  Future<PreviewFrame> previewVideo(
    XFile file, {
    required String userId,
    void Function(double progress)? onProgress,
    Duration timeout = defaultUploadTimeout,
  }) async {
    onProgress?.call(0);
    http.MultipartFile multipartFile;
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      );
    } else {
      if (!await File(file.path).exists()) {
        throw const ApiException('选择的视频文件不存在');
      }
      multipartFile = await http.MultipartFile.fromPath('file', file.path);
    }
    final request = _ProgressMultipartRequest(
      'POST',
      ApiConfig.uri('/api/videos/preview-frame'),
      onProgress: (sentBytes, totalBytes) {
        if (totalBytes > 0) {
          onProgress?.call(((sentBytes / totalBytes) * 0.92).clamp(0, 0.92));
        }
      },
    )
      ..fields['user_id'] = userId
      ..files.add(multipartFile);
    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(timeout);
      onProgress?.call(0.96);
      final result = PreviewFrame.fromJson(_decodeMap(response));
      onProgress?.call(1);
      return result;
    } on TimeoutException {
      throw const ApiException('提取预览帧超时，请检查网络后重试', isTransient: true);
    } on SocketException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    } on http.ClientException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    } on FormatException catch (error) {
      throw ApiException(error.message);
    }
  }

  Future<UploadResult> uploadVideo(
    XFile? file, {
    required String userId,
    String? sourceUploadId,
    List<CourtPoint>? corners,
    String language = 'zh',
    String poseMode = 'balanced',
    bool keepAudio = true,
    void Function(double progress)? onProgress,
    Duration timeout = defaultUploadTimeout,
  }) async {
    final hasSource =
        sourceUploadId != null && sourceUploadId.trim().isNotEmpty;
    if (!hasSource && file == null) {
      throw const ApiException('请提供视频文件或预览上传 ID');
    }
    if (!hasSource && !kIsWeb && !await File(file!.path).exists()) {
      throw const ApiException('选择的视频文件不存在');
    }

    onProgress?.call(0);
    final request = _ProgressMultipartRequest(
      'POST',
      ApiConfig.uri('/api/videos/upload'),
      onProgress: (sentBytes, totalBytes) {
        if (totalBytes <= 0) return;
        onProgress?.call((sentBytes / totalBytes).clamp(0.0, 1.0));
      },
    )
      ..fields['user_id'] = userId
      ..fields['language'] = language
      ..fields['pose_mode'] = poseMode
      ..fields['keep_audio'] = keepAudio.toString();
    if (hasSource) {
      request.fields['source_upload_id'] = sourceUploadId.trim();
    } else {
      http.MultipartFile multipartFile;
      if (kIsWeb) {
        final bytes = await file!.readAsBytes();
        multipartFile = http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        );
      } else {
        multipartFile = await http.MultipartFile.fromPath('file', file!.path);
      }
      request.files.add(multipartFile);
    }
    if (corners != null && corners.length == 4) {
      request.fields['corners_json'] =
          jsonEncode(corners.map((point) => point.toJson()).toList());
    }

    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(timeout);
      final json = _decodeMap(response);
      onProgress?.call(1);
      return UploadResult.fromJson(json);
    } on TimeoutException {
      throw const ApiException('上传超时，请检查手机网络和后端是否仍在运行');
    } on SocketException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    } on http.ClientException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    }
  }

  Future<TaskStatus> getTask(String taskId) async {
    try {
      final response = await _client
          .get(ApiConfig.uri('/api/tasks/$taskId'))
          .timeout(const Duration(seconds: 20));
      return TaskStatus.fromJson(_decodeMap(response));
    } on TimeoutException {
      throw const ApiException('网络连接短暂中断，正在自动重试。', isTransient: true);
    } on SocketException {
      throw const ApiException('网络连接短暂中断，正在自动重试。', isTransient: true);
    } on http.ClientException {
      throw const ApiException('网络连接短暂中断，正在自动重试。', isTransient: true);
    }
  }

  Future<AnalysisReport> getReport(String taskId) async {
    return AnalysisReport.fromJson(await getReportPayload(taskId));
  }

  Future<Map<String, dynamic>> getReportPayload(String taskId) async {
    try {
      final response = await _client
          .get(ApiConfig.uri('/api/tasks/$taskId/report'))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 202) {
        throw const ReportPendingException();
      }
      return _decodeMap(response);
    } on ReportPendingException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('读取报告超时，请稍后重试', isTransient: true);
    } on SocketException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    } on http.ClientException {
      throw const ApiException('网络连接短暂中断，请稍后重试', isTransient: true);
    }
  }

  Future<AnalysisReport> getDemoReport() async {
    final response = await _client
        .get(ApiConfig.uri('/api/demo/sample'))
        .timeout(const Duration(seconds: 20));
    final payload = _decodeMap(response);
    final report = payload['report'];
    if (report is! Map) {
      throw const ApiException('Demo 接口未返回 report 数据');
    }
    return AnalysisReport.fromJson(
      report.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<List<HistoryItem>> getHistory({
    required String userId,
    int limit = 30,
    String? status,
  }) async {
    final query = <String, dynamic>{'user_id': userId, 'limit': limit};
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }
    final response = await _client
        .get(ApiConfig.uri('/api/history', query))
        .timeout(const Duration(seconds: 20));
    final payload = _decodeMap(response);
    final items = payload['items'];
    if (items is! List) {
      throw const ApiException('历史接口未返回 items 列表');
    }
    return items
        .whereType<Map>()
        .map(
          (item) => HistoryItem.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<void> deleteTask(String taskId, {required String userId}) async {
    final response = await _client
        .delete(
          ApiConfig.uri('/api/tasks/$taskId', {'user_id': userId}),
        )
        .timeout(const Duration(seconds: 20));
    _decodeMap(response);
  }

  Future<String> downloadFile(String url, String localPath) async {
    final response =
        await _client.get(Uri.parse(url)).timeout(const Duration(minutes: 10));
    if (response.statusCode != 200) {
      throw ApiException('下载失败：HTTP ${response.statusCode}');
    }
    final file = File(localPath);
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  Future<bool> fileExists(String? relativePath) async {
    final url = ApiConfig.absoluteFileUrl(relativePath);
    if (url == null) return false;
    try {
      final response = await _client
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void close() {
    _client.close();
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        '后端返回了无法解析的数据',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      String? code;
      String? hint;
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is Map) {
          code = detail['code']?.toString();
          message = detail['message']?.toString();
          hint = detail['hint']?.toString();
        } else {
          message = detail?.toString();
        }
      }
      throw ApiException(
        message ?? '请求失败',
        statusCode: response.statusCode,
        code: code,
        hint: hint,
      );
    }
    if (decoded is! Map) {
      throw ApiException(
        '后端返回格式不正确',
        statusCode: response.statusCode,
      );
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Map<String, dynamic> _nestedMap(
    Map<String, dynamic> payload,
    String key,
  ) {
    final value = payload[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ApiException('后端响应缺少 $key 数据');
  }
}

class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(
    super.method,
    super.url, {
    required this.onProgress,
  });

  final void Function(int sentBytes, int totalBytes) onProgress;

  @override
  http.ByteStream finalize() {
    final totalBytes = contentLength;
    var sentBytes = 0;
    final stream = super.finalize().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          sentBytes += data.length;
          onProgress(sentBytes, totalBytes);
          sink.add(data);
        },
      ),
    );
    return http.ByteStream(stream);
  }
}

class UploadResult {
  const UploadResult({
    required this.taskId,
    required this.status,
    required this.statusUrl,
    required this.reportUrl,
  });

  final String taskId;
  final String status;
  final String statusUrl;
  final String reportUrl;

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    final taskId = json['task_id']?.toString() ?? '';
    if (taskId.isEmpty) {
      throw const ApiException('上传响应缺少 task_id');
    }
    return UploadResult(
      taskId: taskId,
      status: json['status']?.toString() ?? '',
      statusUrl: json['status_url']?.toString() ?? '',
      reportUrl: json['report_url']?.toString() ?? '',
    );
  }
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.hint,
    this.isTransient = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final String? hint;
  final bool isTransient;

  @override
  String toString() {
    final prefix = statusCode == null ? '' : 'HTTP $statusCode：';
    final suffix = hint == null || hint!.isEmpty ? '' : '\n$hint';
    return '$prefix$message$suffix';
  }
}

class ReportPendingException extends ApiException {
  const ReportPendingException() : super('报告还未生成完成', statusCode: 202);
}
