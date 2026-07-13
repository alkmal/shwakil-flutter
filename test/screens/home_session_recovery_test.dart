import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/screens/home_screen.dart';
import 'package:virtual_currency_cards/services/auth_service.dart';
import 'package:virtual_currency_cards/utils/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device-id'});
    AuthService.resetMemoryCacheForTesting();
  });

  testWidgets(
    'missing permission snapshot shows recovery without opening login',
    (tester) async {
      final auth = _SessionRecoveryAuthService(
        token: 'preserved-session-token',
        user: {'id': 'user-1', 'username': 'cached-user'},
      );

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
          home: HomeScreen(authService: auth),
        ),
      );
      await tester.pump();
      for (var attempt = 0; attempt < 30; attempt++) {
        if (find
            .byKey(const ValueKey('session-recovery'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const ValueKey('session-recovery')), findsOneWidget);
      expect(find.byKey(const ValueKey('login')), findsNothing);
      expect(await auth.token(), 'preserved-session-token');
      expect(await auth.currentUser(), containsPair('id', 'user-1'));
    },
  );
}

class _SessionRecoveryAuthService extends AuthService {
  _SessionRecoveryAuthService({required String token, required this.user})
    : _token = token;

  final String _token;
  final Map<String, dynamic> user;

  @override
  Future<String?> token() async => _token;

  @override
  Future<Map<String, dynamic>?> currentUser() async =>
      Map<String, dynamic>.from(user);

  @override
  Future<bool> tryRefreshCurrentUser() async => false;
}
