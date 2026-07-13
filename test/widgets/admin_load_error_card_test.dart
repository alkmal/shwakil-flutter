import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/widgets/admin/admin_load_error_card.dart';

void main() {
  testWidgets('admin load error is retryable on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminLoadErrorCard(
              message: 'Network unavailable',
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('admin-load-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(retries, 1);
  });
}
