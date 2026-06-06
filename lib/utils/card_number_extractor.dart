class CardNumberExtractor {
  static const int cardNumberLength = 16;

  static String normalizeDigits(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final arabicIndex = arabicIndic.indexOf(character);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      final easternIndex = easternArabicIndic.indexOf(character);
      if (easternIndex >= 0) {
        buffer.write(easternIndex);
        continue;
      }
      buffer.write(character);
    }

    return buffer.toString();
  }

  static List<String> extractCandidates(String value) {
    final normalized = normalizeDigits(value);
    final candidates = <String>{};
    final digits = StringBuffer();

    void commit() {
      final candidate = digits.toString();
      if (candidate.length == cardNumberLength) {
        candidates.add(candidate);
      }
      digits.clear();
    }

    for (final rune in normalized.runes) {
      final character = String.fromCharCode(rune);
      if (RegExp(r'[0-9]').hasMatch(character)) {
        digits.write(character);
      } else if (digits.isNotEmpty &&
          RegExp(r'[ \t\-–—]').hasMatch(character)) {
        continue;
      } else {
        commit();
      }
    }
    commit();

    return candidates.toList(growable: false);
  }

  static String? extractFirst(String value) {
    final candidates = extractCandidates(value);
    return candidates.isEmpty ? null : candidates.first;
  }
}
