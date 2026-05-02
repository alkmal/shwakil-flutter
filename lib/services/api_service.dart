import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;

import '../localization/app_localization.dart';
import '../localization/app_strings_ar.dart';
import '../localization/app_strings_en.dart';
import '../models/index.dart';
import 'app_config.dart';
import 'app_version_service.dart';
import 'auth_service.dart';
import 'error_message_service.dart';
import 'network_client_service.dart';
import 'phone_number_service.dart';

class ApiService {
  final AuthService _authService = AuthService();
  bool lastCardLookupAutoRedeemed = false;
  static final http.Client _client = NetworkClientService.client;
  static const Duration _publicRequestTimeout = Duration(seconds: 8);
  static const Duration _authenticatedRequestTimeout = Duration(seconds: 12);
  static const Duration _authSettingsCacheLifetime = Duration(minutes: 5);
  static const Duration _notificationSummaryCacheLifetime = Duration(
    seconds: 20,
  );
  static Map<String, dynamic>? _cachedAuthSettings;
  static DateTime? _cachedAuthSettingsAt;
  static Future<Map<String, dynamic>>? _pendingAuthSettingsRequest;
  static Map<String, dynamic>? _cachedNotificationSummary;
  static DateTime? _cachedNotificationSummaryAt;
  static Future<Map<String, dynamic>>? _pendingNotificationSummaryRequest;

