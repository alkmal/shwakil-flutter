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
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('not authorized') ||
        lower.contains('not permitted') ||
        lower.contains(_tr('services_error_message_service.008').toLowerCase()) ||
        lower.contains(_tr('services_error_message_service.009').toLowerCase())) {
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

  static String sanitizeRegistration(Object? error) {
    final text = (error?.toString() ?? '').trim();
    if (text.isEmpty) {
      return _tr('services_error_message_service.012');
    }

    final lower = text.toLowerCase();
    if (lower.contains('registration is currently disabled') ||
        lower.contains('registration disabled') ||
        lower.contains('could not start registration') ||
        lower.contains('required permission to continue') ||
        lower.contains('please sign in with an account that has the required permission') ||
        lower.contains('trusted client key') ||
        lower.contains('client key') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('تعذر إرسال الرسالة عبر واتساب') ||
        lower.contains('whatsapp') ||
        lower.contains('واتساب') ||
        lower.contains('التسجيل متوقف حاليا') ||
        lower.contains('التسجيل الجديد متوقف') ||
        lower.contains('التسجيل متوقف') ||
        lower.contains('الصلاحية المطلوبة') ||
        lower.contains('الطلب العام غير موثق')) {
      return _tr('services_error_message_service.012');
    }

    return sanitize(text);
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
}
