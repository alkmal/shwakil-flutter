import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/services/local_security_service.dart';
import 'package:virtual_currency_cards/widgets/local_security_setup_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await LocalSecurityService.clearTrustedState();
  });

  testWidgets('cancel continues without forcing device security settings', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showOptionalLocalSecuritySetupPrompt(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel and continue'), findsOneWidget);

    await tester.tap(find.text('Cancel and continue'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(LocalSecurityService.securitySetupRequired, isFalse);
  });

  testWidgets('transition is returned only after explicit confirmation', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showOptionalLocalSecuritySetupPrompt(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
