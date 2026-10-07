import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/services/api_service.dart';
import 'package:virtual_currency_cards/services/debt_book_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'debt sync acknowledges only confirmed work and preserves new work',
    () async {
      final service = DebtBookService();
      const userId = 'offline-sync-test-user';
      await service.upsertCustomerLocally(
        userId: userId,
        fullName: 'الأول',
        phone: '',
      );
      final firstBatch = await service.getPendingOperations(userId);
      final api = _DeferredDebtSyncApi();
      final syncing = service.syncPending(userId: userId, api: api);
      await api.requestStarted.future;

      await service.upsertCustomerLocally(
        userId: userId,
        fullName: 'الثاني',
        phone: '',
      );
      api.allowResponse.complete();
      await syncing;

      final pending = await service.getPendingOperations(userId);
      expect(pending, hasLength(1));
      expect(pending.single['opId'], isNot(firstBatch.single['opId']));
      final snapshot = await service.getSnapshot(userId);
      expect(snapshot['customers'], hasLength(2));
    },
  );
}

class _DeferredDebtSyncApi extends ApiService {
  final requestStarted = Completer<void>();
  final allowResponse = Completer<void>();
  String? _confirmedOperationId;

  @override
  Future<Map<String, dynamic>> syncDebtBook(
    List<Map<String, dynamic>> operations,
  ) async {
    _confirmedOperationId = operations.single['opId']?.toString();
    requestStarted.complete();
    await allowResponse.future;
    return {
      'applied': [
        {'opId': _confirmedOperationId},
      ],
      'customers': <Map<String, dynamic>>[],
      'entries': <Map<String, dynamic>>[],
      'summary': <String, dynamic>{},
    };
  }
}
