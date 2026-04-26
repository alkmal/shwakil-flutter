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
    return _productionApiUrl;
  }

  static List<String> get apiBaseUrls {
    const env = String.fromEnvironment('API_BASE_URL');
    if (env.isNotEmpty) {
      return [env];
    }

    return {
      _productionApiUrl,
      _localDebugApiUrl,
    }.toList();
  }

  static Uri get baseUri => Uri.parse(baseUrl);
  static String get trustedClientKey => _trustedClientKey.trim();
  static bool get hasTrustedClientKey => trustedClientKey.isNotEmpty;

  static Uri inviteUri(String referralCode) {
    final normalizedCode = referralCode.trim();
    const envInviteBaseUrl = String.fromEnvironment('INVITE_BASE_URL');

    if (envInviteBaseUrl.isNotEmpty) {
      final inviteBaseUri = Uri.parse(envInviteBaseUrl);
      final inviteBasePath = inviteBaseUri.path.endsWith('/')
          ? inviteBaseUri.path
          : '${inviteBaseUri.path}/';
      return inviteBaseUri.replace(
        path: '$inviteBasePath${Uri.encodeComponent(normalizedCode)}',
        queryParameters: null,
      );
    }

    return Uri.parse(
      '${baseUri.origin}/invite/${Uri.encodeComponent(normalizedCode)}',
    );
  }

  static Uri apiUri(String path, [Map<String, dynamic>? queryParameters]) {
    return apiCandidateUris(path, queryParameters).first;
  }

  static List<Uri> apiCandidateUris(
    String path, [
    Map<String, dynamic>? queryParameters,
  ]) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return apiBaseUrls.map((url) {
      final uri = Uri.parse(url);
      final basePath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
      return uri.replace(
        path: '$basePath$normalizedPath',
        queryParameters: queryParameters?.map(
          (key, value) => MapEntry(key, value?.toString()),
        ),
      );
    }).toList(growable: false);
  }
}
