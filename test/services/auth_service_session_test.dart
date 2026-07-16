import 'dart:async';
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
    SharedPreferences.setMockInitialValues({'device_id': 'test-device-id'});
    FlutterSecureStorage.setMockInitialValues({});
    AuthService.resetMemoryCacheForTesting();
    PackageInfo.setMockInitialValues(
      appName: 'Shwakil',
      packageName: 'com.test.shwakil',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  group('AuthService session persistence', () {
    test(
      'restores a cached session after the in-memory cache is rebuilt',
      () async {
        final auth = AuthService();
        await _seedSession(auth);

        AuthService.resetMemoryCacheForTesting();
        final restored = AuthService();

        expect(await restored.token(), 'session-token');
        expect(await restored.isLoggedIn(), isTrue);
        expect(await restored.currentUser(), containsPair('id', 'user-1'));
      },
    );

    test('migrates a legacy cached session without losing it', () async {
      SharedPreferences.setMockInitialValues({
        'device_id': 'test-device-id',
        'auth_token': 'legacy-session-token',
        'auth_user_json': jsonEncode({
          'id': 'legacy-user',
          'name': 'Legacy cached user',
        }),
      });
      AuthService.resetMemoryCacheForTesting();

      final auth = AuthService();
      expect(await auth.token(), 'legacy-session-token');
      expect(await auth.currentUser(), containsPair('id', 'legacy-user'));

      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();
      expect(prefs.containsKey('auth_token'), isFalse);
      expect(prefs.containsKey('auth_user_json'), isFalse);
      expect(
        await secureStorage.read(key: 'auth_token'),
        'legacy-session-token',
      );
      expect(
        jsonDecode((await secureStorage.read(key: 'auth_user_json'))!),
        containsPair('id', 'legacy-user'),
      );
    });

    test(
      'recovers a legacy user cache when the secure copy is corrupt',
      () async {
        SharedPreferences.setMockInitialValues({
          'device_id': 'test-device-id',
          'auth_user_json': jsonEncode({
            'id': 'fallback-user',
            'name': 'Fallback user',
          }),
        });
        FlutterSecureStorage.setMockInitialValues({
          'auth_user_json': '{invalid-json',
        });
        AuthService.resetMemoryCacheForTesting();

        final user = await AuthService().currentUser();

        expect(user, containsPair('id', 'fallback-user'));
        expect(
          jsonDecode(
            (await const FlutterSecureStorage().read(key: 'auth_user_json'))!,
          ),
          containsPair('id', 'fallback-user'),
        );
      },
    );

    test(
      'keeps the cached session when refreshing fails on the network',
      () async {
        final auth = AuthService(
          client: MockClient((_) async {
            throw http.ClientException('network is unreachable');
          }),
        );
        await _seedSession(auth);

        expect(await auth.tryRefreshCurrentUser(), isFalse);
        await _expectSessionUnchanged(auth);
      },
    );

    test(
      'keeps a valid token when the user snapshot is missing and refresh is offline',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'auth_token': 'token-without-user-snapshot',
        });
        AuthService.resetMemoryCacheForTesting();
        final auth = AuthService(
          client: MockClient((request) async {
            throw http.ClientException('network is unreachable');
          }),
        );

        expect(await auth.currentUser(), isNull);
        expect(await auth.tryRefreshCurrentUser(), isFalse);
        expect(await auth.token(), 'token-without-user-snapshot');
        expect(await auth.isLoggedIn(), isTrue);
      },
    );

    test('keeps the cached session when auth/me returns 401', () async {
      final auth = AuthService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': 'Unauthorized'}),
            401,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await _seedSession(auth);

      await expectLater(auth.refreshCurrentUser(), throwsA(isA<Exception>()));
      await _expectSessionUnchanged(auth);
    });

    test(
      'recovers auth/me 401 with the trusted device refresh token',
      () async {
        var meCalls = 0;
        final auth = AuthService(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/device-session/refresh')) {
              return http.Response(
                jsonEncode({
                  'token': 'recovered-token',
                  'refreshToken': 'rotated-refresh-token',
                  'user': {'id': 'user-1', 'name': 'Recovered user'},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            meCalls++;
            if (meCalls == 1) {
              return http.Response(
                jsonEncode({'message': 'Unauthorized'}),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'authenticated': true,
                'user': {'id': 'user-1', 'name': 'Recovered user'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await _seedSession(auth);
        await const FlutterSecureStorage().write(
          key: 'device_session_refresh_token',
          value: 'trusted-refresh-token',
        );

        await auth.refreshCurrentUser();

        expect(await auth.token(), 'recovered-token');
        expect(
          await auth.currentUser(),
          containsPair('name', 'Recovered user'),
        );
        expect(meCalls, 2);
      },
    );

    test(
      'keeps the cached session when the device needs confirmation',
      () async {
        final auth = AuthService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'authenticated': false}),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        await _seedSession(auth);

        await expectLater(
          auth.refreshCurrentUser(),
          throwsA(
            isA<AuthRequestException>().having(
              (error) => error.deviceSessionOtpRequired,
              'deviceSessionOtpRequired',
              isTrue,
            ),
          ),
        );
        await _expectSessionUnchanged(auth);
      },
    );

    test('stores a transparently refreshed token and user', () async {
      final auth = AuthService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'authenticated': true,
              'token': 'rotated-token',
              'user': {'id': 'user-1', 'name': 'Updated name'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await _seedSession(auth);

      await auth.refreshCurrentUser();

      expect(await auth.token(), 'rotated-token');
      expect(await auth.currentUser(), containsPair('name', 'Updated name'));
    });

    test(
      'explicit logout calls the current-device endpoint and clears locally on 401',
      () async {
        late http.Request capturedRequest;
        final auth = AuthService(
          client: MockClient((request) async {
            capturedRequest = request;
            return http.Response(
              jsonEncode({'message': 'Unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await _seedSession(auth);

        await auth.logout();

        expect(capturedRequest.url.path, endsWith('/api/auth/logout'));
        expect(
          capturedRequest.headers['Authorization'],
          'Bearer session-token',
        );
        expect(capturedRequest.headers['X-Device-Id'], 'test-device-id');
        expect(
          jsonDecode(capturedRequest.body),
          containsPair('deviceId', 'test-device-id'),
        );
        expect(await auth.token(), isNull);
        expect(await auth.currentUser(), isNull);
        expect(await auth.isLoggedIn(), isFalse);
      },
    );

    test(
      'explicit logout clears locally when the server is unreachable',
      () async {
        final auth = AuthService(
          client: MockClient((_) async {
            throw http.ClientException('network is unreachable');
          }),
        );
        await _seedSession(auth);

        await auth.logout();

        expect(await auth.token(), isNull);
        expect(await auth.currentUser(), isNull);
        expect(await auth.isLoggedIn(), isFalse);
      },
    );

    test(
      'a delayed auth response cannot restore a logged-out session',
      () async {
        final delayedMe = Completer<http.Response>();
        final auth = AuthService(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/me')) {
              return delayedMe.future;
            }
            return http.Response(
              jsonEncode({'message': 'logged out'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await _seedSession(auth);

        final refresh = auth.refreshCurrentUser();
        await Future<void>.delayed(Duration.zero);
        await auth.logout();
        delayedMe.complete(
          http.Response(
            jsonEncode({
              'authenticated': true,
              'token': 'stale-rotated-token',
              'user': {'id': 'user-1', 'name': 'Stale response'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await refresh;

        expect(await auth.token(), isNull);
        expect(await auth.currentUser(), isNull);
        expect(await auth.isLoggedIn(), isFalse);
      },
    );

    test('trusted login sends the stored device refresh proof', () async {
      final requests = <http.Request>[];
      final auth = AuthService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'token': 'access-token-${requests.length}',
              'refreshToken': 'trusted-device-refresh-token',
              'user': {'id': 'user-1', 'name': 'Trusted user'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await auth.login(username: 'trusted', password: 'secret');
      await auth.login(username: 'trusted', password: 'secret');

      final firstPayload =
          jsonDecode(requests.first.body) as Map<String, dynamic>;
      final secondPayload =
          jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(firstPayload, isNot(contains('deviceRefreshToken')));
      expect(
        secondPayload['deviceRefreshToken'],
        'trusted-device-refresh-token',
      );
    });
  });

  test('a 401 API response preserves the current session', () async {
    final auth = AuthService();
    await _seedSession(auth);
    late http.Request capturedRequest;
    final api = ApiService(
      authService: auth,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'message': 'JWT token expired'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(api.getMyBalance(), throwsA(isA<Exception>()));

    expect(capturedRequest.headers['Authorization'], 'Bearer session-token');
    await _expectSessionUnchanged(auth);
  });

  test('financial requests send the server-verifiable security PIN', () async {
    final auth = AuthService();
    await _seedSession(auth);
    late http.Request capturedRequest;
    final api = ApiService(
      authService: auth,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'card': {}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.resellCard(
      cardId: 'card-1',
      securityPin: '1234',
      localAuthMethod: 'pin',
    );

    final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(payload['securityPin'], '1234');
    expect(payload, isNot(contains('localAuthMethod')));
  });

  test('OTP takes precedence over a PIN in financial requests', () async {
    final auth = AuthService();
    await _seedSession(auth);
    late http.Request capturedRequest;
    final api = ApiService(
      authService: auth,
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'card': {}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.resellCard(
      cardId: 'card-1',
      otpCode: '654321',
      securityPin: '1234',
    );

    final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(payload['otpCode'], '654321');
    expect(payload, isNot(contains('securityPin')));
  });

  test('direct API requests persist a transparently refreshed token', () async {
    final auth = AuthService();
    await _seedSession(auth);
    final api = ApiService(
      authService: auth,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'card': {}}),
          200,
          headers: {
            'content-type': 'application/json',
            'x-auth-token': 'rotated-session-token',
          },
        ),
      ),
    );

    await api.resellCard(cardId: 'card-1', securityPin: '1234');

    expect(await auth.token(), 'rotated-session-token');
  });

  test('password changes keep the refreshed session token', () async {
    final auth = AuthService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'ok'}),
          200,
          headers: {
            'content-type': 'application/json',
            'x-auth-token': 'password-rotated-token',
          },
        ),
      ),
    );
    await _seedSession(auth);

    await auth.changePassword(
      currentPassword: 'old-password',
      newPassword: 'new-password',
    );

    expect(await auth.token(), 'password-rotated-token');
    expect(await auth.currentUser(), containsPair('name', 'Cached name'));
  });
}

Future<void> _seedSession(AuthService auth) async {
  await auth.cacheToken('session-token');
  await auth.cacheCurrentUser({'id': 'user-1', 'name': 'Cached name'});
}

Future<void> _expectSessionUnchanged(AuthService auth) async {
  expect(await auth.token(), 'session-token');
  expect(await auth.isLoggedIn(), isTrue);
  expect(await auth.currentUser(), containsPair('name', 'Cached name'));
}
