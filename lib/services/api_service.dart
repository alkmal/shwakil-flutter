import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;
import '../models/index.dart';
import 'app_config.dart';
import 'app_version_service.dart';
import 'auth_service.dart';
import 'error_message_service.dart';

class ApiService {
  final AuthService _authService = AuthService();

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

  Future<Map<String, String>> _publicHeaders() {
    return AppVersionService.publicHeaders();
  }

  Future<Map<String, dynamic>> getMyBalance({
    String locationFilter = 'all',
    int page = 1,
    int perPage = 8,
    bool printingDebtOnly = false,
  }) async {
    final response = await http.get(
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
    final response = await http.get(
      AppConfig.apiUri('app/contact-info'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['contact'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getAuthSettings() async {
    final response = await http.get(
      AppConfig.apiUri('app/auth-settings'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['auth'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getTopupRequestSettings() async {
    final response = await http.get(
      AppConfig.apiUri('app/topup-request-settings'),
      headers: await _publicHeaders(),
    );
    final body = _decodeObject(response);
    return Map<String, dynamic>.from(body['topupRequest'] as Map? ?? const {});
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

  Future<Map<String, dynamic>> getAdminUserDevices(String userId) async {
    final response = await http.get(
      AppConfig.apiUri('admin/users/$userId/devices'),
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
    required bool canResellCards,
    required bool canRequestCardPrinting,
    required bool canManageCardPrintRequests,
    required bool canOfflineCardScan,
    required bool canManageUsers,
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/users/$userId/card-permissions'),
      headers: await _headers(),
      body: jsonEncode({
        'canIssueCards': canIssueCards,
        'canIssueSubShekelCards': canIssueSubShekelCards,
        'canIssueHighValueCards': canIssueHighValueCards,
        'canIssuePrivateCards': canIssuePrivateCards,
        'canResellCards': canResellCards,
        'canRequestCardPrinting': canRequestCardPrinting,
        'canManageCardPrintRequests': canManageCardPrintRequests,
        'canOfflineCardScan': canOfflineCardScan,
        'canManageUsers': canManageUsers,
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> updateAdminUserAccountControls({
    required String userId,
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
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/users/$userId/account-controls'),
      headers: await _headers(),
      body: jsonEncode({
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
  }) async {
    final response = await http.post(
      AppConfig.apiUri('cards/print-requests'),
      headers: await _headers(),
      body: jsonEncode({
        'value': value,
        'quantity': quantity,
        'cardType': cardType,
        'notes': notes.trim(),
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
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users'),
      headers: await _headers(),
      body: jsonEncode({
        'username': username.trim(),
        'whatsapp': whatsapp.trim(),
        'fullName': fullName.trim(),
        'password': password,
        'countryCode': countryCode.trim(),
      }),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> resendAdminUserAccountDetails({
    required String userId,
    bool regeneratePassword = true,
  }) async {
    final response = await http.post(
      AppConfig.apiUri('admin/users/$userId/resend-account-details'),
      headers: await _headers(),
      body: jsonEncode({'regeneratePassword': regeneratePassword}),
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
        'minSupportedVersion': minSupportedVersion.trim(),
        'latestVersion': latestVersion.trim(),
        'androidStoreUrl': androidStoreUrl.trim(),
        'iosStoreUrl': iosStoreUrl.trim(),
        'webStoreUrl': webStoreUrl.trim(),
      }),
    );
    return _decodeObject(response);
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
  }) async {
    final response = await http.put(
      AppConfig.apiUri('admin/settings/topup-request'),
      headers: await _headers(),
      body: jsonEncode({
        'enabled': enabled,
        'instructions': instructions.trim(),
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
    required String minSupportedVersion,
    required String latestVersion,
    required String androidStoreUrl,
    required String iosStoreUrl,
    required String webStoreUrl,
  }) {
    return updateAdminAuthSettings(
      registrationEnabled: registrationEnabled,
      minSupportedVersion: minSupportedVersion,
      latestVersion: latestVersion,
      androidStoreUrl: androidStoreUrl,
      iosStoreUrl: iosStoreUrl,
      webStoreUrl: webStoreUrl,
    );
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
    }
    final response = await http.post(
      AppConfig.apiUri('wallet/topup'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> transferBalance({
    required String recipientId,
    required double amount,
    String notes = '',
    String? otpCode,
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

  Future<Map<String, dynamic>> getTopupRequestOptions() async {
    final response = await http.get(
      AppConfig.apiUri('wallet/topup-request/options'),
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
    String notes = '',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('auth/verification'),
      headers: await _headers(),
      body: jsonEncode({
        'identityDocumentBase64': identityDocumentBase64,
        'selfieImageBase64': selfieImageBase64,
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
    String visibilityScope = 'general',
    String cardType = 'standard',
  }) async {
    final response = await http.post(
      AppConfig.apiUri('cards/issue'),
      headers: await _headers(),
      body: jsonEncode({
        'value': value,
        'quantity': quantity,
        'allowedUserIds': allowedUserIds,
        'visibilityScope': visibilityScope,
        'cardType': cardType,
      }),
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

  Future<void> deleteCard(String cardId) async {
    final response = await http.delete(
      AppConfig.apiUri('cards/$cardId'),
      headers: await _headers(),
    );
    final body = _decodeObject(response);
    await _patchCachedBalanceFromPayload(body);
  }

  Future<VirtualCard?> getCardByBarcode(String barcode) async {
    final response = await http.get(
      AppConfig.apiUri('cards/$barcode'),
      headers: await _headers(),
    );
    if (response.statusCode == 404) {
      return null;
    }
    final body = _decodeObject(response);
    return _cardFromApi(Map<String, dynamic>.from(body['card'] as Map));
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
      await _authService.patchCurrentUser({'balance': balance.toDouble()});
    }
  }

  VirtualCard _cardFromApi(Map<String, dynamic> map) {
    return VirtualCard(
      id: map['id']?.toString() ?? '',
      barcode: map['barcode']?.toString() ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0,
      cardType: map['cardType']?.toString() ?? 'standard',
      visibilityScope: map['visibilityScope']?.toString() ?? 'general',
      issueCost: (map['issueCost'] as num?)?.toDouble() ?? 0,
      ownerId: map['ownerId']?.toString(),
      ownerUsername: map['ownerUsername']?.toString(),
      issuedById: map['issuedById']?.toString(),
      issuedByUsername: map['issuedByUsername']?.toString(),
      redeemedById: map['redeemedById']?.toString(),
      allowedUserIds: List<String>.from(
        (map['allowedUserIds'] as List? ?? const []).map(
          (item) => item.toString(),
        ),
      ),
      allowedUsernames: List<String>.from(
        (map['allowedUsernames'] as List? ?? const []).map(
          (item) => item.toString(),
        ),
      ),
      customerName: map['customerName']?.toString(),
      createdAt:
          DateTime.tryParse(map['issuedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastResoldAt: map['lastResoldAt'] == null
          ? null
          : DateTime.tryParse(map['lastResoldAt'].toString()),
      useCount: (map['useCount'] as num?)?.toInt() ?? 0,
      resaleCount: (map['resaleCount'] as num?)?.toInt() ?? 0,
      totalRedeemedValue: (map['totalRedeemedValue'] as num?)?.toDouble() ?? 0,
      status: _statusFromApi(map['status']?.toString()),
      usedAt: map['redeemedAt'] == null
          ? null
          : DateTime.tryParse(map['redeemedAt'].toString()),
      usedBy: map['redeemedByUsername']?.toString(),
      soldPrice: (map['value'] as num?)?.toDouble(),
    );
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
    const fallbackMessage = 'تأكد من جميع البيانات وحاول مرة أخرى.';

    if (!contentType.contains('application/json') && looksLikeHtml) {
      throw Exception(fallbackMessage);
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
}
