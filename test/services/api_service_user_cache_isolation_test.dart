import 'dart:convert';

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
    SharedPreferences.setMockInitialValues({'device_id': 'cache-test-device'});
    ApiService.invalidateNotificationSummaryCache();
    PackageInfo.setMockInitialValues(
      appName: 'Shwakil',
      packageName: 'com.test.shwakil',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  test('notification summary cache is isolated by account', () async {
    var firstRequests = 0;
    var secondRequests = 0;
    final first = ApiService(
      authService: _AccountAuthService('account-a'),
      client: MockClient((request) async {
        firstRequests++;
        return http.Response(
          jsonEncode({
            'summary': {'unreadCount': 7},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final second = ApiService(
      authService: _AccountAuthService('account-b'),
      client: MockClient((request) async {
        secondRequests++;
        return http.Response(
          jsonEncode({
            'summary': {'unreadCount': 2},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect((await first.getNotificationSummary())['summary'], {
      'unreadCount': 7,
    });
    expect((await second.getNotificationSummary())['summary'], {
      'unreadCount': 2,
    });
    expect(firstRequests, 1);
    expect(secondRequests, 1);
  });
}

class _AccountAuthService extends AuthService {
  _AccountAuthService(this.id);

  final String id;

  @override
  Future<Map<String, dynamic>?> currentUser() async => {'id': id};

  @override
  Future<String?> token() async => 'token-$id';
}
