import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _productionApiUrl = 'https://shwakil.alkmal.com/api';
  static const String _localDebugApiUrl = 'https://wa.alkmal.com/api';
  static const String _trustedClientKey = String.fromEnvironment(
    'API_CLIENT_KEY',
  );

  static String get baseUrl {
    const env = String.fromEnvironment('API_BASE_URL');
    if (env.isNotEmpty) {
      return env;
    }
    if (kDebugMode) {
      return _localDebugApiUrl;
    }
    if (kIsWeb) {
      return '${Uri.base.origin}/api';
    }
    return _productionApiUrl;
  }

  static Uri get baseUri => Uri.parse(baseUrl);
  static String get trustedClientKey => _trustedClientKey.trim();
  static bool get hasTrustedClientKey => trustedClientKey.isNotEmpty;

  static Uri apiUri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(
      path: '$basePath$normalizedPath',
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }
}
