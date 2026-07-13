import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virtual_currency_cards/services/api_service.dart';
import 'package:virtual_currency_cards/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'device_id': 'print-test-device'});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'saved-session'});
    AuthService.resetMemoryCacheForTesting();
    PackageInfo.setMockInitialValues(
      appName: 'Shwakil',
      packageName: 'com.test.shwakil',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  test('new card print request sends PIN and stable idempotency key', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiService(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'request': {'id': 'print-1'},
          }),
          bodies.length == 1 ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      await api.requestCardPrint(
        idempotencyKey: 'print.retry:key-1',
        value: 25,
        quantity: 35,
        cardType: 'standard',
        securityPin: '1234',
      );
    }

    expect(bodies, hasLength(2));
    expect(bodies[0]['idempotencyKey'], 'print.retry:key-1');
    expect(bodies[1]['idempotencyKey'], 'print.retry:key-1');
    expect(bodies[0]['securityPin'], '1234');
    expect(bodies[0].containsKey('localAuthMethod'), isFalse);
    expect(await AuthService().token(), 'saved-session');
  });

  test('existing-card print request sends OTP confirmation', () async {
    late Map<String, dynamic> body;
    final api = ApiService(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'request': {'id': 'print-2'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.requestExistingCardsPrint(
      idempotencyKey: 'existing.cards:2',
      cardIds: const ['card-1', 'card-2'],
      otpCode: '654321',
    );

    expect(body['idempotencyKey'], 'existing.cards:2');
    expect(body['cardIds'], ['card-1', 'card-2']);
    expect(body['otpCode'], '654321');
    expect(body.containsKey('securityPin'), isFalse);
  });

  test('admin print request sends confirmation for charged account', () async {
    late Map<String, dynamic> body;
    final api = ApiService(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'request': {'id': 'print-3'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.createAdminCardPrintRequest(
      idempotencyKey: 'admin.print:3',
      userId: 'owner-1',
      chargeUserId: 'payer-2',
      value: 50,
      quantity: 35,
      cardType: 'standard',
      securityPin: '4321',
    );

    expect(body['idempotencyKey'], 'admin.print:3');
    expect(body['userId'], 'owner-1');
    expect(body['chargeUserId'], 'payer-2');
    expect(body['securityPin'], '4321');
  });

  test(
    'card delete and admin transfer send server-verifiable confirmation',
    () async {
      final requests = <http.Request>[];
      final api = ApiService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path.endsWith('/transfer')
                ? jsonEncode({
                    'card': {
                      'id': 'card-1',
                      'barcode': '1234567890123456',
                      'value': 10,
                      'status': 'unused',
                    },
                  })
                : jsonEncode(<String, dynamic>{}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await api.deleteCard('card-1', securityPin: '1111');
      await api.deleteAdminCard('card-2', otpCode: '222222');
      await api.transferAdminCard(
        cardId: 'card-3',
        targetUserId: 'user-9',
        securityPin: '3333',
      );

      expect(requests, hasLength(3));
      expect(requests[0].method, 'DELETE');
      expect(jsonDecode(requests[0].body), {'securityPin': '1111'});
      expect(requests[1].method, 'DELETE');
      expect(jsonDecode(requests[1].body), {'otpCode': '222222'});
      expect(jsonDecode(requests[2].body), {
        'targetUserId': 'user-9',
        'securityPin': '3333',
      });
    },
  );
}
