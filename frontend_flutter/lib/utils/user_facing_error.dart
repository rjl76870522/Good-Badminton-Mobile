import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../services/api_service.dart';

/// Converts transport and unexpected errors into short, user-facing Chinese text.
/// Raw exception details should stay out of normal app screens.
String userFacingError(
  Object error, {
  String fallback = '操作暂时无法完成，请稍后重试。',
}) {
  if (error is ApiException && _containsChinese(error.message)) {
    return error.message;
  }
  if (error is TimeoutException) {
    return '请求超时，请检查网络后重试。';
  }
  if (error is SocketException || error is http.ClientException) {
    return '暂时无法连接分析服务器，请确认服务已启动后重试。';
  }
  return fallback;
}

bool _containsChinese(String value) =>
    RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
