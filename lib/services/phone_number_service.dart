class CountryOption {
  final String name;
  final String dialCode;
  final String flag;
  const CountryOption({
    required this.name,
    required this.dialCode,
    required this.flag,
  });
}

class PhoneNumberService {
  static const List<CountryOption> countries = [
    CountryOption(name: 'فلسطين', dialCode: '970', flag: 'PS'),
    CountryOption(name: 'إسرائيل', dialCode: '972', flag: 'IL'),
  ];
  static String normalize({
    required String input,
    required String defaultDialCode,
  }) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith(defaultDialCode)) {
      return digits;
    }
    if (digits.startsWith('0')) {
      return '$defaultDialCode${digits.substring(1)}';
    }
    return '$defaultDialCode$digits';
  }

  static String localDisplay(String? input) {
    var digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    for (final country in countries) {
      final dialCode = country.dialCode;
      if (digits.startsWith(dialCode) &&
          digits.length > dialCode.length &&
          digits.substring(dialCode.length).startsWith('5')) {
        return '0${digits.substring(dialCode.length)}';
      }
    }
    if (digits.startsWith('5') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }
}
