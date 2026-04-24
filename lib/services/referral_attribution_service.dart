import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReferralAttributionService {
  ReferralAttributionService._();

  static const MethodChannel _channel = MethodChannel(
    'com.alkmal.shwakil/referrals',
  );
  static const String _pendingReferralKey = 'pending_referral_code';
  static const String _pendingReferralSourceKey = 'pending_referral_source';
  static const String _installReferrerHandledKey =
      'pending_referral_install_referrer_handled_v1';

  static Future<void> initialize() async {
    if (kIsWeb) {
      await _storeReferralFromCurrentWebUrl(source: 'web_query');
      return;
    }

    try {
      final payload = Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'getInitialReferralPayload',
            ) ??
            const <String, dynamic>{},
      );

      final directCode = _normalizeReferralCode(
        payload['intentCode']?.toString() ?? payload['urlCode']?.toString(),
      );
      if (directCode != null) {
        await savePendingReferralCode(directCode, source: 'deep_link');
      }

      final installReferrerCode = _normalizeReferralCode(
        payload['installReferrerCode']?.toString(),
      );
      if (installReferrerCode == null) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final alreadyHandled = prefs.getBool(_installReferrerHandledKey) ?? false;
      if (!alreadyHandled) {
        await savePendingReferralCode(
          installReferrerCode,
          source: 'android_install_referrer',
        );
        await prefs.setBool(_installReferrerHandledKey, true);
      }
    } on MissingPluginException {
      // Referral attribution is optional outside supported mobile platforms.
    } catch (_) {
      // Startup should remain resilient if referral attribution fails.
    }
  }

  static Future<void> savePendingReferralCode(
    String code, {
    String source = 'manual',
  }) async {
    final normalizedCode = _normalizeReferralCode(code);
    if (normalizedCode == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralKey, normalizedCode);
    await prefs.setString(_pendingReferralSourceKey, source);
  }

  static Future<String?> getPendingReferralCode() async {
    if (kIsWeb) {
      await _storeReferralFromCurrentWebUrl(source: 'web_query');
    }

    final prefs = await SharedPreferences.getInstance();
    return _normalizeReferralCode(prefs.getString(_pendingReferralKey));
  }

  static Future<String?> getPendingReferralSource() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_pendingReferralSourceKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> clearPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingReferralKey);
    await prefs.remove(_pendingReferralSourceKey);
  }

  static Future<void> _storeReferralFromQuery(
    Uri uri, {
    required String source,
  }) async {
    final code = _extractReferralCode(uri);
    if (code == null) {
      return;
    }

    await savePendingReferralCode(code, source: source);
  }

  static Future<void> _storeReferralFromCurrentWebUrl({
    required String source,
  }) async {
    await _storeReferralFromQuery(Uri.base, source: source);
  }

  static String? _extractReferralCode(Uri uri) {
    final directCode = _normalizeReferralCode(
      uri.queryParameters['ref'] ??
          uri.queryParameters['referral'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['referralPhone'],
    );
    if (directCode != null) {
      return directCode;
    }

    final fragment = uri.fragment.trim();
    if (fragment.isEmpty || !fragment.contains('?')) {
      return null;
    }

    final fragmentQuery = fragment.substring(fragment.indexOf('?') + 1);
    final fragmentUri = Uri.tryParse('https://local.invalid/?$fragmentQuery');
    if (fragmentUri == null) {
      return null;
    }

    return _normalizeReferralCode(
      fragmentUri.queryParameters['ref'] ??
          fragmentUri.queryParameters['referral'] ??
          fragmentUri.queryParameters['code'] ??
          fragmentUri.queryParameters['referralPhone'],
    );
  }

  static String? _normalizeReferralCode(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty || normalized.length > 64) {
      return null;
    }

    if (RegExp(r'[\s/?#&]').hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }
}
