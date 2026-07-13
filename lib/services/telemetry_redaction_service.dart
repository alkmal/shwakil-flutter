class TelemetryRedactionService {
  TelemetryRedactionService._();

  static final RegExp _sensitiveAssignment = RegExp(
    r'''["']?(password|passwd|otp|otpcode|pin|securitypin|token|authorization|secret|nationalid|cardnumber|barcode)["']?\s*[:=]\s*["']?[^"'\s,;&}]+["']?''',
    caseSensitive: false,
  );
  static final RegExp _bearerToken = RegExp(
    r'\bbearer\s+[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _phoneOrLongNumber = RegExp(
    r'(?<!\d)\+?\d[\d\s().-]{7,}\d(?!\d)',
  );

  static String scrub(Object? value, {int maxLength = 500}) {
    var text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return '';
    }

    text = text
        .replaceAll(_bearerToken, 'Bearer [REDACTED]')
        .replaceAllMapped(
          _sensitiveAssignment,
          (match) => '${match.group(1)}=[REDACTED]',
        )
        .replaceAll(_email, '[REDACTED_EMAIL]')
        .replaceAll(_phoneOrLongNumber, '[REDACTED_NUMBER]');

    return text.length > maxLength
        ? '${text.substring(0, maxLength)}...'
        : text;
  }
}
