import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/currency_formatter.dart';

void main() {
  test('keeps a negative amount left-to-right for RTL display', () {
    expect(CurrencyFormatter.ils(-4937.91), '\u2066-4,937.91\u2069');
  });

  test('keeps the export formatter free of bidi control characters', () {
    expect(CurrencyFormatter.formatAmount(-4937.91), '-4,937.91');
  });

  test('omits an empty decimal fraction', () {
    expect(CurrencyFormatter.ils(1500), '\u20661,500\u2069');
  });
}
