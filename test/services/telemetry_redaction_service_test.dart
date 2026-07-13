import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/services/telemetry_redaction_service.dart';

void main() {
  test('scrubs secrets from structured and plain telemetry text', () {
    final scrubbed = TelemetryRedactionService.scrub(
      'token=abc123 Bearer jwt.value password: hidden otpCode=123456',
    );

    expect(scrubbed, isNot(contains('abc123')));
    expect(scrubbed, isNot(contains('jwt.value')));
    expect(scrubbed, isNot(contains('hidden')));
    expect(scrubbed, isNot(contains('123456')));
    expect(scrubbed, contains('[REDACTED]'));
  });

  test('scrubs email, phone, barcode, and JSON secret values', () {
    final scrubbed = TelemetryRedactionService.scrub(
      '{"token":"secret-value","barcode":"1234567890123456"} '
      'private@example.com +970 59 999 9999',
    );

    expect(scrubbed, isNot(contains('secret-value')));
    expect(scrubbed, isNot(contains('1234567890123456')));
    expect(scrubbed, isNot(contains('private@example.com')));
    expect(scrubbed, isNot(contains('970 59 999 9999')));
  });

  test('keeps useful operational text and limits its length', () {
    final scrubbed = TelemetryRedactionService.scrub(
      'StateError in CreateCardScreen ${List.filled(600, 'x').join()}',
      maxLength: 120,
    );

    expect(scrubbed, startsWith('StateError in CreateCardScreen'));
    expect(scrubbed.length, 123);
    expect(scrubbed, endsWith('...'));
  });
}
