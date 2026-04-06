import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _productionApiUrl = 'https://wa.alkmal.com/api';
  static const String _localDebugApiUrl = 'https://shwakil.test/api';
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
