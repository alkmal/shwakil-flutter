import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/app_theme.dart';
import 'package:virtual_currency_cards/widgets/responsive_scaffold_container.dart';
import 'package:virtual_currency_cards/widgets/shwakel_page_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('explicit page padding is not added to the mobile gutter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveScaffoldContainer(
            useSafeArea: false,
            padding: EdgeInsets.all(24),
            child: SizedBox(key: ValueKey('content'), width: 10, height: 10),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(const ValueKey('content'))).dx, 24);
  });

  testWidgets('page header remains usable with large text on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.4,
          maxScaleFactor: 1.4,
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(8),
              child: ShwakelPageHeader(
                title: 'عنوان الصفحة الطويل',
                subtitle:
                    'وصف أطول للتحقق من الاستجابة عند تكبير النص على الهاتف.',
                badges: [
                  ShwakelInfoBadge(
                    icon: Icons.verified_rounded,
                    label: 'حالة حساب طويلة قابلة للالتفاف بأمان',
                  ),
                ],
                trailing: SizedBox(key: ValueKey('trailing'), height: 52),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    final trailingRect = tester.getRect(find.byKey(const ValueKey('trailing')));
    expect(trailingRect.width, greaterThanOrEqualTo(240));
    expect(trailingRect.height, closeTo(52, 0.01));
    expect(trailingRect.left, greaterThanOrEqualTo(8));
    expect(trailingRect.right, lessThanOrEqualTo(312));
  });
}
