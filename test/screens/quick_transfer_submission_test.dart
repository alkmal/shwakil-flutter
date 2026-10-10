import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/screens/quick_transfer_screen.dart';
import 'package:virtual_currency_cards/services/api_service.dart';
import 'package:virtual_currency_cards/services/auth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'device_id': 'test-device'});
  });

  Future<void> open(
    WidgetTester tester,
    _LookupApi api, {
    bool canTransfer = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QuickTransferScreen(
          authService: _Auth(canTransfer),
          apiService: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!canTransfer) return;
    await tester.enterText(find.byType(TextField).at(0), '0599000000');
    await tester.enterText(find.byType(TextField).at(1), '25');
  }

  testWidgets('keyboard submission cannot start a second recipient lookup', (
    tester,
  ) async {
    final api = _LookupApi();
    await open(tester, api);
    final submit = tester
        .widget<TextField>(find.byType(TextField).at(1))
        .onSubmitted!;
    submit('25');
    submit('25');
    await tester.pump();
    expect(api.calls, 1);
    await tester.pumpWidget(const SizedBox());
    api.pending.complete({
      'user': {'id': 'recipient'},
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('transfer form is unavailable without permission', (
    tester,
  ) async {
    final api = _LookupApi();
    await open(tester, api, canTransfer: false);
    expect(find.byType(TextField), findsNothing);
    await tester.pump();
    expect(api.calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('non-finite amounts never reach the lookup API', (tester) async {
    final api = _LookupApi();
    await open(tester, api);
    await tester.enterText(find.byType(TextField).at(1), 'NaN');
    tester.widget<TextField>(find.byType(TextField).at(1)).onSubmitted!('NaN');
    await tester.pump();
    expect(api.calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class _Auth extends AuthService {
  _Auth(this.canTransfer);
  final bool canTransfer;
  @override
  Future<Map<String, dynamic>?> currentUser() async => {
    'id': 'sender',
    'username': 'test',
    'permissions': {'canTransfer': canTransfer},
  };
}

class _LookupApi extends ApiService {
  int calls = 0;
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> lookupUserByPhone({
    required String phone,
    required String countryCode,
    bool inviteIfMissing = false,
  }) {
    calls++;
    return pending.future;
  }
}