  Future<Map<String, String>> _headers() async {
    final token = await _authService.token();
    final headers = await AppVersionService.publicHeaders(
      includeJsonContentType: true,
    );
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, String>> authenticatedHeaders() => _headers();

  Uri adminVerificationFileUri({
    required String requestId,
    required String fileType,
  }) {
    return AppConfig.apiUri('admin/verifications/$requestId/files/$fileType');
  }

  Future<Map<String, String>> _publicHeaders() {
    return AppVersionService.publicHeaders();
  }

  Future<Map<String, dynamic>> getMyBalance({
    String locationFilter = 'all',
    int page = 1,
    int perPage = 8,
    bool printingDebtOnly = false,
  }) async {
    final response = await _client.get(
      AppConfig.apiUri('balance/me', {
        if (locationFilter != 'all') 'locationFilter': locationFilter,
        'page': page.toString(),
        'perPage': perPage.toString(),
        if (printingDebtOnly) 'printingDebtOnly': 'true',
      }),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    final responseUser = body['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(body['user'] as Map<String, dynamic>)
        : body['user'] is Map
        ? Map<String, dynamic>.from(body['user'] as Map)
        : null;
    if (responseUser != null) {
      await _authService.cacheCurrentUser(responseUser);
    } else if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    final user = responseUser ?? await _authService.currentUser();
    return {
      'user': user ?? <String, dynamic>{},
      'transactions': List<dynamic>.from(
        body['statement'] as List? ?? const [],
      ),
      'balance': body['balance'],
      'pagination': Map<String, dynamic>.from(
        body['pagination'] as Map? ?? const {},
      ),
    };
  }

  Future<Map<String, dynamic>> getContactInfo() async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .get(
          AppConfig.apiUri('app/contact-info'),
          headers: await _publicHeaders(),
        )
        .timeout(_publicRequestTimeout);
    final body = _decodeObject(response);
    _debugLogRequest('GET', 'app/contact-info', stopwatch.elapsed);
    return Map<String, dynamic>.from(body['contact'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getAuthSettings({bool refresh = false}) async {
    if (!refresh && _hasFreshCachedAuthSettings()) {
      return Map<String, dynamic>.from(_cachedAuthSettings!);
    }
    final pendingRequest = _pendingAuthSettingsRequest;
    if (!refresh && pendingRequest != null) {
      return Map<String, dynamic>.from(await pendingRequest);
    }

    final future = _fetchAuthSettings();
    _pendingAuthSettingsRequest = future;
    try {
      return Map<String, dynamic>.from(await future);
    } finally {
      if (identical(_pendingAuthSettingsRequest, future)) {
        _pendingAuthSettingsRequest = null;
      }
    }
  }

  static bool _hasFreshCachedAuthSettings() {
    final cached = _cachedAuthSettings;
    final cachedAt = _cachedAuthSettingsAt;
    if (cached == null || cachedAt == null) {
      return false;
    }
    return DateTime.now().difference(cachedAt) < _authSettingsCacheLifetime;
  }

  Future<Map<String, dynamic>> _fetchAuthSettings() async {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .get(
          AppConfig.apiUri('app/auth-settings'),
          headers: await _publicHeaders(),
        )
        .timeout(_publicRequestTimeout);
    final body = _decodeObject(response);
    final auth = Map<String, dynamic>.from(body['auth'] as Map? ?? const {});
    _cachedAuthSettings = Map<String, dynamic>.from(auth);
    _cachedAuthSettingsAt = DateTime.now();
    _debugLogRequest('GET', 'app/auth-settings', stopwatch.elapsed);
    return auth;
  }

  static void _debugLogRequest(String method, String path, Duration elapsed) {
    assert(() {
      // Keep network timing visible in debug runs without impacting release.
      // ignore: avoid_print
      print('[api] $method $path ${elapsed.inMilliseconds}ms');
      return true;
    }());
  }

  static void invalidateNotificationSummaryCache() {
    _cachedNotificationSummary = null;
    _cachedNotificationSummaryAt = null;
  }

  static void invalidateAuthSettingsCache() {
    _cachedAuthSettings = null;
    _cachedAuthSettingsAt = null;
    _pendingAuthSettingsRequest = null;
  }

  Future<Map<String, dynamic>> getTopupRequestSettings() async {
    final response = await http.get(
      AppConfig.apiUri('app/topup-request-settings'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['topupRequest'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getAdminAffiliateSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/affiliate'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['affiliate'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getTransferSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/transfer'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['transfer'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getFeeSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/fees'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['fees'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getOfflineCardSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/offline-cards'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['offlineCards'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getPermissionTemplates() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/permissions'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getUsagePolicy() async {
    final response = await http.get(
      AppConfig.apiUri('app/usage-policy'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['policy'] as Map? ?? const {});
  }

  Future<List<Map<String, dynamic>>> getSupportedLocations() async {
    final response = await http.get(
      AppConfig.apiUri('app/supported-locations'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> getSupportedLocationsDashboard() async {
    final response = await http.get(
      AppConfig.apiUri('supported-locations/dashboard'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return {
      'locations': List<Map<String, dynamic>>.from(
        (body['locations'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      'myLocations': List<Map<String, dynamic>>.from(
        (body['myLocations'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      'canSubmit': body['canSubmit'] == true,
    };
  }

  Future<List<Map<String, dynamic>>> getAdminSupportedLocations() async {
    final response = await http.get(
      AppConfig.apiUri('admin/supported-locations'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> submitSupportedLocation({
    required String title,
    String displayName = '',
    required String address,
    required String phone,
    String displayPhone = '',
    String displayWhatsapp = '',
    required String type,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('supported-locations/submissions'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title.trim(),
        'displayName': displayName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'displayPhone': displayPhone.trim(),
        'displayWhatsapp': displayWhatsapp.trim(),
        'type': type.trim(),
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['myLocations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> saveMySupportedLocation({
    required String locationId,
    required String title,
    String displayName = '',
    required String address,
    required String phone,
    String displayPhone = '',
    String displayWhatsapp = '',
    required String type,
    required double latitude,
    required double longitude,
    required bool isActive,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('supported-locations/my/$locationId'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title.trim(),
        'displayName': displayName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'displayPhone': displayPhone.trim(),
        'displayWhatsapp': displayWhatsapp.trim(),
        'type': type.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'isActive': isActive,
      }),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['myLocations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> saveAdminSupportedLocation({
    String? locationId,
    required String title,
    required String address,
    required String phone,
    required String type,
    required double latitude,
    required double longitude,
    required bool isActive,
    required int sortOrder,
  }) async {
    final payload = {
      'title': title,
      'address': address,
      'phone': phone,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'isActive': isActive,
      'sortOrder': sortOrder,
    };
    final response = locationId == null
        ? await http.post(
            AppConfig.apiUri('admin/supported-locations'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
        : await http.put(
            AppConfig.apiUri('admin/supported-locations/$locationId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> approveAdminSupportedLocation(
    String locationId,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('admin/supported-locations/$locationId/approve'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> rejectAdminSupportedLocation(
    String locationId, {
    String reason = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/supported-locations/$locationId/reject'),
      headers: await _headers(),
      body: jsonEncode({'reason': reason.trim()}),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> deleteAdminSupportedLocation(
    String locationId,
  ) async {
    final response = await http.delete(
      AppConfig.apiUri('admin/supported-locations/$locationId'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['locations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> getAdminCustomers({
    String query = '',
    int page = 1,
    int perPage = 25,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('admin/customers', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminCustomerTransactions(
    String userId, {
    String locationFilter = 'all',
  }) async {
    final response = await http.get(
      AppConfig.apiUri(
        'admin/customers/$userId/transactions',
        locationFilter == 'all' ? null : {'locationFilter': locationFilter},
      ),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> getSubUsers() async {
    final response = await http.get(
      AppConfig.apiUri('sub-users'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['subUsers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> createSubUser({
    required String fullName,
    required String username,
    required String password,
    required Map<String, bool> permissions,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('sub-users'),
      headers: await _headers(),
      body: jsonEncode({
        'fullName': fullName.trim(),
        'username': username.trim().toLowerCase(),
        'password': password,
        'permissions': permissions,
      }),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['subUsers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> updateSubUser({
    required String subUserId,
    required String fullName,
    String? password,
    required Map<String, bool> permissions,
    bool isDisabled = false,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('sub-users/$subUserId'),
      headers: await _headers(),
      body: jsonEncode({
        'fullName': fullName.trim(),
        if (password != null && password.trim().isNotEmpty)
          'password': password.trim(),
        'permissions': permissions,
        'isDisabled': isDisabled,
      }),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['subUsers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> transferSubUserBalance({
    required String subUserId,
    required String direction,
    required double amount,
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('sub-users/$subUserId/balance-transfer'),
      headers: await _headers(),
      body: jsonEncode({
        'direction': direction,
        'amount': amount,
        'notes': notes.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['currentUser'] is Map) {
      await _authService.cacheCurrentUser(
        Map<String, dynamic>.from(body['currentUser'] as Map),
      );
    }
    return List<Map<String, dynamic>>.from(
      (body['subUsers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> getAdminUserDevices(String userId) async {
    final response = await http.get(
      AppConfig.apiUri('admin/users/$userId/devices'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminUserVerification(String userId) async {
    final response = await http.get(
      AppConfig.apiUri('admin/users/$userId/verification'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> getPendingDeviceAccessRequests() async {
    final response = await http.get(
      AppConfig.apiUri('admin/devices/pending'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingRegistrationRequests() async {
    final response = await http.get(
      AppConfig.apiUri('admin/registrations/pending'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingWithdrawalRequests() async {
    final response = await http.get(
      AppConfig.apiUri('admin/withdrawals/pending'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingTopupRequests() async {
    final response = await http.get(
      AppConfig.apiUri('admin/topup-requests/pending'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingVerificationRequests() async {
    final response = await http.get(
      AppConfig.apiUri('admin/verifications/pending'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> getWithdrawalRequests({
    String? status,
    String query = '',
    int page = 1,
    int perPage = 8,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (status != null && status.trim().isNotEmpty && status.trim() != 'all') {
      params['status'] = status.trim();
    }
    if (query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('admin/withdrawals', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getTopupRequests({
    String? status,
    String query = '',
    int page = 1,
    int perPage = 8,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (status != null && status.trim().isNotEmpty && status.trim() != 'all') {
      params['status'] = status.trim();
    }
    if (query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('admin/topup-requests', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approvePendingDeviceAccessRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/devices/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectPendingDeviceAccessRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/devices/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approvePendingVerificationRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/verifications/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectPendingVerificationRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/verifications/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<void> downloadAdminVerificationFile({
    required String requestId,
    required String fileType,
    required String fileName,
  }) async {
    final response = await http.get(
      adminVerificationFileUri(requestId: requestId, fileType: fileType),
      headers: await _headers(),
    );

    if (response.statusCode >= 400) {
      _decodeObject(response);
    }

    final contentType = response.headers['content-type'] ?? '';
    final extension = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
        ? 'webp'
        : 'jpg';
    final mimeType = extension == 'png'
        ? MimeType.png
        : extension == 'webp'
        ? MimeType.other
        : MimeType.jpeg;

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: response.bodyBytes,
      fileExtension: extension,
      mimeType: mimeType,
    );
  }

  Future<Map<String, dynamic>> approvePendingWithdrawalRequest(
    String requestId, {
    required String approvalImageBase64,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/withdrawals/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({'approvalImageBase64': approvalImageBase64}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approvePendingTopupRequest(
    String requestId, {
    required String approvalImageBase64,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/topup-requests/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({'approvalImageBase64': approvalImageBase64}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectPendingWithdrawalRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/withdrawals/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectPendingTopupRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/topup-requests/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminUserDevicePolicy({
    required String userId,
    required bool allowMultiDevice,
    required int maxDevices,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/users/$userId/device-policy'),
      headers: await _headers(),
      body: jsonEncode({
        'allowMultiDevice': allowMultiDevice,
        'maxDevices': maxDevices,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminUserCardPermissions({
    required String userId,
    required bool canIssueCards,
    required bool canIssueSubShekelCards,
    required bool canIssueHighValueCards,
    required bool canIssuePrivateCards,
    required bool canIssueSingleUseTickets,
    required bool canIssueAppointmentTickets,
    required bool canIssueQueueTickets,
    required bool canReadOwnPrivateCardsOnly,
    required bool canResellCards,
    required bool canRequestCardPrinting,
    required bool canManageCardPrintRequests,
    required bool canOfflineCardScan,
    required bool canManageDebtBook,
    required bool canManageUsers,
    required bool canFinanceTopup,
    required bool canUsePrepaidMultipayCards,
    required bool canAcceptPrepaidMultipayPayments,
    bool canUsePrepaidMultipayNfc = false,
    Map<String, bool> permissionOverrides = const {},
    bool restoreDefaults = false,
  }) async {
    final payload = <String, dynamic>{
      'canIssueCards': canIssueCards,
      'canIssueSubShekelCards': canIssueSubShekelCards,
      'canIssueHighValueCards': canIssueHighValueCards,
      'canIssuePrivateCards': canIssuePrivateCards,
      'canIssueSingleUseTickets': canIssueSingleUseTickets,
      'canIssueAppointmentTickets': canIssueAppointmentTickets,
      'canIssueQueueTickets': canIssueQueueTickets,
      'canReadOwnPrivateCardsOnly': canReadOwnPrivateCardsOnly,
      'canResellCards': canResellCards,
      'canRequestCardPrinting': canRequestCardPrinting,
      'canManageCardPrintRequests': canManageCardPrintRequests,
      'canOfflineCardScan': canOfflineCardScan,
      'canManageDebtBook': canManageDebtBook,
      'canManageUsers': canManageUsers,
      'canFinanceTopup': canFinanceTopup,
      'canUsePrepaidMultipayCards': canUsePrepaidMultipayCards,
      'canAcceptPrepaidMultipayPayments': canAcceptPrepaidMultipayPayments,
      'canUsePrepaidMultipayNfc': canUsePrepaidMultipayNfc,
      ...permissionOverrides,
      if (restoreDefaults) 'restoreDefaults': true,
    };
    final response = await http.put(
      AppConfig.apiUri('admin/users/$userId/card-permissions'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getDebtBookSnapshot() async {
    final response = await http.get(
      AppConfig.apiUri('debt-book/snapshot'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> syncDebtBook(
    List<Map<String, dynamic>> operations,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('debt-book/sync'),
      headers: await _headers(),
      body: jsonEncode({'operations': operations}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminUserAccountControls({
    required String userId,
    String? businessName,
    String? fullName,
    String? username,
    String? whatsapp,
    String? email,
    String? address,
    String? nationalId,
    String? birthDate,
    String? referralPhone,
    String? printLogoBase64,
    bool removePrintLogo = false,
    required bool isDisabled,
    required String transferVerificationStatus,
    required String role,
    required double printingDebtLimit,
    double? customTopupFeePercent,
    double? customWithdrawFeePercent,
    double? customTransferFeePercent,
    double? customCardRedeemFeePercent,
    double? customCardResellFeePercent,
    double? customCardPrintRequestFeePercent,
    int? customCardScanLimit,
    bool cardScanLimitExempt = false,
    bool resetCardScanCounter = false,
    bool cardAutoRedeemOnScanForced = false,
  }) async {
    final payload = <String, dynamic>{
      'removePrintLogo': removePrintLogo,
      'isDisabled': isDisabled,
      'transferVerificationStatus': transferVerificationStatus,
      'role': role,
      'printingDebtLimit': printingDebtLimit,
      'customTopupFeePercent': customTopupFeePercent,
      'customWithdrawFeePercent': customWithdrawFeePercent,
      'customTransferFeePercent': customTransferFeePercent,
      'customCardRedeemFeePercent': customCardRedeemFeePercent,
      'customCardResellFeePercent': customCardResellFeePercent,
      'customCardPrintRequestFeePercent': customCardPrintRequestFeePercent,
      'customCardScanLimit': customCardScanLimit,
      'cardScanLimitExempt': cardScanLimitExempt,
      'resetCardScanCounter': resetCardScanCounter,
      'cardAutoRedeemOnScanForced': cardAutoRedeemOnScanForced,
    };
    if (businessName != null) payload['businessName'] = businessName;
    if (fullName != null) payload['fullName'] = fullName;
    if (username != null) payload['username'] = username;
    if (whatsapp != null) payload['whatsapp'] = whatsapp;
    if (email != null) payload['email'] = email;
    if (address != null) payload['address'] = address;
    if (nationalId != null) payload['nationalId'] = nationalId;
    if (birthDate != null) payload['birthDate'] = birthDate;
    if (referralPhone != null) payload['referralPhone'] = referralPhone;
    if (printLogoBase64 != null) payload['printLogoBase64'] = printLogoBase64;

    final response = await http.put(
      AppConfig.apiUri('admin/users/$userId/account-controls'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getCardScanLimitSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/card-scan-limits'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(
      body['cardScanLimits'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> updateCardScanLimitSettings({
    required int defaultLimit,
    required int restrictedLimit,
    required int basicLimit,
    required int verifiedLimit,
    required int driverLimit,
    required int marketerLimit,
    required int supportLimit,
    required int financeLimit,
    required int adminLimit,
    required bool autoRedeemGlobalForced,
    required int withoutRedeemChargeEvery,
    required double withoutRedeemChargeAmount,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/card-scan-limits'),
      headers: await _headers(),
      body: jsonEncode({
        'defaultLimit': defaultLimit,
        'restrictedLimit': restrictedLimit,
        'basicLimit': basicLimit,
        'verifiedLimit': verifiedLimit,
        'driverLimit': driverLimit,
        'marketerLimit': marketerLimit,
        'supportLimit': supportLimit,
        'financeLimit': financeLimit,
        'adminLimit': adminLimit,
        'autoRedeemGlobalForced': autoRedeemGlobalForced,
        'withoutRedeemChargeEvery': withoutRedeemChargeEvery,
        'withoutRedeemChargeAmount': withoutRedeemChargeAmount,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateFeeSettings({
    required double walletTopupPercent,
    required double walletTransferPercent,
    required double cardRedeemPercent,
    required double cardResellPercent,
    required double cardPrintRequestPercent,
    required double withdrawPercent,
    required double standardCardIssueCost,
    required double deliveryCardIssueCost,
    required double privateCardIssueCost,
    required double singleUseTicketIssueCost,
    required double appointmentTicketIssueCost,
    required double queueTicketIssueCost,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/fees'),
      headers: await _headers(),
      body: jsonEncode({
        'walletTopupPercent': walletTopupPercent,
        'walletTransferPercent': walletTransferPercent,
        'cardRedeemPercent': cardRedeemPercent,
        'cardResellPercent': cardResellPercent,
        'cardPrintRequestPercent': cardPrintRequestPercent,
        'withdrawPercent': withdrawPercent,
        'standardCardIssueCost': standardCardIssueCost,
        'deliveryCardIssueCost': deliveryCardIssueCost,
        'privateCardIssueCost': privateCardIssueCost,
        'singleUseTicketIssueCost': singleUseTicketIssueCost,
        'appointmentTicketIssueCost': appointmentTicketIssueCost,
        'queueTicketIssueCost': queueTicketIssueCost,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updatePermissionTemplates({
    required Map<String, dynamic> templates,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/permissions'),
      headers: await _headers(),
      body: jsonEncode({'templates': templates}),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> getMyCardPrintRequests() async {
    final response = await http.get(
      AppConfig.apiUri('cards/print-requests'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['requests'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> requestCardPrint({
    required double value,
    required int quantity,
    required String cardType,
    String notes = '',
    List<String> allowedUserIds = const [],
    List<String> allowedUserPhones = const [],
    String? validFrom,
    String? validUntil,
    Map<String, dynamic> cardDetails = const {},
  }) async {
    final response = await http.post(
      AppConfig.apiUri('cards/print-requests'),
      headers: await _headers(),
      body: jsonEncode({
        'value': value,
        'quantity': quantity,
        'cardType': cardType,
        'notes': notes.trim(),
        if (allowedUserIds.isNotEmpty) 'allowedUserIds': allowedUserIds,
        if (allowedUserPhones.isNotEmpty)
          'allowedUserPhones': allowedUserPhones,
        if ((validFrom ?? '').trim().isNotEmpty) 'validFrom': validFrom!.trim(),
        if ((validUntil ?? '').trim().isNotEmpty)
          'validUntil': validUntil!.trim(),
        if (cardDetails.isNotEmpty) 'cardDetails': cardDetails,
      }),
    );
    final body = _decodeObject(response);
    if (body['user'] is Map<String, dynamic>) {
      await _authService.cacheCurrentUser(
        Map<String, dynamic>.from(body['user'] as Map<String, dynamic>),
      );
    } else if (body['user'] is Map) {
      await _authService.cacheCurrentUser(
        Map<String, dynamic>.from(body['user'] as Map),
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> getCardPrintRequests({
    String status = 'all',
    String query = '',
    int page = 1,
    int perPage = 8,
  }) async {
    final params = <String, String>{
      'status': status,
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('admin/card-print-requests', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> createAdminCardPrintRequest({
    required String userId,
    required double value,
    required int quantity,
    required String cardType,
    String notes = '',
    List<String> allowedUserIds = const [],
    List<String> allowedUserPhones = const [],
    String? validFrom,
    String? validUntil,
    Map<String, dynamic> cardDetails = const {},
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests'),
      headers: await _headers(),
      body: jsonEncode({
        'userId': userId,
        'value': value,
        'quantity': quantity,
        'cardType': cardType,
        'notes': notes.trim(),
        if (allowedUserIds.isNotEmpty) 'allowedUserIds': allowedUserIds,
        if (allowedUserPhones.isNotEmpty)
          'allowedUserPhones': allowedUserPhones,
        if ((validFrom ?? '').trim().isNotEmpty) 'validFrom': validFrom!.trim(),
        if ((validUntil ?? '').trim().isNotEmpty)
          'validUntil': validUntil!.trim(),
        if (cardDetails.isNotEmpty) 'cardDetails': cardDetails,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approveCardPrintRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> startCardPrintRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/start'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> readyCardPrintRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/ready'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> completeCardPrintRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/complete'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> markCardPrintRequestPrinted(
    String requestId,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/printed'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> overrideCardPrintRequestStatus(
    String requestId, {
    required String status,
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/override-status'),
      headers: await _headers(),
      body: jsonEncode({
        'status': status.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectCardPrintRequest(
    String requestId, {
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/card-print-requests/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> createAdminUser({
    required String username,
    required String whatsapp,
    String fullName = '',
    String password = '',
    String countryCode = '970',
    String deliveryMethod = 'whatsapp',
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedWhatsapp = PhoneNumberService.normalize(
      input: whatsapp.trim(),
      defaultDialCode: countryCode.trim(),
    );

    final response = await http.post(
      AppConfig.apiUri('admin/users'),
      headers: await _headers(),
      body: jsonEncode({
        'username': normalizedUsername,
        'whatsapp': normalizedWhatsapp,
        'fullName': fullName.trim(),
        'password': password,
        'countryCode': countryCode.trim(),
        'deliveryMethod': deliveryMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> resendAdminUserAccountDetails({
    required String userId,
    bool regeneratePassword = true,
    String deliveryMethod = 'whatsapp',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users/$userId/resend-account-details'),
      headers: await _headers(),
      body: jsonEncode({
        'regeneratePassword': regeneratePassword,
        'deliveryMethod': deliveryMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> sendAdminUserOtp({
    required String userId,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('admin/users/$userId/send-otp'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> settleAdminUserPrintingDebt({
    required String userId,
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users/$userId/settle-printing-debt'),
      headers: await _headers(),
      body: jsonEncode({if (notes.trim().isNotEmpty) 'notes': notes.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminAuthSettings({
    required bool registrationEnabled,
    required bool loginOtpRequired,
    required bool registrationWhatsappVerificationRequired,
    required String whatsappUsageMode,
    required String messageDeliveryPriority,
    required bool adminAlertsWhatsappEnabled,
    required bool adminAlertsSmsEnabled,
    required String minSupportedVersion,
    required String latestVersion,
    required String androidStoreUrl,
    required String iosStoreUrl,
    required String webStoreUrl,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/auth'),
      headers: await _headers(),
      body: jsonEncode({
        'registrationEnabled': registrationEnabled,
        'loginOtpRequired': loginOtpRequired,
        'registrationWhatsappVerificationRequired':
            registrationWhatsappVerificationRequired,
        'whatsappUsageMode': whatsappUsageMode.trim(),
        'messageDeliveryPriority': messageDeliveryPriority.trim(),
        'adminAlertsWhatsappEnabled': adminAlertsWhatsappEnabled,
        'adminAlertsSmsEnabled': adminAlertsSmsEnabled,
        'minSupportedVersion': minSupportedVersion.trim(),
        'latestVersion': latestVersion.trim(),
        'androidStoreUrl': androidStoreUrl.trim(),
        'iosStoreUrl': iosStoreUrl.trim(),
        'webStoreUrl': webStoreUrl.trim(),
      }),
    );
    final body = _decodeObject(response);
    final auth = body['auth'];
    if (auth is Map) {
      _cachedAuthSettings = Map<String, dynamic>.from(auth);
      _cachedAuthSettingsAt = DateTime.now();
    } else {
      invalidateAuthSettingsCache();
    }
    return body;
  }

  Future<Map<String, dynamic>> updateAdminTransferSettings({
    required double unverifiedTransferLimit,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/transfer'),
      headers: await _headers(),
      body: jsonEncode({'unverifiedTransferLimit': unverifiedTransferLimit}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminOfflineCardSettings({
    required double maxPendingAmount,
    required int maxPendingCount,
    required int maxCachedCards,
    required int syncIntervalMinutes,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/offline-cards'),
      headers: await _headers(),
      body: jsonEncode({
        'maxPendingAmount': maxPendingAmount,
        'maxPendingCount': maxPendingCount,
        'maxCachedCards': maxCachedCards,
        'syncIntervalMinutes': syncIntervalMinutes,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminTopupRequestSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/topup-request'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['topupRequest'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateAdminTopupRequestSettings({
    required bool enabled,
    required String instructions,
    double? minAmount,
    double? maxAmount,
  }) async {
    final payload = <String, dynamic>{
      'enabled': enabled,
      'instructions': instructions.trim(),
    };
    if (minAmount != null) {
      payload['minAmount'] = minAmount;
    }
    if (maxAmount != null) {
      payload['maxAmount'] = maxAmount;
    }
    final response = await http.put(
      AppConfig.apiUri('admin/settings/topup-request'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminWithdrawalRequestSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/withdrawal-request'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(
      body['withdrawalRequest'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> updateAdminWithdrawalRequestSettings({
    required bool enabled,
    required String instructions,
    required double minAmount,
    required double maxAmount,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/withdrawal-request'),
      headers: await _headers(),
      body: jsonEncode({
        'enabled': enabled,
        'instructions': instructions.trim(),
        'minAmount': minAmount,
        'maxAmount': maxAmount,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getCardQuantityLimitSettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/card-quantity-limits'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(
      body['cardQuantityLimits'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> updateCardQuantityLimitSettings({
    required int defaultLimit,
    required int restrictedLimit,
    required int basicLimit,
    required int verifiedLimit,
    required int driverLimit,
    required int marketerLimit,
    required int supportLimit,
    required int financeLimit,
    required int adminLimit,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/card-quantity-limits'),
      headers: await _headers(),
      body: jsonEncode({
        'defaultLimit': defaultLimit,
        'restrictedLimit': restrictedLimit,
        'basicLimit': basicLimit,
        'verifiedLimit': verifiedLimit,
        'driverLimit': driverLimit,
        'marketerLimit': marketerLimit,
        'supportLimit': supportLimit,
        'financeLimit': financeLimit,
        'adminLimit': adminLimit,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminAffiliateSettings({
    required bool enabled,
    required double rewardAmount,
    required double firstTopupMinAmount,
    required double marketerDebtLimit,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/affiliate'),
      headers: await _headers(),
      body: jsonEncode({
        'enabled': enabled,
        'rewardAmount': rewardAmount,
        'firstTopupMinAmount': firstTopupMinAmount,
        'marketerDebtLimit': marketerDebtLimit,
      }),
    );
    return _decodeObject(response);
  }

  Future<List<Map<String, dynamic>>> getAdminTopupPaymentMethods() async {
    final response = await http.get(
      AppConfig.apiUri('admin/topup-payment-methods'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> saveAdminTopupPaymentMethod({
    String? methodId,
    required String title,
    required String description,
    required String imageUrl,
    required String accountNumber,
    required bool isActive,
    required int sortOrder,
  }) async {
    final payload = {
      'title': title.trim(),
      'description': description.trim(),
      'imageUrl': imageUrl.trim(),
      'accountNumber': accountNumber.trim(),
      'isActive': isActive,
      'sortOrder': sortOrder,
    };
    final response = methodId == null
        ? await http.post(
            AppConfig.apiUri('admin/topup-payment-methods'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
        : await http.put(
            AppConfig.apiUri('admin/topup-payment-methods/$methodId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> deleteAdminTopupPaymentMethod(
    String methodId,
  ) async {
    final response = await http.delete(
      AppConfig.apiUri('admin/topup-payment-methods/$methodId'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getAdminWithdrawalMethods() async {
    final response = await http.get(
      AppConfig.apiUri('admin/withdrawal-methods'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> saveAdminWithdrawalMethod({
    String? methodId,
    required String code,
    required String title,
    required String description,
    required String accountLabel,
    required bool requiresBankName,
    required bool isActive,
    required int sortOrder,
  }) async {
    final payload = {
      'code': code.trim(),
      'title': title.trim(),
      'description': description.trim(),
      'accountLabel': accountLabel.trim(),
      'requiresBankName': requiresBankName,
      'isActive': isActive,
      'sortOrder': sortOrder,
    };
    final response = methodId == null
        ? await http.post(
            AppConfig.apiUri('admin/withdrawal-methods'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
        : await http.put(
            AppConfig.apiUri('admin/withdrawal-methods/$methodId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> deleteAdminWithdrawalMethod(
    String methodId,
  ) async {
    final response = await http.delete(
      AppConfig.apiUri('admin/withdrawal-methods/$methodId'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<Map<String, dynamic>>.from(
      (body['methods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<Map<String, dynamic>> updatePrintLogo({
    String? logoBase64,
    bool remove = false,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/profile/print-logo'),
      headers: await _headers(),
      body: jsonEncode({'logoBase64': logoBase64, 'remove': remove}),
    );
    final body = _decodeObject(response);
    await _syncCurrentUserFromPayload(body);
    return body;
  }

  Future<Map<String, dynamic>> updateAdminContactSettings({
    required String title,
    required String supportWhatsapp,
    required String supportEmail,
    required String address,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/contact'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'supportWhatsapp': supportWhatsapp,
        'supportEmail': supportEmail,
        'address': address,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminUsagePolicy({
    required String title,
    required String content,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/usage-policy'),
      headers: await _headers(),
      body: jsonEncode({'title': title, 'content': content}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateContactInfo({
    required String title,
    required String supportWhatsapp,
    required String supportEmail,
    required String address,
  }) {
    return updateAdminContactSettings(
      title: title,
      supportWhatsapp: supportWhatsapp,
      supportEmail: supportEmail,
      address: address,
    );
  }

  Future<Map<String, dynamic>> updateAuthSettings({
    required bool registrationEnabled,
    required bool loginOtpRequired,
    required bool registrationWhatsappVerificationRequired,
    required String whatsappUsageMode,
    required String messageDeliveryPriority,
    required bool adminAlertsWhatsappEnabled,
    required bool adminAlertsSmsEnabled,
    required String minSupportedVersion,
    required String latestVersion,
    required String androidStoreUrl,
    required String iosStoreUrl,
    required String webStoreUrl,
  }) {
    return updateAdminAuthSettings(
      registrationEnabled: registrationEnabled,
      loginOtpRequired: loginOtpRequired,
      registrationWhatsappVerificationRequired:
          registrationWhatsappVerificationRequired,
      whatsappUsageMode: whatsappUsageMode,
      messageDeliveryPriority: messageDeliveryPriority,
      adminAlertsWhatsappEnabled: adminAlertsWhatsappEnabled,
      adminAlertsSmsEnabled: adminAlertsSmsEnabled,
      minSupportedVersion: minSupportedVersion,
      latestVersion: latestVersion,
      androidStoreUrl: androidStoreUrl,
      iosStoreUrl: iosStoreUrl,
      webStoreUrl: webStoreUrl,
    );
  }

  Future<Map<String, dynamic>> getAdminMessageGatewayDashboard() async {
    final response = await http.get(
      AppConfig.apiUri('admin/message-gateway/dashboard'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> toggleWhatsAppGatewayChannel({
    required String channelKey,
    required bool enabled,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/message-gateway/whatsapp/$channelKey/toggle'),
      headers: await _headers(),
      body: jsonEncode({'enabled': enabled}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> testWhatsAppGatewayChannel({
    required String channelKey,
    String phone = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/message-gateway/whatsapp/$channelKey/test'),
      headers: await _headers(),
      body: jsonEncode({
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> testSmsGateway({String phone = ''}) async {
    final response = await http.post(
      AppConfig.apiUri('admin/message-gateway/sms/test'),
      headers: await _headers(),
      body: jsonEncode({
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateTransferSettings({
    required double unverifiedTransferLimit,
  }) {
    return updateAdminTransferSettings(
      unverifiedTransferLimit: unverifiedTransferLimit,
    );
  }

  Future<Map<String, dynamic>> updateUsagePolicy({
    required String title,
    required String content,
  }) {
    return updateAdminUsagePolicy(title: title, content: content);
  }

  Future<Map<String, dynamic>> updateAffiliateSettings({
    required bool enabled,
    required double rewardAmount,
    required double firstTopupMinAmount,
    required double marketerDebtLimit,
  }) {
    return updateAdminAffiliateSettings(
      enabled: enabled,
      rewardAmount: rewardAmount,
      firstTopupMinAmount: firstTopupMinAmount,
      marketerDebtLimit: marketerDebtLimit,
    );
  }

  Future<Map<String, dynamic>> reviewDeviceAccessRequest(
    String requestId, {
    required bool approve,
    String notes = '',
  }) {
    return approve
        ? approvePendingDeviceAccessRequest(requestId, notes: notes)
        : rejectPendingDeviceAccessRequest(requestId, notes: notes);
  }

  Future<Map<String, dynamic>> reviewWithdrawalRequest(
    String requestId, {
    required bool approve,
    String notes = '',
    String approvalImageBase64 = '',
  }) {
    return approve
        ? approvePendingWithdrawalRequest(
            requestId,
            approvalImageBase64: approvalImageBase64,
          )
        : rejectPendingWithdrawalRequest(requestId, notes: notes);
  }

  Future<Map<String, dynamic>> reviewTopupRequest(
    String requestId, {
    required bool approve,
    String notes = '',
    String approvalImageBase64 = '',
  }) {
    return approve
        ? approvePendingTopupRequest(
            requestId,
            approvalImageBase64: approvalImageBase64,
          )
        : rejectPendingTopupRequest(requestId, notes: notes);
  }

  Future<Map<String, dynamic>> releaseAdminUserDevice({
    required String userId,
    required String deviceRecordId,
  }) async {
    final response = await http.delete(
      AppConfig.apiUri('admin/users/$userId/devices/$deviceRecordId'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> releaseAllAdminUserDevices({
    required String userId,
  }) async {
    final response = await http.delete(
      AppConfig.apiUri('admin/users/$userId/devices'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getMyDevices() async {
    final response = await http.get(
      AppConfig.apiUri('auth/devices'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> releaseMyDevice({
    required String deviceRecordId,
  }) async {
    final response = await http.delete(
      AppConfig.apiUri('auth/devices/$deviceRecordId'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<OtpRequestResult> requestTransferSecurityOtp() async {
    final response = await http.post(
      AppConfig.apiUri('auth/transfer-security/request-otp'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return OtpRequestResult(
      message: body['message']?.toString(),
      whatsapp: body['whatsapp']?.toString(),
      debugOtpCode: body['debugOtpCode']?.toString(),
    );
  }

  Future<void> exportCustomerTransactionsCsv({
    required Map<String, dynamic> customer,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(
      '\uFEFFid,type,amount,fee,description,location_status,nearest_branch,created_at',
    );
    for (final item in transactions) {
      final description = (item['description']?.toString() ?? '').replaceAll(
        '"',
        '""',
      );
      final metadata = Map<String, dynamic>.from(
        item['metadata'] as Map? ?? const {},
      );
      final audit = Map<String, dynamic>.from(
        metadata['locationAudit'] as Map? ?? const {},
      );
      final locationStatus = audit.isEmpty
          ? ''
          : (audit['isNearSupportedBranch'] == true
                ? 'near_branch'
                : 'outside_branches');
      final nearestBranch =
          (audit['nearestBranch'] as Map?)?['title']?.toString().replaceAll(
            '"',
            '""',
          ) ??
          '';
      buffer.writeln(
        '${item['id'] ?? ''},${item['type'] ?? ''},${item['amount'] ?? ''},${item['fee'] ?? ''},"$description",$locationStatus,"$nearestBranch",${item['createdAt'] ?? ''}',
      );
    }
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final fileName =
        'customer_${customer['username'] ?? customer['id']}_transactions';
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  Future<void> exportMyTransactionsCsv({
    required List<Map<String, dynamic>> transactions,
  }) async {
    final user = await _authService.currentUser();
    await exportCustomerTransactionsCsv(
      customer: user ?? const <String, dynamic>{'username': 'my'},
      transactions: transactions,
    );
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final response = await http.get(
      AppConfig.apiUri('users', {'q': query}),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return List<dynamic>.from(
      body['users'] as List? ?? const [],
    ).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> lookupUserByPhone({
    required String phone,
    required String countryCode,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('users/lookup-by-phone', {
        'phone': phone,
        'countryCode': countryCode,
      }),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> topUpUser({
    required String userId,
    required double amount,
    String notes = '',
    String? otpCode,
    String? localAuthMethod,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{
      'userId': userId,
      'amount': amount,
      'notes': notes,
    };
    if (location != null) {
      payload['location'] = location;
    }
    if (otpCode != null && otpCode.trim().isNotEmpty) {
      payload['otpCode'] = otpCode.trim();
    } else if (localAuthMethod != null && localAuthMethod.trim().isNotEmpty) {
      payload['localAuthMethod'] = localAuthMethod.trim();
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/topup'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> addAdminUserBalance({
    required String userId,
    required double amount,
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users/$userId/add-balance'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount, 'notes': notes}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> deductAdminUserBalance({
    required String userId,
    required double amount,
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users/$userId/deduct-balance'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount, 'notes': notes}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> transferBalance({
    required String recipientId,
    required double amount,
    String notes = '',
    String? otpCode,
    String? localAuthMethod,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{
      'recipientId': recipientId,
      'amount': amount,
      'notes': notes,
    };
    if (location != null) {
      payload['location'] = location;
    }
    if (otpCode != null && otpCode.trim().isNotEmpty) {
      payload['otpCode'] = otpCode.trim();
    } else if (localAuthMethod != null && localAuthMethod.trim().isNotEmpty) {
      payload['localAuthMethod'] = localAuthMethod.trim();
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/transfer'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    return body;
  }

  Future<Map<String, dynamic>> createTemporaryTransferCode({
    required double amount,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final payload = <String, dynamic>{'amount': amount};
    if (otpCode != null && otpCode.trim().isNotEmpty) {
      payload['otpCode'] = otpCode.trim();
    } else if (localAuthMethod != null && localAuthMethod.trim().isNotEmpty) {
      payload['localAuthMethod'] = localAuthMethod.trim();
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/temporary-transfer-code'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> approvePendingRegistrationRequest(
    String requestId, {
    bool allowUnverifiedWhatsapp = false,
    String deliveryMethod = 'whatsapp',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/registrations/$requestId/approve'),
      headers: await _headers(),
      body: jsonEncode({
        'allowUnverifiedWhatsapp': allowUnverifiedWhatsapp,
        'deliveryMethod': deliveryMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> confirmPendingRegistrationWithoutOtp(
    String requestId,
  ) async {
    final response = await http.post(
      AppConfig.apiUri('admin/registrations/$requestId/confirm-without-otp'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> rejectPendingRegistrationRequest(
    String requestId, {
    String reason = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/registrations/$requestId/reject'),
      headers: await _headers(),
      body: jsonEncode({'rejectionReason': reason.trim()}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> prefetchTemporaryTransferCodes({
    required String deviceId,
    int count = 5,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('wallet/temporary-transfer-code/prefetch'),
      headers: await _headers(),
      body: jsonEncode({'deviceId': deviceId, 'count': count}),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> redeemTemporaryTransferCode({
    required String payload,
    Map<String, dynamic>? location,
  }) async {
    final requestPayload = <String, dynamic>{'payload': payload};
    if (location != null) {
      requestPayload['location'] = location;
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/temporary-transfer-code/redeem'),
      headers: await _headers(),
      body: jsonEncode(requestPayload),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    return body;
  }

  Future<Map<String, dynamic>> requestWithdrawal({
    required double amount,
    required String destinationType,
    required String destinationAccount,
    required String accountHolderName,
    String? bankName,
    String notes = '',
    required bool agreementAccepted,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{
      'amount': amount,
      'destinationType': destinationType,
      'destinationAccount': destinationAccount,
      'accountHolderName': accountHolderName,
      'notes': notes,
      'agreementAccepted': agreementAccepted,
    };
    if (bankName != null && bankName.trim().isNotEmpty) {
      payload['bankName'] = bankName.trim();
    }
    if (location != null) {
      payload['location'] = location;
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/withdrawal'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    return body;
  }

  Future<Map<String, dynamic>> getWithdrawalRequestOptions() async {
    final response = await http.get(
      AppConfig.apiUri('wallet/withdrawal/options'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getTopupRequestOptions() async {
    final response = await http.get(
      AppConfig.apiUri('wallet/topup-request/options'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAffiliateDashboard() async {
    final response = await http.get(
      AppConfig.apiUri('affiliate/dashboard'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> requestTopup({
    required double amount,
    required String paymentMethodId,
    String senderName = '',
    String senderPhone = '',
    String transferReference = '',
    String? transferredAt,
    String notes = '',
  }) async {
    final payload = <String, dynamic>{
      'amount': amount,
      'paymentMethodId': paymentMethodId,
      'senderName': senderName.trim(),
      'senderPhone': senderPhone.trim(),
      'transferReference': transferReference.trim(),
      'notes': notes.trim(),
    };
    if (transferredAt != null && transferredAt.trim().isNotEmpty) {
      payload['transferredAt'] = transferredAt.trim();
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/topup-request'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getVerificationStatus() async {
    final response = await http.get(
      AppConfig.apiUri('auth/verification'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> submitVerification({
    required String identityDocumentBase64,
    required String selfieImageBase64,
    required String fullName,
    required String nationalId,
    required String birthDate,
    String requestedRole = 'verified_member',
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/verification'),
      headers: await _headers(),
      body: jsonEncode({
        'identityDocumentBase64': identityDocumentBase64,
        'selfieImageBase64': selfieImageBase64,
        'fullName': fullName.trim(),
        'nationalId': nationalId.trim(),
        'birthDate': birthDate.trim(),
        'requestedRole': requestedRole,
        'notes': notes,
      }),
    );
    final body = _decodeObject(response);
    final nextStatus = body['status']?.toString();
    await _authService.patchCurrentUser({
      if (nextStatus != null && nextStatus.isNotEmpty)
        'transferVerificationStatus': nextStatus,
    });
    return body;
  }

  Future<List<VirtualCard>> issueCards({
    required double value,
    required int quantity,
    List<String> allowedUserIds = const [],
    List<String> allowedUserPhones = const [],
    String visibilityScope = 'general',
    String cardType = 'standard',
    Map<String, dynamic>? printDesign,
    String? validFrom,
    String? validUntil,
    Map<String, dynamic>? cardDetails,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final payload = <String, dynamic>{
      'value': value,
      'quantity': quantity,
      'cardType': cardType,
      if (allowedUserIds.isNotEmpty) 'allowedUserIds': allowedUserIds,
      if (allowedUserPhones.isNotEmpty) 'allowedUserPhones': allowedUserPhones,
      if (visibilityScope.trim().isNotEmpty) 'visibilityScope': visibilityScope,
      ...?printDesign == null ? null : {'printDesign': printDesign},
      if (validFrom != null && validFrom.trim().isNotEmpty)
        'validFrom': validFrom,
      if (validUntil != null && validUntil.trim().isNotEmpty)
        'validUntil': validUntil,
      ...?cardDetails == null ? null : {'cardDetails': cardDetails},
      if (otpCode != null && otpCode.trim().isNotEmpty)
        'otpCode': otpCode.trim(),
      if (otpCode == null || otpCode.trim().isEmpty)
        if (localAuthMethod != null && localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
    };
    final response = await http.post(
      AppConfig.apiUri('cards/issue'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _authService.patchCurrentUser({
      if (body['balance'] is num)
        'balance': (body['balance'] as num).toDouble(),
      if (body['availablePrintingBalance'] is num)
        'availablePrintingBalance': (body['availablePrintingBalance'] as num)
            .toDouble(),
    });
    final rawCards = List<dynamic>.from(body['cards'] as List? ?? const []);
    return rawCards
        .map((item) => _cardFromApi(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<VirtualCard>> issueTrialCards({
    required List<Map<String, dynamic>> items,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final payload = <String, dynamic>{
      'items': items,
      if (otpCode != null && otpCode.trim().isNotEmpty)
        'otpCode': otpCode.trim(),
      if (otpCode == null || otpCode.trim().isEmpty)
        if (localAuthMethod != null && localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
    };
    final response = await http.post(
      AppConfig.apiUri('cards/trial-issue'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _authService.patchCurrentUser({
      if (body['balance'] is num)
        'balance': (body['balance'] as num).toDouble(),
      if (body['trialCardsLimit'] is num)
        'trialCardsLimit': (body['trialCardsLimit'] as num).toDouble(),
      if (body['trialCardsOutstandingAmount'] is num)
        'trialCardsOutstandingAmount':
            (body['trialCardsOutstandingAmount'] as num).toDouble(),
      if (body['trialCardsRemainingAmount'] is num)
        'trialCardsAvailableAmount': (body['trialCardsRemainingAmount'] as num)
            .toDouble(),
    });
    final rawCards = List<dynamic>.from(body['cards'] as List? ?? const []);
    return rawCards
        .map((item) => _cardFromApi(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> getMyCards({
    String? status,
    int page = 1,
    int perPage = 12,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('cards', query.isEmpty ? null : query),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    final rawCards = List<dynamic>.from(body['cards'] as List? ?? const []);
    return {
      'cards': rawCards
          .map((item) => _cardFromApi(Map<String, dynamic>.from(item as Map)))
          .toList(),
      'pagination': Map<String, dynamic>.from(
        body['pagination'] as Map? ?? const {},
      ),
    };
  }

  Future<Map<String, dynamic>> getAdminCards({
    String? status,
    String creator = '',
    double? valueMin,
    double? valueMax,
    String issuedFrom = '',
    String issuedTo = '',
    int page = 1,
    int perPage = 24,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (status != null && status.trim().isNotEmpty && status.trim() != 'all') {
      query['status'] = status.trim();
    }
    if (creator.trim().isNotEmpty) {
      query['creator'] = creator.trim();
    }
    if (valueMin != null) {
      query['valueMin'] = valueMin.toString();
    }
    if (valueMax != null) {
      query['valueMax'] = valueMax.toString();
    }
    if (issuedFrom.trim().isNotEmpty) {
      query['issuedFrom'] = issuedFrom.trim();
    }
    if (issuedTo.trim().isNotEmpty) {
      query['issuedTo'] = issuedTo.trim();
    }
    final response = await http.get(
      AppConfig.apiUri('admin/cards', query),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    final rawCards = List<dynamic>.from(body['cards'] as List? ?? const []);
    return {
      'cards': rawCards
          .map((item) => _cardFromApi(Map<String, dynamic>.from(item as Map)))
          .toList(),
      'pagination': Map<String, dynamic>.from(
        body['pagination'] as Map? ?? const {},
      ),
      'filters': Map<String, dynamic>.from(body['filters'] as Map? ?? const {}),
    };
  }

  Future<Map<String, dynamic>> getOfflineCardCache() async {
    final response = await http.get(
      AppConfig.apiUri('cards/offline-cache'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    final cards = List<dynamic>.from(body['cards'] as List? ?? const []);
    return {
      ...body,
      'cards': cards
          .map((item) => _cardFromApi(Map<String, dynamic>.from(item as Map)))
          .toList(),
      'settings': Map<String, dynamic>.from(
        body['settings'] as Map? ?? const {},
      ),
    };
  }

  Future<void> deleteCard(String cardId) async {
    final response = await http.delete(
      AppConfig.apiUri('cards/$cardId'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    await _authService.patchCurrentUser({
      if (body['trialCardsLimit'] is num)
        'trialCardsLimit': (body['trialCardsLimit'] as num).toDouble(),
      if (body['trialCardsOutstandingAmount'] is num)
        'trialCardsOutstandingAmount':
            (body['trialCardsOutstandingAmount'] as num).toDouble(),
      if (body['trialCardsRemainingAmount'] is num)
        'trialCardsAvailableAmount': (body['trialCardsRemainingAmount'] as num)
            .toDouble(),
    });
  }

  Future<VirtualCard?> getCardByBarcode(
    String barcode, {
    bool autoRedeem = false,
    Map<String, dynamic>? location,
  }) async {
    lastCardLookupAutoRedeemed = false;
    final query = <String, String>{};
    if (autoRedeem) {
      query['autoRedeem'] = '1';
    }
    if (location != null) {
      // Server accepts either `location[lat]=..` style or a json string; we use json for simplicity.
      query['location'] = jsonEncode(location);
    }
    final response = await http.get(
      AppConfig.apiUri('cards/$barcode', query.isEmpty ? null : query),
      headers: await _headers(),
    );
    if (response.statusCode == 404) {
      return null;
    }
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    if (body['user'] is Map) {
      await _authService.patchCurrentUser(
        Map<String, dynamic>.from(body['user'] as Map),
      );
    }
    lastCardLookupAutoRedeemed = body['autoRedeemed'] == true;
    return _cardFromApi(Map<String, dynamic>.from(body['card'] as Map));
  }

  Future<Map<String, dynamic>> getAdminCardScanReportUsers({
    String scope = 'private',
    String? from,
    String? to,
    int page = 1,
    int perPage = 12,
  }) async {
    final params = <String, String>{
      'scope': scope,
      'page': page.toString(),
      'perPage': perPage.toString(),
    };
    if (from != null && from.trim().isNotEmpty) params['from'] = from.trim();
    if (to != null && to.trim().isNotEmpty) params['to'] = to.trim();

    final response = await http.get(
      AppConfig.apiUri('admin/reports/card-scans/users', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminCardScanReportUserLocations(
    String userId, {
    String scope = 'private',
    String? from,
    String? to,
  }) async {
    final params = <String, String>{'scope': scope};
    if (from != null && from.trim().isNotEmpty) params['from'] = from.trim();
    if (to != null && to.trim().isNotEmpty) params['to'] = to.trim();

    final response = await http.get(
      AppConfig.apiUri(
        'admin/reports/card-scans/users/$userId/locations',
        params,
      ),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminCardScanReportLocations({
    String scope = 'private',
    String? from,
    String? to,
  }) async {
    final params = <String, String>{'scope': scope};
    if (from != null && from.trim().isNotEmpty) params['from'] = from.trim();
    if (to != null && to.trim().isNotEmpty) params['to'] = to.trim();

    final response = await http.get(
      AppConfig.apiUri('admin/reports/card-scans/locations', params),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateCardAutoRedeemOnScanPreference({
    required bool enabled,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('cards/auto-redeem-on-scan'),
      headers: await _headers(),
      body: jsonEncode({'enabled': enabled}),
    );
    final body = _decodeObject(response);
    if (body['user'] is Map) {
      await _authService.patchCurrentUser(
        Map<String, dynamic>.from(body['user'] as Map),
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> redeemCard({
    required String cardId,
    required String customerName,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{'customerName': customerName};
    if (location != null) {
      payload['location'] = location;
    }
    final response = await http.post(
      AppConfig.apiUri('cards/$cardId/redeem'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    await _authService.patchCurrentUser({
      if (body['trialCardsLimit'] is num)
        'trialCardsLimit': (body['trialCardsLimit'] as num).toDouble(),
      if (body['trialCardsOutstandingAmount'] is num)
        'trialCardsOutstandingAmount':
            (body['trialCardsOutstandingAmount'] as num).toDouble(),
      if (body['trialCardsRemainingAmount'] is num)
        'trialCardsAvailableAmount': (body['trialCardsRemainingAmount'] as num)
            .toDouble(),
    });
    return body;
  }

  Future<Map<String, dynamic>> syncOfflineCardRedeems({
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('cards/offline-redeem'),
      headers: await _headers(),
      body: jsonEncode({'items': items}),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    return body;
  }

  Future<Map<String, dynamic>> getMyTransactions({
    String locationFilter = 'all',
    String query = '',
    String dateFilter = 'all',
    bool printingDebtOnly = false,
    int page = 1,
    int perPage = 10,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('transactions/me', {
        if (locationFilter != 'all') 'locationFilter': locationFilter,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (dateFilter != 'all') 'dateFilter': dateFilter,
        if (printingDebtOnly) 'printingDebtOnly': 'true',
        'page': page.toString(),
        'perPage': perPage.toString(),
      }),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminPrepaidMultipaySettings() async {
    final response = await http.get(
      AppConfig.apiUri('admin/settings/prepaid-multipay'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(
      body['prepaidMultipay'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> updateAdminPrepaidMultipaySettings({
    required double maxCardAmount,
    required double maxPaymentAmount,
    required int maxActiveCards,
    required int maxExpiryDays,
    required double dailyPaymentAmountLimit,
    required int dailyPaymentCountLimit,
    bool? nfcEnabled,
    bool? nfcPilotOnly,
    double? nfcMaxPaymentAmount,
    int? nfcAuthorizationTtlSeconds,
    int? nfcMaxDevicesPerCard,
    double? nfcOfflineMerchantAmountLimit,
    int? nfcOfflineMerchantCountLimit,
    bool? nfcRequireBiometrics,
  }) async {
    final payload = <String, dynamic>{
      'maxCardAmount': maxCardAmount,
      'maxPaymentAmount': maxPaymentAmount,
      'maxActiveCards': maxActiveCards,
      'maxExpiryDays': maxExpiryDays,
      'dailyPaymentAmountLimit': dailyPaymentAmountLimit,
      'dailyPaymentCountLimit': dailyPaymentCountLimit,
    };
    if (nfcEnabled != null) payload['nfcEnabled'] = nfcEnabled;
    if (nfcPilotOnly != null) payload['nfcPilotOnly'] = nfcPilotOnly;
    if (nfcMaxPaymentAmount != null) {
      payload['nfcMaxPaymentAmount'] = nfcMaxPaymentAmount;
    }
    if (nfcAuthorizationTtlSeconds != null) {
      payload['nfcAuthorizationTtlSeconds'] = nfcAuthorizationTtlSeconds;
    }
    if (nfcMaxDevicesPerCard != null) {
      payload['nfcMaxDevicesPerCard'] = nfcMaxDevicesPerCard;
    }
    if (nfcOfflineMerchantAmountLimit != null) {
      payload['nfcOfflineMerchantAmountLimit'] = nfcOfflineMerchantAmountLimit;
    }
    if (nfcOfflineMerchantCountLimit != null) {
      payload['nfcOfflineMerchantCountLimit'] = nfcOfflineMerchantCountLimit;
    }
    if (nfcRequireBiometrics != null) {
      payload['nfcRequireBiometrics'] = nfcRequireBiometrics;
    }

    final response = await http.put(
      AppConfig.apiUri('admin/settings/prepaid-multipay'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminPrepaidMultipayPayments({
    String? buyerUserId,
    String? merchantUserId,
    String? dateFrom,
    String? dateTo,
    String? query,
    String? cardStatus,
    int perPage = 50,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('admin/prepaid-multipay/payments', {
        if (buyerUserId != null && buyerUserId.trim().isNotEmpty)
          'buyerUserId': buyerUserId.trim(),
        if (merchantUserId != null && merchantUserId.trim().isNotEmpty)
          'merchantUserId': merchantUserId.trim(),
        if (dateFrom != null && dateFrom.trim().isNotEmpty)
          'dateFrom': dateFrom.trim(),
        if (dateTo != null && dateTo.trim().isNotEmpty) 'dateTo': dateTo.trim(),
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (cardStatus != null &&
            cardStatus.trim().isNotEmpty &&
            cardStatus.trim() != 'all')
          'cardStatus': cardStatus.trim(),
        'perPage': perPage.toString(),
      }),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminPendingPrepaidMultipayApprovals({
    int perPage = 50,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('admin/prepaid-multipay/approvals', {
        'perPage': perPage.toString(),
      }),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminPrepaidMultipayNfcAttempts({
    String? status,
    int perPage = 50,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('admin/prepaid-multipay/nfc/attempts', {
        if (status != null && status.trim().isNotEmpty && status != 'all')
          'status': status.trim(),
        'perPage': perPage.toString(),
      }),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> reviewAdminPrepaidMultipayApproval({
    required String cardId,
    required String action,
    String? note,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/prepaid-multipay/approvals/$cardId'),
      headers: await _headers(),
      body: jsonEncode({
        'action': action.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<void> exportAdminPrepaidMultipayPaymentsCsv({
    required List<Map<String, dynamic>> payments,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(
      '\uFEFFid,buyer,merchant,card_label,card_number,card_status,amount,status,note,created_at',
    );
    for (final item in payments) {
      String csv(String value) => '"${value.replaceAll('"', '""')}"';
      buffer.writeln(
        [
          csv(item['id']?.toString() ?? ''),
          csv(item['buyerUsername']?.toString() ?? ''),
          csv(item['merchantUsername']?.toString() ?? ''),
          csv(item['cardLabel']?.toString() ?? ''),
          csv(item['cardNumber']?.toString() ?? ''),
          csv(item['cardStatus']?.toString() ?? ''),
          item['amount']?.toString() ?? '',
          csv(item['status']?.toString() ?? ''),
          csv(item['note']?.toString() ?? ''),
          csv(item['createdAt']?.toString() ?? ''),
        ].join(','),
      );
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    await FileSaver.instance.saveFile(
      name: 'prepaid_multipay_payments',
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  Future<Map<String, dynamic>> getPrepaidMultipayCards() async {
    final response = await http.get(
      AppConfig.apiUri('prepaid-multipay-cards'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> createPrepaidMultipayCard({
    required String label,
    required double amount,
    required String pin,
    required int validityYears,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards'),
      headers: await _headers(),
      body: jsonEncode({
        'label': label.trim(),
        'amount': amount,
        'pin': pin.trim(),
        'validityYears': validityYears,
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> reloadPrepaidMultipayCard({
    required String cardId,
    required double amount,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/reload'),
      headers: await _headers(),
      body: jsonEncode({
        'amount': amount,
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> renewPrepaidMultipayCard({
    required String cardId,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/renew'),
      headers: await _headers(),
      body: jsonEncode({
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> updatePrepaidMultipayCard({
    required String cardId,
    required String label,
    required int validityYears,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId'),
      headers: await _headers(),
      body: jsonEncode({
        'label': label.trim(),
        'validityYears': validityYears,
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> deletePrepaidMultipayCard({
    required String cardId,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final request = http.Request(
      'DELETE',
      AppConfig.apiUri('prepaid-multipay-cards/$cardId'),
    );
    request.headers.addAll(await _headers());
    request.body = jsonEncode({
      if (otpCode != null && otpCode.trim().isNotEmpty)
        'otpCode': otpCode.trim(),
      if ((otpCode == null || otpCode.trim().isEmpty) &&
          localAuthMethod != null &&
          localAuthMethod.trim().isNotEmpty)
        'localAuthMethod': localAuthMethod.trim(),
    });

    final client = http.Client();
    late final http.Response response;
    try {
      final streamed = await client.send(request);
      response = await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
    final body = _decodeObject(response);
    if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> updatePrepaidMultipayCardStatus({
    required String cardId,
    required String action,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/status'),
      headers: await _headers(),
      body: jsonEncode({
        'action': action,
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['balance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['balance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> changePrepaidMultipayCardPin({
    required String cardId,
    required String currentPin,
    required String newPin,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/pin'),
      headers: await _headers(),
      body: jsonEncode({
        'currentPin': currentPin.trim(),
        'newPin': newPin.trim(),
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getPrepaidMultipayNfcDevices({
    required String cardId,
  }) async {
    final response = await http.get(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/nfc/devices'),
      headers: await _headers(),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> registerPrepaidMultipayNfcDevice({
    required String cardId,
    required String deviceId,
    required String deviceName,
    required String publicKey,
    String keyAlgorithm = 'ed25519',
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/nfc/devices'),
      headers: await _headers(),
      body: jsonEncode({
        'deviceId': deviceId.trim(),
        'deviceName': deviceName.trim(),
        'publicKey': publicKey.trim(),
        'keyAlgorithm': keyAlgorithm.trim(),
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> revokePrepaidMultipayNfcDevice({
    required String cardId,
    required String deviceId,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final request = http.Request(
      'DELETE',
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/nfc/devices/$deviceId'),
    );
    request.headers.addAll(await _headers());
    request.body = jsonEncode({
      if (otpCode != null && otpCode.trim().isNotEmpty)
        'otpCode': otpCode.trim(),
      if ((otpCode == null || otpCode.trim().isEmpty) &&
          localAuthMethod != null &&
          localAuthMethod.trim().isNotEmpty)
        'localAuthMethod': localAuthMethod.trim(),
    });

    final client = http.Client();
    late final http.Response response;
    try {
      final streamed = await client.send(request);
      response = await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> preparePrepaidMultipayNfcPayment({
    required String cardId,
    required double amount,
    required String pin,
    required String deviceId,
    String? merchantId,
    String? appVersion,
    String? otpCode,
    String? localAuthMethod,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/$cardId/nfc/prepare'),
      headers: await _headers(),
      body: jsonEncode({
        'amount': amount,
        'pin': pin.trim(),
        'deviceId': deviceId.trim(),
        if (merchantId != null && merchantId.trim().isNotEmpty)
          'merchantId': merchantId.trim(),
        if (appVersion != null && appVersion.trim().isNotEmpty)
          'appVersion': appVersion.trim(),
        if (otpCode != null && otpCode.trim().isNotEmpty)
          'otpCode': otpCode.trim(),
        if ((otpCode == null || otpCode.trim().isEmpty) &&
            localAuthMethod != null &&
            localAuthMethod.trim().isNotEmpty)
          'localAuthMethod': localAuthMethod.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> acceptPrepaidMultipayNfcPayment({
    required String signedPayload,
    required String signature,
    required String idempotencyKey,
    String? merchantDeviceId,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/nfc/payments'),
      headers: await _headers(),
      body: jsonEncode({
        'signedPayload': signedPayload,
        'signature': signature,
        'idempotencyKey': idempotencyKey,
        if (merchantDeviceId != null && merchantDeviceId.trim().isNotEmpty)
          'merchantDeviceId': merchantDeviceId.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['merchantBalance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['merchantBalance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> getPrepaidMultipayNfcPaymentStatus({
    required String idempotencyKey,
  }) async {
    final response = await http.get(
      AppConfig.apiUri(
        'prepaid-multipay-cards/nfc/payments/status/${Uri.encodeComponent(idempotencyKey.trim())}',
      ),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    if (body['merchantBalance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['merchantBalance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> acceptPrepaidMultipayCardPayment({
    required String cardNumber,
    required double amount,
    required String expiryMonth,
    required String expiryYear,
    required String securityCode,
    required String idempotencyKey,
    String? note,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('prepaid-multipay-cards/payments'),
      headers: await _headers(),
      body: jsonEncode({
        'cardNumber': cardNumber.trim(),
        'amount': amount,
        'expiryMonth': expiryMonth.trim(),
        'expiryYear': expiryYear.trim(),
        'securityCode': securityCode.trim(),
        'idempotencyKey': idempotencyKey,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
    final body = _decodeObject(response);
    if (body['merchantBalance'] is num) {
      await _authService.patchCurrentUser({
        'balance': (body['merchantBalance'] as num).toDouble(),
      });
    }
    return body;
  }

  Future<Map<String, dynamic>> getNotificationSummary() async {
    final cached = _cachedNotificationSummary;
    final cachedAt = _cachedNotificationSummaryAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) <
            _notificationSummaryCacheLifetime) {
      return Map<String, dynamic>.from(cached);
    }
    final pending = _pendingNotificationSummaryRequest;
    if (pending != null) {
      return Map<String, dynamic>.from(await pending);
    }
    final future = _fetchNotificationSummary();
    _pendingNotificationSummaryRequest = future;
    try {
      return Map<String, dynamic>.from(await future);
    } finally {
      if (identical(_pendingNotificationSummaryRequest, future)) {
        _pendingNotificationSummaryRequest = null;
      }
    }
  }

  Future<Map<String, dynamic>> _fetchNotificationSummary() async {
    final response = await _getNotificationWithFallback(
      'notifications/summary',
    );
    final payload = _decodeObject(response);
    _cachedNotificationSummary = Map<String, dynamic>.from(payload);
    _cachedNotificationSummaryAt = DateTime.now();
    return payload;
  }

  Future<Map<String, dynamic>> getAppNotifications({
    String filter = 'all',
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _getNotificationWithFallback(
      'notifications',
      query: {
        'filter': filter,
        'page': page.toString(),
        'perPage': perPage.toString(),
      },
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> getAdminNotificationComposer() async {
    final response = await _authenticatedGetWithFallback('admin/notifications');
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> sendAdminNotification({
    required String targetType,
    String targetValue = '',
    required String category,
    required String notificationType,
    required String priority,
    required String title,
    required String body,
    String details = '',
    String actionRoute = '',
    String actionLabel = '',
  }) async {
    final response = await _authenticatedPostWithFallback(
      'admin/notifications',
      body: jsonEncode({
        'targetType': targetType,
        'targetValue': targetValue,
        'category': category,
        'notificationType': notificationType,
        'priority': priority,
        'title': title.trim(),
        'body': body.trim(),
        if (details.trim().isNotEmpty) 'details': details.trim(),
        if (actionRoute.trim().isNotEmpty) 'actionRoute': actionRoute.trim(),
        if (actionLabel.trim().isNotEmpty) 'actionLabel': actionLabel.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> markNotificationAsRead(String id) async {
    final response = await _authenticatedPostWithFallback(
      'notifications/$id/read',
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> markAllNotificationsAsRead() async {
    final response = await _authenticatedPostWithFallback(
      'notifications/read-all',
    );
    return _decodeObject(response);
  }

  Future<http.Response> _authenticatedGetWithFallback(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    Object? lastError;
    http.Response? lastAuthFailure;
    final headers = await _headers();
    for (final uri in AppConfig.apiCandidateUris(path, query)) {
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(_authenticatedRequestTimeout);
        if ((response.statusCode == 401 || response.statusCode == 403) &&
            AppConfig.apiBaseUrls.length > 1) {
          lastAuthFailure = response;
          continue;
        }
        return response;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }
    if (lastAuthFailure != null) {
      return lastAuthFailure;
    }
    throw lastError ?? Exception(_tr('services_api_service.001'));
  }

  Future<http.Response> _authenticatedPostWithFallback(
    String path, {
    Object? body,
  }) async {
    Object? lastError;
    http.Response? lastAuthFailure;
    final headers = await _headers();
    for (final uri in AppConfig.apiCandidateUris(path)) {
      try {
        final response = await _client
            .post(uri, headers: headers, body: body)
            .timeout(_authenticatedRequestTimeout);
        if ((response.statusCode == 401 || response.statusCode == 403) &&
            AppConfig.apiBaseUrls.length > 1) {
          lastAuthFailure = response;
          continue;
        }
        return response;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }
    if (lastAuthFailure != null) {
      return lastAuthFailure;
    }
    throw lastError ?? Exception(_tr('services_api_service.001'));
  }

  Future<http.Response> _getNotificationWithFallback(
    String path, {
    Map<String, dynamic>? query,
  }) {
    return _authenticatedGetWithFallback(path, query: query);
  }

  Future<Map<String, dynamic>> resellCard({
    required String cardId,
    String? otpCode,
    Map<String, dynamic>? location,
  }) async {
    final payload = <String, dynamic>{};
    if (otpCode != null && otpCode.trim().isNotEmpty) {
      payload['otpCode'] = otpCode.trim();
    }
    if (location != null) {
      payload['location'] = location;
    }
    final response = await http.post(
      AppConfig.apiUri('cards/$cardId/resell'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
    return body;
  }

  Future<void> _syncCurrentUserFromPayload(Map<String, dynamic> body) async {
    final user = body['user'];
    if (user is Map<String, dynamic>) {
      await _authService.cacheCurrentUser(user);
      return;
    }
    if (user is Map) {
      await _authService.cacheCurrentUser(Map<String, dynamic>.from(user));
    }
  }

  Future<void> _patchCachedBalanceFromPayload(Map<String, dynamic> body) async {
    final balance = body['balance'];
    if (balance is num) {
      final currentUser = await _authService.currentUser();
      final currentUserId = currentUser?['id']?.toString();
      final balanceOwnerId = body['balanceOwnerId']?.toString();
      if (balanceOwnerId != null &&
          balanceOwnerId.isNotEmpty &&
          currentUserId != balanceOwnerId) {
        return;
      }
      await _authService.patchCurrentUser({'balance': balance.toDouble()});
    }
  }

  VirtualCard _cardFromApi(Map<String, dynamic> map) {
    return VirtualCard.fromMap({
      ...map,
      'status': map['status']?.toString() ?? 'available',
    }).copyWith(
      status: _statusFromApi(map['status']?.toString()),
      soldPrice: _doubleFromApi(map['value']),
    );
  }

  double? _doubleFromApi(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.trim().replaceAll(',', '');
      if (normalized.isNotEmpty) {
        return double.tryParse(normalized);
      }
    }
    return null;
  }

  CardStatus _statusFromApi(String? status) {
    switch (status) {
      case 'used':
        return CardStatus.used;
      case 'archived':
        return CardStatus.archived;
      default:
        return CardStatus.unused;
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    final rawBody = response.body;
    final trimmedBody = rawBody.trimLeft();
    final looksLikeHtml =
        trimmedBody.startsWith('<!DOCTYPE html') ||
        trimmedBody.startsWith('<html') ||
        trimmedBody.startsWith('<');
    final fallbackMessage = _tr('services_api_service.001');
    final payloadTooLargeMessage = _tr('services_api_service.002');

    if (response.statusCode == 401) {
      throw Exception(_tr('services_error_message_service.011'));
    }

    if (response.statusCode == 403) {
      throw Exception(_tr('services_error_message_service.002'));
    }

    if (response.statusCode == 413) {
      throw Exception(payloadTooLargeMessage);
    }

    if (!contentType.contains('application/json') && looksLikeHtml) {
      throw Exception(
        response.statusCode == 413 ? payloadTooLargeMessage : fallbackMessage,
      );
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(rawBody) as Map<String, dynamic>;
    } on FormatException {
      throw Exception(fallbackMessage);
    }

    if (response.statusCode >= 400) {
      throw Exception(ErrorMessageService.sanitize(body['message']));
    }

    return body;
  }

  String _tr(String key) {
    if ((AppLocaleService.instance.locale?.languageCode ?? 'ar') == 'en') {
      return appStringsEn[key] ?? key;
    }
    return appStringsAr[key] ?? appStringsEn[key] ?? key;
  }
}
