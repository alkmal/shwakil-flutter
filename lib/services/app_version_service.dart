import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_config.dart';
import 'network_client_service.dart';

class AppUpdateRequirement {
  const AppUpdateRequirement({
    required this.currentVersion,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.platformLabel,
    required this.isForced,
  });

  final String currentVersion;
  final String minSupportedVersion;
  final String latestVersion;
  final String storeUrl;
  final String platformLabel;
  final bool isForced;

  bool get hasStoreUrl => storeUrl.trim().isNotEmpty;
}

class AppVersionService {
  AppVersionService._();
  static const Duration _requestTimeout = Duration(seconds: 8);
  static final http.Client _client = NetworkClientService.client;

  static PackageInfo? _cachedInfo;

  static Future<PackageInfo> _packageInfo() async {
    _cachedInfo ??= await PackageInfo.fromPlatform();
    return _cachedInfo!;
  }

  static Future<String> currentVersion() async {
    return (await _packageInfo()).version.trim();
  }

  static Future<Map<String, String>> publicHeaders({
    bool includeJsonContentType = false,
  }) async {
    final info = await _packageInfo();
    return {
      'Accept': 'application/json',
      if (includeJsonContentType) 'Content-Type': 'application/json',
      'X-Requested-With': 'shwakil-flutter-client',
      'X-App-Version': info.version.trim(),
      'X-App-Build': info.buildNumber.trim(),
      'X-App-Platform': _platformLabel,
      if (AppConfig.hasTrustedClientKey)
        'X-Client-Key': AppConfig.trustedClientKey,
    };
  }

  static Future<AppUpdateRequirement?> fetchRequiredUpdate() async {
    final info = await _packageInfo();
    late final http.Response response;
    final stopwatch = Stopwatch()..start();
    try {
      response = await _client
          .get(
            AppConfig.apiUri('app/auth-settings'),
            headers: await publicHeaders(),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      return null;
    }
    if (response.statusCode >= 400) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final auth = Map<String, dynamic>.from(body['auth'] as Map? ?? const {});
    final minSupportedVersion =
        auth['minSupportedVersion']?.toString().trim() ?? '';
    final latestVersion =
        auth['latestVersion']?.toString().trim().isNotEmpty == true
        ? auth['latestVersion'].toString().trim()
        : minSupportedVersion;

    if (minSupportedVersion.isEmpty && latestVersion.isEmpty) {
      return null;
    }

    final currentVersion = info.version.trim();
    final forced =
        minSupportedVersion.isNotEmpty &&
        _compareVersions(currentVersion, minSupportedVersion) < 0;
    final newerAvailable =
        latestVersion.isNotEmpty &&
        _compareVersions(currentVersion, latestVersion) < 0;

    if (!forced && !newerAvailable) {
      assert(() {
        // ignore: avoid_print
        print(
          '[startup] GET app/auth-settings ${stopwatch.elapsed.inMilliseconds}ms',
        );
        return true;
      }());
      return null;
    }

    assert(() {
      // ignore: avoid_print
      print('[startup] GET app/auth-settings ${stopwatch.elapsed.inMilliseconds}ms');
      return true;
    }());
    return AppUpdateRequirement(
      currentVersion: currentVersion,
      minSupportedVersion: minSupportedVersion,
      latestVersion: latestVersion,
      storeUrl: _storeUrlForPlatform(auth),
      platformLabel: _platformLabel,
      isForced: forced,
    );
  }

  static String _storeUrlForPlatform(Map<String, dynamic> auth) {
    if (kIsWeb) {
      return auth['webStoreUrl']?.toString().trim() ?? '';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return auth['androidStoreUrl']?.toString().trim() ?? '';
      case TargetPlatform.iOS:
        return auth['iosStoreUrl']?.toString().trim() ?? '';
      default:
        return auth['webStoreUrl']?.toString().trim() ?? '';
    }
  }

  static String get _platformLabel {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static int _compareVersions(String left, String right) {
    final leftParts = _normalizeVersion(left);
    final rightParts = _normalizeVersion(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index++) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return 0;
  }

  static List<int> _normalizeVersion(String version) {
    return version
        .split(RegExp(r'[^0-9]+'))
        .where((segment) => segment.isNotEmpty)
        .map((segment) => int.tryParse(segment) ?? 0)
        .toList();
  }
}
