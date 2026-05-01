import 'dart:convert';

import '../localization/app_localization.dart';
import '../localization/app_strings_ar.dart';
import '../localization/app_strings_en.dart';

class ErrorMessageService {
  ErrorMessageService._();

  static String sanitize(Object? error) {
    final text = (error?.toString() ?? '').trim();
    if (text.isEmpty) {
      return _tr('services_error_message_service.001');
    }

    final lower = text.toLowerCase();
    if (lower.contains('هذا الجهاز غير معتمد') ||
        lower.contains('device is not approved') ||
        lower.contains('device not approved')) {
      return _tr('services_error_message_service.010');
    }

    if (lower.contains('غير مصرح.') ||
        lower == 'غير مصرح' ||
        lower.contains('session version') ||
        lower.contains('bearer ') ||
        lower.contains('jwt') ||
        lower.contains('token')) {
      return _tr('services_error_message_service.011');
    }

    if (lower.contains('401') ||
        lower.contains('unauthorized') ||
        lower.contains(
          _tr('services_error_message_service.008').toLowerCase(),
        )) {
      return _tr('services_error_message_service.011');
    }

    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('not authorized') ||
        lower.contains('not permitted') ||
        lower.contains(
          _tr('services_error_message_service.009').toLowerCase(),
        )) {
      return _tr('services_error_message_service.002');
    }

    if (lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('err_connection_timed_out')) {
      return _tr('services_error_message_service.003');
    }

    if (lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('clientexception') ||
        lower.contains('xmlhttprequest error') ||
        lower.contains('net::err_') ||
        lower.contains('socketexception') ||
        lower.contains('failed to fetch')) {
      return _tr('services_error_message_service.004');
    }

    if (lower.contains('websocket') || lower.contains('socket.io')) {
      return _tr('services_error_message_service.005');
    }

    if (lower.contains('badpaddingexception') ||
        lower.contains('bad_decrypt') ||
        lower.contains('failed to unwrap key') ||
        (lower.contains('platformexception') && lower.contains('read'))) {
      return _tr('services_error_message_service.013');
    }

    final withoutUrls = text.replaceAll(RegExp(r'https?://\S+'), '').trim();
    final cleaned = withoutUrls
        .replaceFirst(
          RegExp(r'^(?:[A-Za-z_]+\s*)?Exception:\s*', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^exception:\s*', caseSensitive: false), '')
        .trim();

    if (cleaned.isEmpty ||
        cleaned.startsWith('<!DOCTYPE html') ||
        cleaned.startsWith('<html')) {
      return _tr('services_error_message_service.006');
    }

    if (cleaned.toLowerCase().contains('typeerror') ||
        cleaned.toLowerCase().contains('stack') ||
        cleaned.toLowerCase().contains('payload')) {
      return _tr('services_error_message_service.007');
    }

    return cleaned;
  }

  static String forUser(Object? error, {bool includeSupportGuidance = false}) {
    final clean = _normalizeMixedDirection(sanitize(error));
    if (!includeSupportGuidance || !_shouldAppendSupportGuidance(clean)) {
      return clean;
    }
    final guidance = _normalizeMixedDirection(
      _tr('services_error_message_service.014'),
    );
    return '$clean\n$guidance';
  }

  static String sanitizeRegistration(Object? error) {
    final text = (error?.toString() ?? '').trim();
    if (text.isEmpty) {
      return _tr('services_error_message_service.012');
    }

    return sanitize(text);
  }

  static bool requiresFreshLogin(Object? error) {
    final clean = sanitize(error);
    final lower = (error?.toString() ?? clean).toLowerCase();
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('not authorized') ||
        lower.contains('not permitted') ||
        lower.contains('session version') ||
        lower.contains('bearer ') ||
        lower.contains('jwt') ||
        lower.contains('token')) {
      return true;
    }

    return _matchesAnyMessage(clean, [
      'services_error_message_service.002',
      'services_error_message_service.010',
      'services_error_message_service.011',
    ]);
  }

  static String fromResponseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return sanitize(message);
        }
      }
    } catch (_) {}

    return sanitize(body);
  }

  static bool _shouldAppendSupportGuidance(String message) {
    final clean = message.trim();
    if (clean.isEmpty ||
        clean.contains(_tr('services_error_message_service.014')) ||
        clean.contains(
          appStringsAr['services_error_message_service.014'] ?? '',
        ) ||
        clean.contains(
          appStringsEn['services_error_message_service.014'] ?? '',
        )) {
      return false;
    }

    return true;
  }

  static String _normalizeMixedDirection(String text) {
    final locale = AppLocaleService.instance.locale;
    if ((locale?.languageCode ?? 'ar') != 'ar') {
      return text;
    }

    const isolateStart = '\u2068';
    const isolateEnd = '\u2069';
    return text.replaceAllMapped(
      RegExp(r'([A-Za-z][A-Za-z0-9._@:/+\-]*|\d+(?:[.,]\d+)*)'),
      (match) => '$isolateStart${match.group(0)}$isolateEnd',
    );
  }

  static String fromRegistrationResponseBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return sanitizeRegistration(message);
        }
      }
    } catch (_) {}

    return sanitizeRegistration(body);
  }

  static String _tr(String key) {
    final current = AppLocaleService.instance.locale;
    if ((current?.languageCode ?? 'ar') == 'en') {
      return appStringsEn[key] ?? key;
    }
    return appStringsAr[key] ?? appStringsEn[key] ?? key;
  }

  static bool _matchesAnyMessage(String message, List<String> keys) {
    for (final key in keys) {
      final current = _tr(key);
      final arabic = appStringsAr[key];
      final english = appStringsEn[key];
      for (final candidate in [current, arabic, english]) {
        if (candidate != null &&
            candidate.isNotEmpty &&
            message.contains(candidate)) {
          return true;
        }
      }
    }
    return false;
  }
}
