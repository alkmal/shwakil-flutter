import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/screens/otp_verification_screen.dart';
import 'package:virtual_currency_cards/screens/register_screen.dart';
import 'package:virtual_currency_cards/services/auth_service.dart';
import 'package:virtual_currency_cards/utils/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device_id': 'registration-session-test-device',
    });
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'preserved-registration-session',
      'auth_user_json': '{"id":"existing-user","username":"existing"}',
    });
    AuthService.resetMemoryCacheForTesting();
    PackageInfo.setMockInitialValues(
      appName: 'Shwakil',
      packageName: 'com.test.shwakil',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  testWidgets('opening registration never clears an existing session', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(const RegisterScreen(loadInitialData: false)),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      await tester.runAsync(() => AuthService().token()),
      'preserved-registration-session',
    );
    expect(
      await tester.runAsync(() => AuthService().currentUser()),
      containsPair('id', 'existing-user'),
    );
  });

  testWidgets('opening registration OTP never clears an existing session', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        const OtpVerificationScreen(
          fullName: 'New Customer',
          username: 'new-customer',
          purpose: 'register',
          whatsapp: '0590000000',
          countryCode: '970',
          termsAccepted: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      await tester.runAsync(() => AuthService().token()),
      'preserved-registration-session',
    );
    expect(
      await tester.runAsync(() => AuthService().currentUser()),
      containsPair('id', 'existing-user'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _testApp(Widget home) {
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.lightTheme,
    home: home,
  );
}
