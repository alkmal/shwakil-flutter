class CurrencyFormatter {
  CurrencyFormatter._();

  static String ils(num? amount, {int decimals = 2}) {
    final value = (amount ?? 0).toDouble();
    return '₪${value.toStringAsFixed(decimals)}';
  }
}
