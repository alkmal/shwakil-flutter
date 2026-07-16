import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/scan_card_presentation_policy.dart';

void main() {
  group('ScanCardPresentationPolicy', () {
    test(
      'shows NFC only when both payment and NFC permissions are enabled',
      () {
        expect(
          ScanCardPresentationPolicy.canShowNfc({
            'permissions': {
              'canAcceptPrepaidMultipayPayments': true,
              'canUsePrepaidMultipayNfc': true,
            },
          }, offlineMode: false),
          isTrue,
        );

        expect(
          ScanCardPresentationPolicy.canShowNfc({
            'permissions': {
              'canAcceptPrepaidMultipayPayments': true,
              'canUsePrepaidMultipayNfc': false,
            },
          }, offlineMode: false),
          isFalse,
        );

        expect(
          ScanCardPresentationPolicy.canShowNfc({
            'permissions': {
              'canAcceptPrepaidMultipayPayments': false,
              'canUsePrepaidMultipayNfc': true,
            },
          }, offlineMode: false),
          isFalse,
        );
      },
    );

    test('never shows NFC inside the offline workspace', () {
      expect(
        ScanCardPresentationPolicy.canShowNfc({
          'permissions': {
            'canAcceptPrepaidMultipayPayments': true,
            'canUsePrepaidMultipayNfc': true,
          },
        }, offlineMode: true),
        isFalse,
      );
    });

    test(
      'shows offline mode only to accounts with offline scan permission',
      () {
        expect(
          ScanCardPresentationPolicy.canShowOfflineMode({
            'permissions': {'canOfflineCardScan': true},
          }),
          isTrue,
        );
        expect(
          ScanCardPresentationPolicy.canShowOfflineMode({
            'permissions': {'canOfflineCardScan': false},
          }),
          isFalse,
        );
      },
    );

    test('reveals usage identity only to admin and support roles', () {
      for (final role in ['admin', 'support', 'super_admin']) {
        expect(
          ScanCardPresentationPolicy.canRevealUsageIdentity({
            'role': role,
          }, offlineMode: false),
          isTrue,
          reason: role,
        );
      }

      for (final role in ['merchant', 'customer', 'driver', 'finance']) {
        expect(
          ScanCardPresentationPolicy.canRevealUsageIdentity({
            'role': role,
          }, offlineMode: false),
          isFalse,
          reason: role,
        );
      }
    });

    test('does not reveal usage identity in offline mode', () {
      expect(
        ScanCardPresentationPolicy.canRevealUsageIdentity({
          'role': 'admin',
        }, offlineMode: true),
        isFalse,
      );
    });
  });
}
