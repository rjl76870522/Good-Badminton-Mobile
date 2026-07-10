class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'http://localhost:8001';

  static Uri uri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalizedPath');
    if (queryParameters == null) {
      return uri;
    }
    return uri.replace(
      queryParameters: queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  static String? absoluteFileUrl(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) {
      return path;
    }
    return '$baseUrl${path.startsWith('/') ? path : '/$path'}';
  }
}
