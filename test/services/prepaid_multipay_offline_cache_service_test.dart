import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/services/prepaid_multipay_offline_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  const service = PrepaidMultipayOfflineCacheService();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('never exposes one user prepaid cache to another user', () async {
    await service.save(
      ownerUserId: 'user-a',
      cards: [
        {'id': 'card-a', 'balance': 25},
      ],
      payments: [
        {'id': 'payment-a'},
      ],
      nfcEnabled: true,
      canUsePrepaidCards: true,
      canAcceptPrepaidPayments: true,
      canUsePrepaidNfc: true,
    );

    expect(await service.load(ownerUserId: 'user-b'), isNull);
    final ownerCache = await service.load(ownerUserId: 'user-a');
    expect((ownerCache!['cards'] as List).single['id'], 'card-a');
  });

  test(
    'rejects a tampered scoped cache whose embedded owner does not match',
    () async {
      final userBKey = _keyForUser('user-b');
      FlutterSecureStorage.setMockInitialValues({
        userBKey: jsonEncode({
          'ownerUserId': 'user-a',
          'cards': [
            {'id': 'card-a'},
          ],
          'payments': <Map<String, dynamic>>[],
          'canUsePrepaidCards': true,
        }),
      });

      expect(await service.load(ownerUserId: 'user-b'), isNull);
    },
  );

  test(
    'discards the old unscoped cache because its owner is unknowable',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        PrepaidMultipayOfflineCacheService.cacheKey: jsonEncode({
          'cards': [
            {'id': 'legacy-card'},
          ],
        }),
      });

      expect(await service.load(ownerUserId: 'user-a'), isNull);
      expect(
        await storage.read(key: PrepaidMultipayOfflineCacheService.cacheKey),
        isNull,
      );
    },
  );
}

String _keyForUser(String userId) {
  final encoded = base64Url.encode(utf8.encode(userId)).replaceAll('=', '');
  return '${PrepaidMultipayOfflineCacheService.cacheKey}:$encoded';
}
