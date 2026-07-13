import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static const String _leftToRightIsolate = '\u2066';
  static const String _popDirectionalIsolate = '\u2069';

  /// A display-safe amount that keeps the sign on the left in RTL layouts.
  ///
  /// Use [formatAmount] when a plain value is needed for exports or parsing.
  static String ils(num? amount, {int decimals = 2}) {
    final value = formatAmount(amount, decimals: decimals);
    return '$_leftToRightIsolate$value$_popDirectionalIsolate';
  }

  static String formatAmount(num? amount, {int decimals = 2}) {
    final value = (amount ?? 0).toDouble();
    final safeDecimals = decimals < 0 ? 0 : decimals;
    final formatter = NumberFormat.decimalPatternDigits(
      locale: 'en',
      decimalDigits: _shouldShowDecimals(value, safeDecimals)
          ? safeDecimals
          : 0,
    );
    return formatter.format(value);
  }

  static bool _shouldShowDecimals(double value, int decimals) {
    if (decimals <= 0) {
      return false;
    }

    final rounded = value.toStringAsFixed(decimals);
    return !rounded.endsWith('.${'0' * decimals}');
  }
}
