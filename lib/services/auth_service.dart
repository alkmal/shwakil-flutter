import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_version_service.dart';
import 'error_message_service.dart';
import 'local_security_service.dart';

class OtpRequestResult {
  const OtpRequestResult({
    this.message,
    this.whatsapp,
    this.debugOtpCode,
    this.otpRequired,
    this.pendingRegistrationId,
  });

  final String? message;
  final String? whatsapp;
  final String? debugOtpCode;
  final bool? otpRequired;
  final String? pendingRegistrationId;
}

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user_json';

  static String _normalizeUsername(String? value) {
    return value?.trim().toLowerCase() ?? '';
  }

  static String _normalizeIdentifier(String? value) {
    return value?.trim() ?? '';
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
    bool termsAccepted = false,
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await http.post(
      AppConfig.apiUri('auth/request-otp'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
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
        'deviceId': deviceId,
        'termsAccepted': termsAccepted,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
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
    );
  }

  Future<void> validateRegistration({
    required String fullName,
    required String username,
    required String password,
    required String whatsapp,
    required String countryCode,
    required String nationalId,
    required String birthDate,
    required bool termsAccepted,
    String? referralPhone,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/register/validate'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'fullName': fullName.trim(),
        'username': _normalizeUsername(username),
        'password': password,
        'whatsapp': whatsapp.trim(),
        'countryCode': countryCode.trim(),
        'nationalId': nationalId.trim(),
        'birthDate': birthDate.trim(),
        'referralPhone': referralPhone?.trim().isEmpty ?? true
            ? null
            : referralPhone?.trim(),
        'termsAccepted': termsAccepted,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
  }

  Future<OtpRequestResult> startRegistration({
    required String fullName,
    required String username,
    required String password,
    required String whatsapp,
    required String countryCode,
    required String nationalId,
    required String birthDate,
    required bool termsAccepted,
    String? referralPhone,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/register'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'fullName': fullName.trim(),
        'username': _normalizeUsername(username),
        'password': password,
        'whatsapp': whatsapp.trim(),
        'countryCode': countryCode.trim(),
        'nationalId': nationalId.trim(),
        'birthDate': birthDate.trim(),
        'referralPhone': referralPhone?.trim().isEmpty ?? true
            ? null
            : referralPhone?.trim(),
        'termsAccepted': termsAccepted,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
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
    );
  }

  Future<void> register({
    String? fullName,
    String? username,
    String? password,
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
    final response = await http.post(
      AppConfig.apiUri('auth/register'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'fullName': fullName?.trim(),
        'username': username == null ? null : _normalizeUsername(username),
        'password': password,
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
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
  }

  Future<void> login({
    required String username,
    required String password,
    String? otpCode,
  }) async {
    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final response = await http.post(
      AppConfig.apiUri('auth/login'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'username': _normalizeIdentifier(username),
        'identifier': _normalizeIdentifier(username),
        'password': password,
        'otpCode': (otpCode ?? '').trim(),
        'otpPurpose': 'login',
        'deviceId': deviceId,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    await _saveAuthPayload(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_tokenKey) ?? '').isNotEmpty;
  }

  Future<String?> currentUsername() async {
    final user = await currentUser();
    return user?['username']?.toString();
  }

  Future<Map<String, dynamic>?> currentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<String?> token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> cacheCurrentUser(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
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
    final authToken = await token();
    if (authToken == null || authToken.isEmpty) {
      return;
    }
    final response = await http.get(
      AppConfig.apiUri('auth/me'),
      headers: await _requestHeaders(token: authToken),
    );
    if (response.statusCode >= 400) {
      throw Exception(_extractMessage(response.body));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await cacheCurrentUser(Map<String, dynamic>.from(body['user'] as Map));
  }

  Future<Map<String, dynamic>> updateProfile({
    required String fullName,
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
        'fullName': fullName.trim(),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, payload['token']?.toString() ?? '');
    await prefs.setString(_userKey, jsonEncode(payload['user']));
  }

  String _extractMessage(String body) {
    return ErrorMessageService.fromResponseBody(body);
  }
}
