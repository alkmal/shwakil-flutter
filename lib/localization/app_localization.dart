import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_strings_ar.dart';
import 'app_strings_en.dart';

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

  Map<String, String> get _strings => isArabic ? appStringsAr : appStringsEn;

  String tr(String key, {Map<String, String>? params, String? fallback}) {
    var value = _resolveValue(key, fallback: fallback);
    if (params != null) {
      params.forEach((name, replacement) {
        value = value.replaceAll('{$name}', replacement);
      });
    }
    return value;
  }

  String text(String arabic, String english) => isArabic ? arabic : english;

  String _resolveValue(String key, {String? fallback}) {
    final englishValue = appStringsEn[key] ?? fallback ?? key;
    final sourceValue = _strings[key];
    if (!isArabic) {
      return sourceValue ?? englishValue;
    }

    final arabicValue = sourceValue ?? englishValue;
    final repairedValue = _repairMojibake(arabicValue);
    if (_looksBrokenArabic(repairedValue)) {
      return englishValue;
    }
    return repairedValue;
  }

  String _repairMojibake(String value) {
    if (!RegExp('[\\u00C3\\u00C2\\u00D8\\u00D9\\u00E2]').hasMatch(value)) {
      return value;
    }

    try {
      return utf8.decode(latin1.encode(value));
    } catch (_) {
      return value;
    }
  }

  bool _looksBrokenArabic(String value) {
    if (value.trim().isEmpty) {
      return true;
    }

    if (RegExp(r'\?{2,}').hasMatch(value)) {
      return true;
    }

    if (RegExp('[\\u00C3\\u00C2\\u00D8\\u00D9\\u00E2]').hasMatch(value)) {
      return true;
    }

    return false;
  }
}

extension AppLocalizationX on BuildContext {
  AppLocalizer get loc => AppLocalizer(Localizations.localeOf(this));
}
