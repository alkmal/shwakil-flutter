import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/services/error_message_service.dart';

void main() {
  test(
    'business messages containing token do not trigger a login redirect',
    () {
      const message = 'Card token is already linked to this payment.';

      expect(ErrorMessageService.sanitize(message), message);
      expect(ErrorMessageService.requiresFreshLogin(message), isFalse);
    },
  );

  test('authentication token expiry still requires session recovery', () {
    expect(
      ErrorMessageService.requiresFreshLogin('JWT access token expired'),
      isTrue,
    );
    expect(ErrorMessageService.requiresFreshLogin('HTTP 401'), isTrue);
  });

  test('device session refresh messages require session recovery', () {
    expect(
      ErrorMessageService.requiresFreshLogin('يلزم تجديد جلسة الجهاز الموثق.'),
      isTrue,
    );
  });
}
