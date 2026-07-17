class ApiConfig {
  ApiConfig._();

  /// Public HTTPS endpoint for physical-device access.
  /// Keep this value without a trailing `/api`; services append endpoint paths.
  static const String baseUrl = 'https://api.audacity6441.kdns.fr';

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
