import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/screens/account_settings_screen.dart';
import 'package:virtual_currency_cards/services/auth_service.dart';
import 'package:virtual_currency_cards/utils/app_theme.dart';

void main() {
  testWidgets('token without a user snapshot shows recovery, not login', (
    tester,
  ) async {
    final auth = _MissingSnapshotAuthService();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.lightTheme,
        routes: {
          '/login': (_) =>
              const Scaffold(body: Text('login', key: ValueKey('login'))),
        },
        home: AccountSettingsScreen(authService: auth),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('account-session-recovery')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('login')), findsNothing);
    expect(await auth.token(), 'preserved-token');
  });
}

class _MissingSnapshotAuthService extends AuthService {
  @override
  Future<String?> token() async => 'preserved-token';

  @override
  Future<Map<String, dynamic>?> currentUser() async => null;

  @override
  Future<bool> tryRefreshCurrentUser() async => false;
}
