class CountryOption {
  final String name;
  final String dialCode;
  final String flag;
  const CountryOption({
    required this.name,
    required this.dialCode,
    required this.flag,
  });

  String get label => '$name (+$dialCode)';
}

class PhoneNumberService {
  static const List<CountryOption> countries = [
    CountryOption(name: 'فلسطين', dialCode: '970', flag: 'PS'),
    CountryOption(name: 'الأردن', dialCode: '962', flag: 'JO'),
    CountryOption(name: 'السعودية', dialCode: '966', flag: 'SA'),
    CountryOption(name: 'مصر', dialCode: '20', flag: 'EG'),
    CountryOption(name: 'الإمارات', dialCode: '971', flag: 'AE'),
    CountryOption(name: 'قطر', dialCode: '974', flag: 'QA'),
    CountryOption(name: 'الكويت', dialCode: '965', flag: 'KW'),
    CountryOption(name: 'البحرين', dialCode: '973', flag: 'BH'),
    CountryOption(name: 'عمان', dialCode: '968', flag: 'OM'),
    CountryOption(name: 'العراق', dialCode: '964', flag: 'IQ'),
    CountryOption(name: 'سوريا', dialCode: '963', flag: 'SY'),
    CountryOption(name: 'لبنان', dialCode: '961', flag: 'LB'),
    CountryOption(name: 'اليمن', dialCode: '967', flag: 'YE'),
    CountryOption(name: 'ليبيا', dialCode: '218', flag: 'LY'),
    CountryOption(name: 'تونس', dialCode: '216', flag: 'TN'),
    CountryOption(name: 'الجزائر', dialCode: '213', flag: 'DZ'),
    CountryOption(name: 'المغرب', dialCode: '212', flag: 'MA'),
    CountryOption(name: 'موريتانيا', dialCode: '222', flag: 'MR'),
    CountryOption(name: 'السودان', dialCode: '249', flag: 'SD'),
    CountryOption(name: 'الصومال', dialCode: '252', flag: 'SO'),
    CountryOption(name: 'جيبوتي', dialCode: '253', flag: 'DJ'),
    CountryOption(name: 'جزر القمر', dialCode: '269', flag: 'KM'),
    CountryOption(name: 'إسرائيل', dialCode: '972', flag: 'IL'),
    CountryOption(name: 'تركيا', dialCode: '90', flag: 'TR'),
    CountryOption(name: 'إيران', dialCode: '98', flag: 'IR'),
    CountryOption(name: 'قبرص', dialCode: '357', flag: 'CY'),
    CountryOption(name: 'الولايات المتحدة / كندا', dialCode: '1', flag: 'US'),
    CountryOption(name: 'المملكة المتحدة', dialCode: '44', flag: 'GB'),
    CountryOption(name: 'فرنسا', dialCode: '33', flag: 'FR'),
    CountryOption(name: 'ألمانيا', dialCode: '49', flag: 'DE'),
    CountryOption(name: 'إيطاليا', dialCode: '39', flag: 'IT'),
    CountryOption(name: 'إسبانيا', dialCode: '34', flag: 'ES'),
    CountryOption(name: 'البرتغال', dialCode: '351', flag: 'PT'),
    CountryOption(name: 'هولندا', dialCode: '31', flag: 'NL'),
    CountryOption(name: 'بلجيكا', dialCode: '32', flag: 'BE'),
    CountryOption(name: 'سويسرا', dialCode: '41', flag: 'CH'),
    CountryOption(name: 'النمسا', dialCode: '43', flag: 'AT'),
    CountryOption(name: 'السويد', dialCode: '46', flag: 'SE'),
    CountryOption(name: 'النرويج', dialCode: '47', flag: 'NO'),
    CountryOption(name: 'الدنمارك', dialCode: '45', flag: 'DK'),
    CountryOption(name: 'فنلندا', dialCode: '358', flag: 'FI'),
    CountryOption(name: 'آيسلندا', dialCode: '354', flag: 'IS'),
    CountryOption(name: 'إيرلندا', dialCode: '353', flag: 'IE'),
    CountryOption(name: 'اليونان', dialCode: '30', flag: 'GR'),
    CountryOption(name: 'بولندا', dialCode: '48', flag: 'PL'),
    CountryOption(name: 'التشيك', dialCode: '420', flag: 'CZ'),
    CountryOption(name: 'سلوفاكيا', dialCode: '421', flag: 'SK'),
    CountryOption(name: 'المجر', dialCode: '36', flag: 'HU'),
    CountryOption(name: 'رومانيا', dialCode: '40', flag: 'RO'),
    CountryOption(name: 'بلغاريا', dialCode: '359', flag: 'BG'),
    CountryOption(name: 'كرواتيا', dialCode: '385', flag: 'HR'),
    CountryOption(name: 'سلوفينيا', dialCode: '386', flag: 'SI'),
    CountryOption(name: 'صربيا', dialCode: '381', flag: 'RS'),
    CountryOption(name: 'البوسنة والهرسك', dialCode: '387', flag: 'BA'),
    CountryOption(name: 'الجبل الأسود', dialCode: '382', flag: 'ME'),
    CountryOption(name: 'مقدونيا الشمالية', dialCode: '389', flag: 'MK'),
    CountryOption(name: 'ألبانيا', dialCode: '355', flag: 'AL'),
    CountryOption(name: 'كوسوفو', dialCode: '383', flag: 'XK'),
    CountryOption(name: 'أوكرانيا', dialCode: '380', flag: 'UA'),
    CountryOption(name: 'روسيا', dialCode: '7', flag: 'RU'),
    CountryOption(name: 'بيلاروسيا', dialCode: '375', flag: 'BY'),
    CountryOption(name: 'مولدوفا', dialCode: '373', flag: 'MD'),
    CountryOption(name: 'إستونيا', dialCode: '372', flag: 'EE'),
    CountryOption(name: 'لاتفيا', dialCode: '371', flag: 'LV'),
    CountryOption(name: 'ليتوانيا', dialCode: '370', flag: 'LT'),
    CountryOption(name: 'مالطا', dialCode: '356', flag: 'MT'),
    CountryOption(name: 'لوكسمبورغ', dialCode: '352', flag: 'LU'),
    CountryOption(name: 'ليختنشتاين', dialCode: '423', flag: 'LI'),
    CountryOption(name: 'موناكو', dialCode: '377', flag: 'MC'),
    CountryOption(name: 'أندورا', dialCode: '376', flag: 'AD'),
    CountryOption(name: 'سان مارينو', dialCode: '378', flag: 'SM'),
    CountryOption(name: 'الفاتيكان', dialCode: '379', flag: 'VA'),
    CountryOption(name: 'الهند', dialCode: '91', flag: 'IN'),
    CountryOption(name: 'باكستان', dialCode: '92', flag: 'PK'),
    CountryOption(name: 'بنغلاديش', dialCode: '880', flag: 'BD'),
    CountryOption(name: 'أفغانستان', dialCode: '93', flag: 'AF'),
    CountryOption(name: 'سريلانكا', dialCode: '94', flag: 'LK'),
    CountryOption(name: 'نيبال', dialCode: '977', flag: 'NP'),
    CountryOption(name: 'بوتان', dialCode: '975', flag: 'BT'),
    CountryOption(name: 'المالديف', dialCode: '960', flag: 'MV'),
    CountryOption(name: 'الصين', dialCode: '86', flag: 'CN'),
    CountryOption(name: 'هونغ كونغ', dialCode: '852', flag: 'HK'),
    CountryOption(name: 'ماكاو', dialCode: '853', flag: 'MO'),
    CountryOption(name: 'تايوان', dialCode: '886', flag: 'TW'),
    CountryOption(name: 'اليابان', dialCode: '81', flag: 'JP'),
    CountryOption(name: 'كوريا الجنوبية', dialCode: '82', flag: 'KR'),
    CountryOption(name: 'كوريا الشمالية', dialCode: '850', flag: 'KP'),
    CountryOption(name: 'منغوليا', dialCode: '976', flag: 'MN'),
    CountryOption(name: 'إندونيسيا', dialCode: '62', flag: 'ID'),
    CountryOption(name: 'ماليزيا', dialCode: '60', flag: 'MY'),
    CountryOption(name: 'سنغافورة', dialCode: '65', flag: 'SG'),
    CountryOption(name: 'تايلاند', dialCode: '66', flag: 'TH'),
    CountryOption(name: 'الفلبين', dialCode: '63', flag: 'PH'),
    CountryOption(name: 'فيتنام', dialCode: '84', flag: 'VN'),
    CountryOption(name: 'كمبوديا', dialCode: '855', flag: 'KH'),
    CountryOption(name: 'لاوس', dialCode: '856', flag: 'LA'),
    CountryOption(name: 'ميانمار', dialCode: '95', flag: 'MM'),
    CountryOption(name: 'بروناي', dialCode: '673', flag: 'BN'),
    CountryOption(name: 'تيمور الشرقية', dialCode: '670', flag: 'TL'),
    CountryOption(name: 'كازاخستان', dialCode: '7', flag: 'KZ'),
    CountryOption(name: 'أوزبكستان', dialCode: '998', flag: 'UZ'),
    CountryOption(name: 'تركمانستان', dialCode: '993', flag: 'TM'),
    CountryOption(name: 'طاجيكستان', dialCode: '992', flag: 'TJ'),
    CountryOption(name: 'قيرغيزستان', dialCode: '996', flag: 'KG'),
    CountryOption(name: 'أذربيجان', dialCode: '994', flag: 'AZ'),
    CountryOption(name: 'أرمينيا', dialCode: '374', flag: 'AM'),
    CountryOption(name: 'جورجيا', dialCode: '995', flag: 'GE'),
    CountryOption(name: 'أستراليا', dialCode: '61', flag: 'AU'),
    CountryOption(name: 'نيوزيلندا', dialCode: '64', flag: 'NZ'),
    CountryOption(name: 'فيجي', dialCode: '679', flag: 'FJ'),
    CountryOption(name: 'بابوا غينيا الجديدة', dialCode: '675', flag: 'PG'),
    CountryOption(name: 'ساموا', dialCode: '685', flag: 'WS'),
    CountryOption(name: 'تونغا', dialCode: '676', flag: 'TO'),
    CountryOption(name: 'فانواتو', dialCode: '678', flag: 'VU'),
    CountryOption(name: 'جزر سليمان', dialCode: '677', flag: 'SB'),
    CountryOption(name: 'كيريباتي', dialCode: '686', flag: 'KI'),
    CountryOption(name: 'ناورو', dialCode: '674', flag: 'NR'),
    CountryOption(name: 'توفالو', dialCode: '688', flag: 'TV'),
    CountryOption(name: 'بالاو', dialCode: '680', flag: 'PW'),
    CountryOption(name: 'ميكرونيزيا', dialCode: '691', flag: 'FM'),
    CountryOption(name: 'جزر مارشال', dialCode: '692', flag: 'MH'),
    CountryOption(name: 'جنوب أفريقيا', dialCode: '27', flag: 'ZA'),
    CountryOption(name: 'نيجيريا', dialCode: '234', flag: 'NG'),
    CountryOption(name: 'كينيا', dialCode: '254', flag: 'KE'),
    CountryOption(name: 'إثيوبيا', dialCode: '251', flag: 'ET'),
    CountryOption(name: 'غانا', dialCode: '233', flag: 'GH'),
    CountryOption(name: 'تنزانيا', dialCode: '255', flag: 'TZ'),
    CountryOption(name: 'أوغندا', dialCode: '256', flag: 'UG'),
    CountryOption(name: 'رواندا', dialCode: '250', flag: 'RW'),
    CountryOption(name: 'بوروندي', dialCode: '257', flag: 'BI'),
    CountryOption(name: 'الكونغو الديمقراطية', dialCode: '243', flag: 'CD'),
    CountryOption(name: 'الكونغو', dialCode: '242', flag: 'CG'),
    CountryOption(name: 'الكاميرون', dialCode: '237', flag: 'CM'),
    CountryOption(name: 'ساحل العاج', dialCode: '225', flag: 'CI'),
    CountryOption(name: 'السنغال', dialCode: '221', flag: 'SN'),
    CountryOption(name: 'مالي', dialCode: '223', flag: 'ML'),
    CountryOption(name: 'النيجر', dialCode: '227', flag: 'NE'),
    CountryOption(name: 'تشاد', dialCode: '235', flag: 'TD'),
    CountryOption(name: 'بوركينا فاسو', dialCode: '226', flag: 'BF'),
    CountryOption(name: 'غينيا', dialCode: '224', flag: 'GN'),
    CountryOption(name: 'غينيا بيساو', dialCode: '245', flag: 'GW'),
    CountryOption(name: 'غامبيا', dialCode: '220', flag: 'GM'),
    CountryOption(name: 'سيراليون', dialCode: '232', flag: 'SL'),
    CountryOption(name: 'ليبيريا', dialCode: '231', flag: 'LR'),
    CountryOption(name: 'توغو', dialCode: '228', flag: 'TG'),
    CountryOption(name: 'بنين', dialCode: '229', flag: 'BJ'),
    CountryOption(name: 'الغابون', dialCode: '241', flag: 'GA'),
    CountryOption(name: 'غينيا الاستوائية', dialCode: '240', flag: 'GQ'),
    CountryOption(name: 'أفريقيا الوسطى', dialCode: '236', flag: 'CF'),
    CountryOption(name: 'أنغولا', dialCode: '244', flag: 'AO'),
    CountryOption(name: 'زامبيا', dialCode: '260', flag: 'ZM'),
    CountryOption(name: 'زيمبابوي', dialCode: '263', flag: 'ZW'),
    CountryOption(name: 'موزمبيق', dialCode: '258', flag: 'MZ'),
    CountryOption(name: 'مدغشقر', dialCode: '261', flag: 'MG'),
    CountryOption(name: 'ملاوي', dialCode: '265', flag: 'MW'),
    CountryOption(name: 'ناميبيا', dialCode: '264', flag: 'NA'),
    CountryOption(name: 'بوتسوانا', dialCode: '267', flag: 'BW'),
    CountryOption(name: 'ليسوتو', dialCode: '266', flag: 'LS'),
    CountryOption(name: 'إسواتيني', dialCode: '268', flag: 'SZ'),
    CountryOption(name: 'إريتريا', dialCode: '291', flag: 'ER'),
    CountryOption(name: 'جنوب السودان', dialCode: '211', flag: 'SS'),
    CountryOption(name: 'ساو تومي وبرينسيب', dialCode: '239', flag: 'ST'),
    CountryOption(name: 'سيشل', dialCode: '248', flag: 'SC'),
    CountryOption(name: 'موريشيوس', dialCode: '230', flag: 'MU'),
    CountryOption(name: 'الرأس الأخضر', dialCode: '238', flag: 'CV'),
    CountryOption(name: 'المكسيك', dialCode: '52', flag: 'MX'),
    CountryOption(name: 'البرازيل', dialCode: '55', flag: 'BR'),
    CountryOption(name: 'الأرجنتين', dialCode: '54', flag: 'AR'),
    CountryOption(name: 'تشيلي', dialCode: '56', flag: 'CL'),
    CountryOption(name: 'كولومبيا', dialCode: '57', flag: 'CO'),
    CountryOption(name: 'بيرو', dialCode: '51', flag: 'PE'),
    CountryOption(name: 'فنزويلا', dialCode: '58', flag: 'VE'),
    CountryOption(name: 'الإكوادور', dialCode: '593', flag: 'EC'),
    CountryOption(name: 'بوليفيا', dialCode: '591', flag: 'BO'),
    CountryOption(name: 'باراغواي', dialCode: '595', flag: 'PY'),
    CountryOption(name: 'أوروغواي', dialCode: '598', flag: 'UY'),
    CountryOption(name: 'غيانا', dialCode: '592', flag: 'GY'),
    CountryOption(name: 'سورينام', dialCode: '597', flag: 'SR'),
    CountryOption(name: 'بنما', dialCode: '507', flag: 'PA'),
    CountryOption(name: 'كوستاريكا', dialCode: '506', flag: 'CR'),
    CountryOption(name: 'نيكاراغوا', dialCode: '505', flag: 'NI'),
    CountryOption(name: 'هندوراس', dialCode: '504', flag: 'HN'),
    CountryOption(name: 'السلفادور', dialCode: '503', flag: 'SV'),
    CountryOption(name: 'غواتيمالا', dialCode: '502', flag: 'GT'),
    CountryOption(name: 'بليز', dialCode: '501', flag: 'BZ'),
    CountryOption(name: 'كوبا', dialCode: '53', flag: 'CU'),
    CountryOption(name: 'جمهورية الدومينيكان', dialCode: '1', flag: 'DO'),
    CountryOption(name: 'هايتي', dialCode: '509', flag: 'HT'),
    CountryOption(name: 'جامايكا', dialCode: '1', flag: 'JM'),
    CountryOption(name: 'ترينيداد وتوباغو', dialCode: '1', flag: 'TT'),
    CountryOption(name: 'باهاماس', dialCode: '1', flag: 'BS'),
    CountryOption(name: 'باربادوس', dialCode: '1', flag: 'BB'),
  ];

  static String normalize({
    required String input,
    required String defaultDialCode,
  }) {
    final trimmed = input.trim();
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    final dialCode = defaultDialCode.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (trimmed.startsWith('+')) {
      return digits;
    }
    if (digits.startsWith('00')) {
      return digits.substring(2);
    }
    if (dialCode.isNotEmpty && digits.startsWith(dialCode)) {
      return digits;
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$dialCode$digits';
  }

  static bool looksLikePhoneInput(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('+')) return true;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 6 && RegExp(r'^[\d\s()+-]+$').hasMatch(trimmed);
  }

  static bool isSupportedMobile(
    String input, {
    String defaultDialCode = '970',
  }) {
    final normalized = normalize(
      input: input,
      defaultDialCode: defaultDialCode,
    );
    return RegExp(r'^[1-9]\d{5,14}$').hasMatch(normalized);
  }

  static String localDisplay(String? input) {
    var digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    for (final country in countries) {
      final dialCode = country.dialCode;
      if (digits.startsWith(dialCode) && digits.length > dialCode.length) {
        return '+$dialCode ${digits.substring(dialCode.length)}';
      }
    }
    return '+$digits';
  }
}
