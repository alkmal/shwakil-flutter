import 'package:flutter/painting.dart';

/// Stable denomination colours. Monetary values are keyed by cents, not rounded
/// whole values or a repeating four-colour cycle.
abstract final class CardDenominationColor {
  static const known = <int, int>{
    25: 0xFF4D7C0F,
    50: 0xFF166534,
    100: 0xFF087F6D,
    200: 0xFF1D4ED8,
    300: 0xFFB45309,
    400: 0xFFBE123C,
    500: 0xFF7E22CE,
    1000: 0xFFC2410C,
    2000: 0xFF0E7490,
    2500: 0xFF4338CA,
    5000: 0xFF3F6212,
    10000: 0xFFA21CAF,
    20000: 0xFF854D0E,
    50000: 0xFF334155,
  };

  static Color forValue(num value) {
    final cents = (value * 100).round();
    final fixed = known[cents];
    if (fixed != null) return Color(fixed);
    return HSLColor.fromAHSL(
      1,
      (cents * 137.50776405) % 360,
      0.62,
      0.36,
    ).toColor();
  }
}
