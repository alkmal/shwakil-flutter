import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleService extends ChangeNotifier {
  AppLocaleService._();

  static final AppLocaleService instance = AppLocaleService._();
  static const String _storageKey = 'app_locale_code';

  Locale? _locale;

  Locale? get locale => _locale;
  bool get isArabic => (_locale?.languageCode ?? 'ar') == 'ar';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(_storageKey);
    if (storedCode == 'ar' || storedCode == 'en') {
      _locale = Locale(storedCode!);
      return;
    }

    final systemCode = PlatformDispatcher.instance.locale.languageCode;
    _locale = Locale(systemCode == 'en' ? 'en' : 'ar');
  }

  Future<void> setLocale(Locale locale) async {
    final normalizedCode = locale.languageCode == 'en' ? 'en' : 'ar';
    if (_locale?.languageCode == normalizedCode) {
      return;
    }

    _locale = Locale(normalizedCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, normalizedCode);
    notifyListeners();
  }

  Future<void> toggleLocale() async {
    await setLocale(Locale(isArabic ? 'en' : 'ar'));
  }
}

class AppLocalizer {
  const AppLocalizer(this.locale);

  final Locale locale;

  bool get isArabic => locale.languageCode != 'en';
  bool get isEnglish => locale.languageCode == 'en';
  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  String text(String arabic, String english) => isArabic ? arabic : english;
}

extension AppLocalizationX on BuildContext {
  AppLocalizer get loc => AppLocalizer(Localizations.localeOf(this));
}
