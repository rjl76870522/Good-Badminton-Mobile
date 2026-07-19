class ApiConfig {
  ApiConfig._();

  static const String _defaultBaseUrl = 'https://api.audacity6441.kdns.fr';
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  static String get baseUrl => _configuredBaseUrl.endsWith('/')
      ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
      : _configuredBaseUrl;

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
