import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/card_number_extractor.dart';

void main() {
  test('extracts a 16 digit card number from a message', () {
    expect(
      CardNumberExtractor.extractFirst(
        'رقم بطاقتك هو 1234 5678-9012 3456 ويمكن استخدامه الآن',
      ),
      '1234567890123456',
    );
  });

  test('normalizes Arabic digits', () {
    expect(
      CardNumberExtractor.extractFirst('رقم البطاقة: ١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦'),
      '1234567890123456',
    );
  });

  test('does not accept numbers that are not exactly 16 digits', () {
    expect(CardNumberExtractor.extractFirst('الهاتف 0599883621'), isNull);
  });

  test('does not merge a card number with a phone on the following line', () {
    expect(
      CardNumberExtractor.extractFirst(
        'رقم البطاقة: 1234 5678 9012 3456\nالهاتف: 0599883621',
      ),
      '1234567890123456',
    );
  });
}
