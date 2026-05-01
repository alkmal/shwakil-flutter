import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_version_service.dart';
import 'error_message_service.dart';
import 'local_security_service.dart';
import 'network_client_service.dart';

class OtpRequestResult {
  const OtpRequestResult({
    this.message,
    this.whatsapp,
    this.debugOtpCode,
    this.otpRequired,
    this.pendingRegistrationId,
    this.loginRequired,
    this.loginIdentifier,
  });

  final String? message;
  final String? whatsapp;
  final String? debugOtpCode;
  final bool? otpRequired;
  final String? pendingRegistrationId;
  final bool? loginRequired;
  final String? loginIdentifier;
}

class PendingRegistrationLookupResult {
  const PendingRegistrationLookupResult({
    required this.hasPendingRegistration,
    this.message,
    this.pendingRegistration,
  });

  final bool hasPendingRegistration;
  final String? message;
  final Map<String, dynamic>? pendingRegistration;
}

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user_json';
  static const Duration _requestTimeout = Duration(seconds: 10);
  static final http.Client _client = NetworkClientService.client;
  static SharedPreferences? _cachedPrefs;
  static String? _cachedToken;
  static Map<String, dynamic>? _cachedUser;
  static Future<void>? _pendingRefreshCurrentUser;

  static String _normalizeUsername(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  static String _normalizeIdentifier(String? value) {
    return value?.trim() ?? '';
  }

  static Map<String, dynamic>? peekCurrentUser() {
    final cached = _cachedUser;
    return cached == null ? null : Map<String, dynamic>.from(cached);
  }

  static String? peekToken() => _cachedToken;

  static Future<SharedPreferences> _prefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  Future<Map<String, String>> _jsonHeaders({String? token}) async {
    final headers = await AppVersionService.publicHeaders(
      includeJsonContentType: true,
    );
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, String>> _requestHeaders({String? token}) async {
    final headers = await AppVersionService.publicHeaders();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<OtpRequestResult> requestOtp({
    required String purpose,
    String? username,
    String? password,
    String? fullName,
    String? whatsapp,
    String? countryCode,
    String? nationalId,
    String? birthDate,
    String? referralPhone,
    String? pendingRegistrationId,
    bool termsAccepted = false,
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'auth/request-otp',
      body: {
        'purpose': purpose,
        'username': _normalizeIdentifier(username),
        'identifier': _normalizeIdentifier(username),
        'password': password,
        'fullName': fullName?.trim(),
        'whatsapp': whatsapp?.trim(),
        'countryCode': countryCode?.trim(),
        'nationalId': nationalId?.trim(),
        'birthDate': birthDate?.trim(),
        'referralPhone': referralPhone?.trim(),
        'pendingRegistrationId': pendingRegistrationId?.trim(),
        'deviceId': deviceId,
        'termsAccepted': termsAccepted,
      },
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractRegistrationMessage(response.body));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtpRequestResult(
      message: body['message']?.toString(),
      whatsapp: body['whatsapp']?.toString(),
      debugOtpCode: body['debugOtpCode']?.toString(),
      otpRequired: body['otpRequired'] is bool
          ? body['otpRequired'] as bool
          : null,
      pendingRegistrationId: body['pendingRegistrationId']?.toString(),
      loginRequired: body['loginRequired'] is bool
          ? body['loginRequired'] as bool
          : null,
      loginIdentifier: body['loginIdentifier']?.toString(),
    );
  }

  Future<void> validateRegistration({
    required String fullName,
    String? username,
    required String whatsapp,
    required String countryCode,
    String? nationalId,
    String? birthDate,
    required bool termsAccepted,
    String? referralPhone,
  }) async {
    final response = await _postWithFallback(
      'auth/register/validate',
      body: {
        'fullName': fullName.trim(),
        'username': username == null || username.trim().isEmpty
            ? null
            : _normalizeUsername(username),
        'whatsapp': whatsapp.trim(),
        'countryCode': countryCode.trim(),
        'nationalId': nationalId?.trim(),
        'birthDate': birthDate?.trim(),
        'referralPhone': referralPhone?.trim().isEmpty ?? true
            ? null
            : referralPhone?.trim(),
        'termsAccepted': termsAccepted,
      },
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractRegistrationMessage(response.body));
    }
  }

  Future<OtpRequestResult> startRegistration({
    required String fullName,
    String? username,
    required String whatsapp,
    required String countryCode,
    String? nationalId,
    String? birthDate,
    required bool termsAccepted,
    String? referralPhone,
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'auth/register',
      body: {
        'fullName': fullName.trim(),
        'username': username == null || username.trim().isEmpty
            ? null
            : _normalizeUsername(username),
        'whatsapp': whatsapp.trim(),
        'countryCode': countryCode.trim(),
        'nationalId': nationalId?.trim(),
        'birthDate': birthDate?.trim(),
        'referralPhone': referralPhone?.trim().isEmpty ?? true
            ? null
            : referralPhone?.trim(),
        'termsAccepted': termsAccepted,
        'deviceId': deviceId,
      },
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractRegistrationMessage(response.body));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtpRequestResult(
      message: body['message']?.toString(),
      whatsapp: body['whatsapp']?.toString(),
      debugOtpCode: body['debugOtpCode']?.toString(),
      otpRequired: body['otpRequired'] is bool
          ? body['otpRequired'] as bool
          : null,
      pendingRegistrationId: body['pendingRegistrationId']?.toString(),
      loginRequired: body['loginRequired'] is bool
          ? body['loginRequired'] as bool
          : null,
      loginIdentifier: body['loginIdentifier']?.toString(),
    );
  }

  Future<PendingRegistrationLookupResult>
  getPendingRegistrationForCurrentDevice() async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'auth/register/pending',
      body: {'deviceId': deviceId},
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractRegistrationMessage(response.body));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final pendingRegistrationValue = body['pendingRegistration'];

    return PendingRegistrationLookupResult(
      hasPendingRegistration: body['hasPendingRegistration'] == true,
      message: body['message']?.toString(),
      pendingRegistration: pendingRegistrationValue is Map
          ? Map<String, dynamic>.from(pendingRegistrationValue)
          : null,
    );
  }

  Future<Map<String, dynamic>> register({
    String? fullName,
    String? username,
    String? whatsapp,
    String? countryCode,
    String? nationalId,
    String? birthDate,
    bool? termsAccepted,
    String? referralPhone,
    String? pendingRegistrationId,
    String? otpCode,
    String otpPurpose = 'register',
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'auth/register',
      body: {
        'fullName': fullName?.trim(),
        'username': username == null ? null : _normalizeUsername(username),
        'whatsapp': whatsapp?.trim(),
        'countryCode': countryCode?.trim(),
        'nationalId': nationalId?.trim(),
        'birthDate': birthDate?.trim(),
        'referralPhone': referralPhone?.trim().isEmpty ?? true
            ? null
            : referralPhone?.trim(),
        'termsAccepted': termsAccepted,
        'pendingRegistrationId': pendingRegistrationId?.trim(),
        'otpCode': otpCode?.trim(),
        'otpPurpose': otpPurpose,
        'deviceId': deviceId,
      },
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractRegistrationMessage(response.body));
    }
    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'auth/login',
      body: {
        'username': _normalizeIdentifier(username),
        'identifier': _normalizeIdentifier(username),
        'password': password,
        'otpCode': (otpCode ?? '').trim(),
        'otpPurpose': 'login',
        'deviceId': deviceId,
      },
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    await _saveAuthPayload(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final prefs = await _prefs();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _cachedToken = null;
    _cachedUser = null;
  }

  Future<bool> isLoggedIn() async {
    return ((await token()) ?? '').isNotEmpty;
  }

  Future<String?> currentUsername() async {
    final user = await currentUser();
    return user?['username']?.toString();
  }

  Future<Map<String, dynamic>?> currentUser() async {
    final cached = _cachedUser;
    if (cached != null) {
      return Map<String, dynamic>.from(cached);
    }
    final prefs = await _prefs();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    _cachedUser = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return Map<String, dynamic>.from(_cachedUser!);
  }

  Future<String?> token() async {
    final cached = _cachedToken;
    if (cached != null) {
      return cached;
    }
    final prefs = await _prefs();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  Future<void> cacheCurrentUser(Map<String, dynamic> user) async {
    final prefs = await _prefs();
    _cachedUser = Map<String, dynamic>.from(user);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  Future<void> patchCurrentUser(Map<String, dynamic> patch) async {
    if (patch.isEmpty) {
      return;
    }
    final current = await currentUser();
    if (current == null) {
      return;
    }
    current.addAll(patch);
    await cacheCurrentUser(current);
  }

  Future<void> refreshCurrentUser() async {
    final pending = _pendingRefreshCurrentUser;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _refreshCurrentUserInternal();
    _pendingRefreshCurrentUser = future;
    try {
      await future;
    } finally {
      if (identical(_pendingRefreshCurrentUser, future)) {
        _pendingRefreshCurrentUser = null;
      }
    }
  }

  Future<void> _refreshCurrentUserInternal() async {
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .get(
          AppConfig.apiUri('auth/me'),
          headers: await _requestHeaders(token: authToken),
        )
        .timeout(_requestTimeout);
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await cacheCurrentUser(Map<String, dynamic>.from(body['user'] as Map));
    assert(() {
      // ignore: avoid_print
      print('[auth] GET auth/me ${stopwatch.elapsed.inMilliseconds}ms');
      return true;
    }());
  }

  Future<Map<String, dynamic>> updateProfile({
    required String businessName,
    required String fullName,
    required String username,
    required String email,
    required String address,
    required String nationalId,
    required String birthDate,
    required String referralPhone,
  }) async {
    final authToken = await token();
    final response = await http.put(
      AppConfig.apiUri('auth/profile'),
      headers: await _jsonHeaders(token: authToken),
      body: jsonEncode({
        'businessName': businessName.trim(),
        'fullName': fullName.trim(),
        'username': _normalizeUsername(username),
        'email': email.trim(),
        'address': address.trim(),
        'nationalId': nationalId.trim(),
        'birthDate': birthDate.trim(),
        'referralPhone': referralPhone.trim(),
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await cacheCurrentUser(Map<String, dynamic>.from(body['user'] as Map));
    return body;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final authToken = await token();
    final response = await http.post(
      AppConfig.apiUri('auth/change-password'),
      headers: await _jsonHeaders(token: authToken),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
  }

  Future<void> deleteAccount() async {
    final authToken = await token();
    final response = await http.delete(
      AppConfig.apiUri('auth/account'),
      headers: await _jsonHeaders(token: authToken),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    await logout();
  }

  Future<OtpRequestResult> requestPasswordResetOtp({
    required String username,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/password-reset/request-otp'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'username': _normalizeIdentifier(username),
        'identifier': _normalizeIdentifier(username),
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return OtpRequestResult(
      message: body['message']?.toString(),
      debugOtpCode: body['debugOtpCode']?.toString(),
    );
  }

  Future<void> resetPassword({
    required String username,
    required String otpCode,
    required String newPassword,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/password-reset/reset'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'username': _normalizeIdentifier(username),
        'identifier': _normalizeIdentifier(username),
        'otpCode': otpCode.trim(),
        'newPassword': newPassword,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
  }

  Future<Map<String, dynamic>> lookupAccountByIdentity({
    required String nationalId,
    required String birthDate,
    required String whatsapp,
    required String countryCode,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/account-recovery/lookup'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'nationalId': nationalId.trim(),
        'birthDate': birthDate.trim(),
        'whatsapp': whatsapp.trim(),
        'countryCode': countryCode.trim(),
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _saveAuthPayload(Map<String, dynamic> payload) async {
    final prefs = await _prefs();
    _cachedToken = payload['token']?.toString() ?? '';
    _cachedUser = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : null;
    await prefs.setString(_tokenKey, _cachedToken ?? '');
    await prefs.setString(_userKey, jsonEncode(payload['user']));
  }

  String _extractMessage(String body) {
    return ErrorMessageService.fromResponseBody(body);
  }

  String _extractRegistrationMessage(String body) {
    return ErrorMessageService.fromRegistrationResponseBody(body);
  }

  Future<http.Response> _postWithFallback(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    Object? lastError;
    for (final uri in AppConfig.apiCandidateUris(path)) {
      try {
        return await _client
            .post(uri, headers: await _jsonHeaders(), body: jsonEncode(body))
            .timeout(_requestTimeout);
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      }
    }

    throw lastError ?? Exception('Request failed');
  }
}
