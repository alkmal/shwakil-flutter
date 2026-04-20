import 'dart:convert';

class ErrorMessageService {
  ErrorMessageService._();

  static String sanitize(Object? error) {
    final text = (error?.toString() ?? '').trim();
    if (text.isEmpty) {
      return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
    }

    final lower = text.toLowerCase();
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('not authorized') ||
        lower.contains('not permitted') ||
        lower.contains('غير مصرح') ||
        lower.contains('غير مخول')) {
      return 'يرجى تسجيل الدخول بحساب يملك الصلاحية المطلوبة للمتابعة.';
    }

    if (lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('err_connection_timed_out')) {
      return 'تعذر الاتصال بالخادم في الوقت الحالي. تحقق من الإنترنت أو أعد المحاولة بعد قليل.';
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
      return 'تعذر الاتصال بالخادم. تحقق من الإنترنت أو من توفر الخدمة ثم أعد المحاولة.';
    }

    if (lower.contains('websocket') || lower.contains('socket.io')) {
      return 'تعذر الاتصال الفوري بالخادم حالياً. يمكنك المتابعة وإعادة المحاولة بعد قليل.';
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
      return 'تأكد من جميع البيانات وحاول مرة أخرى. Please verify all entered data and try again.';
    }

    if (cleaned.toLowerCase().contains('typeerror') ||
        cleaned.toLowerCase().contains('stack') ||
        cleaned.toLowerCase().contains('payload')) {
      return 'حدث خطأ أثناء تنفيذ الطلب. حاول مرة أخرى أو تواصل مع الدعم إذا استمرت المشكلة.';
    }

    return cleaned;
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
}
