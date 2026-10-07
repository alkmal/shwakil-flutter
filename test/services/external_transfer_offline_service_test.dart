import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/services/api_service.dart';
import 'package:virtual_currency_cards/services/external_transfer_offline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('failed sync keeps the queued transfer for a later retry', () async {
    final service = ExternalTransferOfflineService();
    final operation = await service.enqueue(
      userId: 'employee-1',
      payload: {'beneficiaryName': 'مستفيد', 'amount': 20},
    );

    await service.syncPending(
      userId: 'employee-1',
      api: _TestApi(shouldFail: true),
    );
    final queue = await service.getPending('employee-1');

    expect(queue, hasLength(1));
    expect(queue.single['clientRef'], operation['clientRef']);
    expect(queue.single['syncStatus'], 'failed');
  });

  test('successful retry removes only the acknowledged transfer', () async {
    final service = ExternalTransferOfflineService();
    final first = await service.enqueue(
      userId: 'employee-2',
      payload: {'beneficiaryName': 'أول', 'amount': 20},
    );
    final second = await service.enqueue(
      userId: 'employee-2',
      payload: {'beneficiaryName': 'ثان', 'amount': 30},
    );

    await service.syncPending(userId: 'employee-2', api: _TestApi());
    final queue = await service.getPending('employee-2');

    expect(queue, isEmpty);
    expect(first['clientRef'], isNot(second['clientRef']));
  });
}

class _TestApi extends ApiService {
  _TestApi({this.shouldFail = false});

  final bool shouldFail;

  @override
  Future<Map<String, dynamic>> createExternalTransfer(
    Map<String, dynamic> payload,
  ) async {
    if (shouldFail) throw Exception('offline');
    return {'id': 1};
  }
}
