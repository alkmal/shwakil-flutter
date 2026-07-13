import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/admin_customer_screen.dart';
import '../utils/app_permissions.dart';
import 'api_service.dart';
import 'app_alert_service.dart';
import 'auth_service.dart';
import 'local_security_service.dart';
import 'offline_session_service.dart';

class NotificationNavigationService {
  NotificationNavigationService._();

  static Map<String, dynamic>? _pendingPayload;
  static int _pendingAttempts = 0;
  static VoidCallback? _unlockListener;
  static const int _maxPendingAttempts = 8;

  static String? requiredLocalSecurityRoute() {
    if (LocalSecurityService.securitySetupRequired) {
      return '/security-settings';
    }
    if (LocalSecurityService.relockRequired) {
      return '/unlock';
    }
    return null;
  }

  static Future<void> openFromPushPayload(Map<String, dynamic> payload) {
    return _openResolvedPayload(
      _normalizePayload(payload),
      includeDefaultNotificationsRoute: true,
    );
  }

  static Future<void> openFromLocalNotificationPayload(String? payload) async {
    final normalized = _normalizePayload(_decodeMap(payload));
    if (normalized.isEmpty) {
      return;
    }
    await _openResolvedPayload(
      normalized,
      includeDefaultNotificationsRoute: true,
    );
  }

  static Future<void> openFromNotificationItem(Map<String, dynamic> item) {
    return _openResolvedPayload(
      _payloadFromNotificationItem(item),
      includeDefaultNotificationsRoute: false,
    );
  }

  static String? actionRouteForNotificationItem(Map<String, dynamic> item) {
    return _resolveRoute(
      _payloadFromNotificationItem(item),
      includeDefaultNotificationsRoute: false,
    );
  }

  static Future<void> _openResolvedPayload(
    Map<String, dynamic> payload, {
    required bool includeDefaultNotificationsRoute,
  }) async {
    if (payload.isEmpty) {
      return;
    }

    if (requiredLocalSecurityRoute() != null) {
      _deferUntilLocalSecurityClears(payload);
      return;
    }

    final currentUser = await AuthService().currentUser();
    final permissions = AppPermissions.fromUser(currentUser);
    final route = _resolveRoute(
      payload,
      includeDefaultNotificationsRoute: includeDefaultNotificationsRoute,
      permissions: permissions,
    );
    if (route == null || route.isEmpty) {
      return;
    }

    if (AppAlertService.navigatorKey.currentState == null ||
        AppAlertService.navigatorKey.currentContext == null) {
      _queuePayload(payload);
      return;
    }

    final handled = await _openCustomDestination(
      payload,
      includeDefaultNotificationsRoute: includeDefaultNotificationsRoute,
      permissions: permissions,
    );
    if (handled) {
      return;
    }

    final navigator = AppAlertService.navigatorKey.currentState;
    final context = AppAlertService.navigatorKey.currentContext;
    if (navigator == null || context == null) {
      _queuePayload(payload);
      return;
    }

    await _pushNamedIfDifferent(route);
  }

  static Future<bool> _openCustomDestination(
    Map<String, dynamic> payload, {
    required bool includeDefaultNotificationsRoute,
    required AppPermissions permissions,
  }) async {
    if (_isErrorNotification(payload)) {
      return true;
    }

    if (_isAdminUserContextNotification(payload, permissions)) {
      final opened = await _openAdminCustomerDestination(payload, permissions);
      if (opened) {
        return true;
      }
    }

    if (_isPendingVerificationNotification(payload) &&
        permissions.canManageUsers) {
      final route = _normalizeRouteName('/admin-verification-requests');
      final navigator = AppAlertService.navigatorKey.currentState;
      if (route == null || navigator == null) {
        _queuePayload(payload);
        return true;
      }
      await _pushNamedIfDifferent(route);
      return true;
    }

    if (!_isNewUserRequestNotification(payload) ||
        !(permissions.canManageUsers ||
            permissions.canManageMarketingAccounts)) {
      return false;
    }

    final pendingRequest = await _findPendingRegistration(payload);
    if (pendingRequest != null) {
      final route = _normalizeRouteName('/admin-pending-registrations');
      if (route != null) {
        final navigator = AppAlertService.navigatorKey.currentState;
        if (navigator == null) {
          _queuePayload(payload);
          return true;
        }
        await _pushNamedIfDifferent(route);
      }
      return true;
    }

    final customer = await _findCustomerForRegistrationNotification(payload);
    if (customer == null) {
      final fallbackRoute = _resolveRoute(
        payload,
        includeDefaultNotificationsRoute: includeDefaultNotificationsRoute,
        permissions: permissions,
      );
      if (fallbackRoute == null || fallbackRoute.isEmpty) {
        return true;
      }
      final navigator = AppAlertService.navigatorKey.currentState;
      if (navigator == null) {
        _queuePayload(payload);
        return true;
      }
      await _pushNamedIfDifferent(fallbackRoute);
      return true;
    }

    final navigator = AppAlertService.navigatorKey.currentState;
    if (navigator == null) {
      _queuePayload(payload);
      return true;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminCustomerScreen(
          customer: customer,
          canManageUsers: permissions.canManageUsers,
          canManageMarketingAccounts: permissions.canManageMarketingAccounts,
        ),
      ),
    );
    return true;
  }

  static void _queuePayload(Map<String, dynamic> payload) {
    _pendingPayload = payload;
    _pendingAttempts++;
    if (_pendingAttempts > _maxPendingAttempts) {
      _pendingPayload = null;
      _pendingAttempts = 0;
      return;
    }

    Timer(const Duration(milliseconds: 500), () {
      final pending = _pendingPayload;
      if (pending == null) {
        return;
      }
      _pendingPayload = null;
      unawaited(
        _openResolvedPayload(
          pending,
          includeDefaultNotificationsRoute: true,
        ).whenComplete(() {
          if (_pendingPayload == null) {
            _pendingAttempts = 0;
          }
        }),
      );
    });
  }

  static void _deferUntilLocalSecurityClears(Map<String, dynamic> payload) {
    _pendingPayload = payload;
    final existingListener = _unlockListener;
    if (existingListener != null) {
      LocalSecurityService.securityStateListenable.removeListener(
        existingListener,
      );
    }

    void listener() {
      if (LocalSecurityService.relockRequired ||
          LocalSecurityService.securitySetupRequired) {
        return;
      }
      LocalSecurityService.securityStateListenable.removeListener(listener);
      _unlockListener = null;
      final pending = _pendingPayload;
      _pendingPayload = null;
      if (pending == null) {
        return;
      }
      Timer(const Duration(milliseconds: 700), () {
        unawaited(
          _openResolvedPayload(pending, includeDefaultNotificationsRoute: true),
        );
      });
    }

    _unlockListener = listener;
    LocalSecurityService.securityStateListenable.addListener(listener);
    final navigator = AppAlertService.navigatorKey.currentState;
    final context = AppAlertService.navigatorKey.currentContext;
    if (navigator != null && context != null) {
      final gateRoute = requiredLocalSecurityRoute();
      if (gateRoute == null) {
        return;
      }
      final currentRoute = ModalRoute.of(context)?.settings.name;
      if (currentRoute != gateRoute) {
        unawaited(
          navigator.pushNamed(
            gateRoute,
            arguments: gateRoute == '/unlock'
                ? const {'returnRoute': '/home'}
                : null,
          ),
        );
      }
    }
  }

  static Future<void> _pushNamedIfDifferent(String route) async {
    final normalizedRoute = _normalizeRouteName(route) ?? route;
    final navigator = AppAlertService.navigatorKey.currentState;
    final context = AppAlertService.navigatorKey.currentContext;
    if (navigator == null || context == null) {
      return;
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == normalizedRoute ||
        (currentRoute == '/app-shell' && normalizedRoute == '/home')) {
      return;
    }

    await navigator.pushNamed(normalizedRoute);
  }

  static String? _resolveRoute(
    Map<String, dynamic> payload, {
    required bool includeDefaultNotificationsRoute,
    AppPermissions? permissions,
  }) {
    if (_isErrorNotification(payload)) {
      return null;
    }

    final explicitRoute = _normalizeRouteName(
      payload['actionRoute']?.toString() ?? payload['route']?.toString(),
    );
    if (explicitRoute != null) {
      return explicitRoute;
    }

    final sourceType = _normalizedText(
      payload['sourceType'] ?? payload['source_type'],
    );
    final category = _normalizedText(payload['category']);
    final type = _normalizedText(payload['transactionType'] ?? payload['type']);
    final messageType = _normalizedText(payload['messageType']);
    final currentPermissions = permissions;
    final canUseAdminRoutes =
        currentPermissions?.hasAdminWorkspaceAccess == true;

    if (canUseAdminRoutes) {
      final adminRoute = _resolveAdminRoute(
        payload,
        permissions: currentPermissions!,
        sourceType: sourceType,
        category: category,
        type: type,
        messageType: messageType,
      );
      if (adminRoute != null) {
        return adminRoute;
      }
    }
    if (currentPermissions == null) {
      final adminPreviewRoute = _resolveAdminPreviewRoute(
        payload,
        sourceType: sourceType,
        category: category,
        type: type,
        messageType: messageType,
      );
      if (adminPreviewRoute != null) {
        return adminPreviewRoute;
      }
    }

    if (const {
      'card_print_request',
      'card_print_request_completed',
      'card_print_request_refund',
      'admin_card_print_request',
    }.contains(type)) {
      return _normalizeRouteName('/card-print-requests');
    }

    if (const {
      'issue_cards',
      'delete_card',
      'redeem_card',
      'resell_card',
      'printed_cards_received',
    }.contains(type)) {
      return _normalizeRouteName('/inventory');
    }

    if ((type.contains('withdrawal') || messageType.contains('withdrawal')) &&
        (sourceType == 'admin_custom_notification' ||
            category == 'account' ||
            category == 'general')) {
      return _normalizeRouteName('/withdrawal-requests');
    }

    if ((type.contains('topup') || messageType.contains('topup')) &&
        sourceType == 'admin_custom_notification' &&
        category != 'financial') {
      return _normalizeRouteName('/topup-requests');
    }

    if (category == 'financial' ||
        const {
          'financial_transaction',
          'topup',
          'balance_credit',
          'wallet_topup_received',
          'transfer_in',
          'transfer_out',
          'wallet_transfer_sent',
          'withdrawal',
          'withdrawal_request',
          'withdrawal_refund',
          'manual_deduction',
          'affiliate_commission_credit',
          'app_fee_credit',
          'app_fee_reversal',
        }.contains(type)) {
      return _normalizeRouteName('/transactions');
    }

    if (type.contains('verification') || messageType.contains('verification')) {
      return _normalizeRouteName('/account-verification');
    }

    if (type.contains('security') ||
        type.contains('device') ||
        type.contains('password') ||
        type.contains('credential') ||
        messageType.contains('device') ||
        messageType.contains('security')) {
      return _normalizeRouteName('/security-settings');
    }

    if (category == 'account' ||
        type == 'account_event' ||
        type.startsWith('account_') ||
        type.contains('profile') ||
        type.contains('registration') ||
        messageType.contains('registration')) {
      return _normalizeRouteName('/account-settings');
    }

    if (sourceType == 'admin_custom_notification' ||
        includeDefaultNotificationsRoute) {
      return _normalizeRouteName('/notifications');
    }

    return null;
  }

  static String? _resolveAdminPreviewRoute(
    Map<String, dynamic> payload, {
    required String sourceType,
    required String category,
    required String type,
    required String messageType,
  }) {
    if (!(category == 'admin' ||
        sourceType == 'admin_alert' ||
        sourceType == 'registration_attempt' ||
        type.startsWith('admin_') ||
        messageType.startsWith('admin_'))) {
      return null;
    }

    if (_isNewUserRequestNotification(payload) ||
        type == 'registration_attempt' ||
        sourceType == 'registration_attempt') {
      return _normalizeRouteName('/admin-pending-registrations');
    }
    if (_isPendingVerificationNotification(payload) ||
        type.contains('verification') ||
        messageType.contains('verification')) {
      return _normalizeRouteName('/admin-verification-requests');
    }
    if (type.contains('device_access') ||
        messageType.contains('device_access')) {
      return _normalizeRouteName('/admin-device-requests');
    }
    if (type == 'admin_card_print_request' ||
        messageType == 'admin_card_print_request') {
      return _normalizeRouteName('/admin-card-print-requests');
    }
    if (type.contains('prepaid_multipay') ||
        messageType.contains('prepaid_multipay')) {
      return _normalizeRouteName('/admin-prepaid-multipay-approvals');
    }
    if (type.contains('topup') || messageType.contains('topup')) {
      return _normalizeRouteName('/topup-requests');
    }
    if (type.contains('withdrawal') || messageType.contains('withdrawal')) {
      return _normalizeRouteName('/withdrawal-requests');
    }
    if (_hasUserContext(payload)) {
      return _normalizeRouteName('/admin-customers');
    }

    return _normalizeRouteName('/admin-dashboard');
  }

  static String? _resolveAdminRoute(
    Map<String, dynamic> payload, {
    required AppPermissions permissions,
    required String sourceType,
    required String category,
    required String type,
    required String messageType,
  }) {
    if (_isNewUserRequestNotification(payload) ||
        type == 'registration_attempt' ||
        sourceType == 'registration_attempt' ||
        messageType == 'registration_attempt') {
      if (permissions.canManageUsers ||
          permissions.canManageMarketingAccounts) {
        return _normalizeRouteName('/admin-pending-registrations');
      }
    }

    if (_isPendingVerificationNotification(payload) ||
        type.contains('verification') ||
        messageType.contains('verification')) {
      if (permissions.canManageUsers) {
        return _normalizeRouteName('/admin-verification-requests');
      }
    }

    if (type == 'admin_pending_device_access_request' ||
        messageType == 'admin_pending_device_access_request' ||
        type.contains('device_access') ||
        messageType.contains('device_access')) {
      if (permissions.canReviewDevices) {
        return _normalizeRouteName('/admin-device-requests');
      }
    }

    if (type == 'admin_card_print_request' ||
        messageType == 'admin_card_print_request' ||
        sourceType == 'card_print_request') {
      if (permissions.canManageCardPrintRequests) {
        return _normalizeRouteName('/admin-card-print-requests');
      }
    }

    if (type.contains('prepaid_multipay') ||
        messageType.contains('prepaid_multipay')) {
      if (permissions.canManageUsers) {
        return _normalizeRouteName('/admin-prepaid-multipay-approvals');
      }
    }

    if (type.contains('topup') || messageType.contains('topup')) {
      if (permissions.canReviewTopups || permissions.canFinanceTopup) {
        return _normalizeRouteName('/topup-requests');
      }
    }

    if (type.contains('withdrawal') || messageType.contains('withdrawal')) {
      if (permissions.canReviewWithdrawals) {
        return _normalizeRouteName('/withdrawal-requests');
      }
    }

    if (type.contains('transfer') || messageType.contains('transfer')) {
      if (permissions.canViewTransactions || permissions.canFinanceTopup) {
        return _normalizeRouteName('/transactions');
      }
    }

    if (_hasUserContext(payload) && permissions.canViewCustomers) {
      return _normalizeRouteName('/admin-customers');
    }

    if (category == 'admin' || sourceType == 'admin_alert') {
      return _normalizeRouteName('/admin-dashboard');
    }

    return null;
  }

  static bool _isNewUserRequestNotification(Map<String, dynamic> payload) {
    final type = _normalizedText(payload['type']);
    final messageType = _normalizedText(payload['messageType']);

    return type == 'admin_pending_registration_request' ||
        messageType == 'admin_pending_registration_request';
  }

  static bool _isPendingVerificationNotification(Map<String, dynamic> payload) {
    final type = _normalizedText(payload['type']);
    final messageType = _normalizedText(payload['messageType']);
    return type == 'admin_pending_verification_request' ||
        messageType == 'admin_pending_verification_request';
  }

  static bool _isErrorNotification(Map<String, dynamic> payload) {
    final type = _normalizedText(payload['type']);
    final messageType = _normalizedText(payload['messageType']);
    final sourceType = _normalizedText(
      payload['sourceType'] ?? payload['source_type'],
    );
    return const {
          'admin_app_error',
          'admin_client_crash',
          'admin_client_error',
        }.contains(type) ||
        const {
          'admin_app_error',
          'admin_client_crash',
          'admin_client_error',
        }.contains(messageType) ||
        const {
          'admin_app_error',
          'admin_client_crash',
          'admin_client_error',
        }.contains(sourceType) ||
        _firstNonEmptyString(payload, const [
              'traceId',
              'stackTrace',
              'stackTracePreview',
              'errorKind',
              'exceptionClass',
            ]) !=
            null;
  }

  static bool _isAdminUserContextNotification(
    Map<String, dynamic> payload,
    AppPermissions permissions,
  ) {
    if (!permissions.canViewCustomers || !permissions.hasAdminWorkspaceAccess) {
      return false;
    }
    if (!_hasUserContext(payload)) {
      return false;
    }

    final type = _normalizedText(payload['type']);
    final messageType = _normalizedText(payload['messageType']);
    final category = _normalizedText(payload['category']);
    return category == 'admin' ||
        type.startsWith('admin_') ||
        messageType.startsWith('admin_') ||
        type == 'account_event' ||
        type.contains('account') ||
        type.contains('profile') ||
        type.contains('user') ||
        messageType.contains('user') ||
        messageType.contains('member') ||
        messageType.contains('security');
  }

  static bool _hasUserContext(Map<String, dynamic> payload) {
    return _firstNonEmptyString(payload, const [
          'targetUserId',
          'target_user_id',
          'accountId',
          'account_id',
          'userId',
          'user_id',
          'memberId',
          'member_id',
          'customerId',
          'customer_id',
          'username',
          'whatsapp',
        ]) !=
        null;
  }

  static Future<bool> _openAdminCustomerDestination(
    Map<String, dynamic> payload,
    AppPermissions permissions,
  ) async {
    final customer = await _findCustomerForNotification(payload);
    if (customer == null) {
      return false;
    }

    final navigator = AppAlertService.navigatorKey.currentState;
    if (navigator == null) {
      _queuePayload(payload);
      return true;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AdminCustomerScreen(
          customer: customer,
          canManageUsers: permissions.canManageUsers,
          canManageMarketingAccounts: permissions.canManageMarketingAccounts,
          canExport: permissions.canExportCustomerTransactions,
        ),
      ),
    );
    return true;
  }

  static Future<Map<String, dynamic>?> _findCustomerForNotification(
    Map<String, dynamic> payload,
  ) async {
    final userId = _firstNonEmptyString(payload, const [
      'targetUserId',
      'target_user_id',
      'accountId',
      'account_id',
      'userId',
      'user_id',
      'memberId',
      'member_id',
      'customerId',
      'customer_id',
    ]);
    final username = _firstNonEmptyString(payload, const ['username']);
    final whatsapp = _firstNonEmptyString(payload, const ['whatsapp']);

    return _findCustomerByAnyIdentity(
      userId: userId,
      username: username,
      whatsapp: whatsapp,
    );
  }

  static Future<Map<String, dynamic>?> _findPendingRegistration(
    Map<String, dynamic> payload,
  ) async {
    final requestId = _firstNonEmptyString(payload, const [
      'requestId',
      'pendingRegistrationId',
      'sourceId',
    ]);
    final username = _firstNonEmptyString(payload, const ['username']);
    final whatsapp = _firstNonEmptyString(payload, const ['whatsapp']);

    try {
      final requests = await ApiService().getPendingRegistrationRequests();
      for (final request in requests) {
        final candidateId = request['id']?.toString().trim() ?? '';
        final candidateUsername =
            request['username']?.toString().trim().toLowerCase() ?? '';
        final candidateWhatsapp = request['whatsapp']?.toString().trim() ?? '';

        if (requestId != null &&
            requestId.isNotEmpty &&
            candidateId == requestId) {
          return request;
        }
        if (username != null &&
            username.isNotEmpty &&
            candidateUsername == username.toLowerCase()) {
          return request;
        }
        if (whatsapp != null &&
            whatsapp.isNotEmpty &&
            candidateWhatsapp == whatsapp) {
          return request;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<Map<String, dynamic>?> _findCustomerForRegistrationNotification(
    Map<String, dynamic> payload,
  ) async {
    final userId = _firstNonEmptyString(payload, const ['userId']);
    final username = _firstNonEmptyString(payload, const ['username']);
    final whatsapp = _firstNonEmptyString(payload, const ['whatsapp']);

    return _findCustomerByAnyIdentity(
      userId: userId,
      username: username,
      whatsapp: whatsapp,
    );
  }

  static Future<Map<String, dynamic>?> _findCustomerByAnyIdentity({
    String? userId,
    String? username,
    String? whatsapp,
  }) async {
    for (final query in [userId, username, whatsapp]) {
      if (query == null || query.isEmpty) {
        continue;
      }

      try {
        final response = await ApiService().getAdminCustomers(
          query: query,
          page: 1,
          perPage: 20,
        );
        final customers = List<Map<String, dynamic>>.from(
          response['customers'] as List? ?? const [],
        );
        for (final customer in customers) {
          final candidateId = customer['id']?.toString().trim() ?? '';
          final candidateUsername =
              customer['username']?.toString().trim().toLowerCase() ?? '';
          final candidateWhatsapp =
              customer['whatsapp']?.toString().trim() ?? '';

          if (userId != null && userId.isNotEmpty && candidateId == userId) {
            return customer;
          }
          if (username != null &&
              username.isNotEmpty &&
              candidateUsername == username.toLowerCase()) {
            return customer;
          }
          if (whatsapp != null &&
              whatsapp.isNotEmpty &&
              candidateWhatsapp == whatsapp) {
            return customer;
          }
        }
      } catch (_) {
        // Fall through to the next query candidate.
      }
    }

    return null;
  }

  static Map<String, dynamic> _payloadFromNotificationItem(
    Map<String, dynamic> item,
  ) {
    final payload = <String, dynamic>{
      'type': item['type'],
      'category': item['category'],
      'sourceType': item['sourceType'],
      'sourceId': item['sourceId'],
      'title': item['title'],
      'body': item['body'],
    };

    final rawData = item['data'];
    if (rawData is Map<String, dynamic>) {
      payload.addAll(rawData);
    } else if (rawData is Map) {
      payload.addAll(Map<String, dynamic>.from(rawData));
    }

    return _normalizePayload(payload);
  }

  static Map<String, dynamic> _normalizePayload(Map<String, dynamic> payload) {
    final normalized = <String, dynamic>{};

    payload.forEach((key, value) {
      if (value == null) {
        return;
      }
      normalized[key] = _decodeStructuredValue(value);
    });

    final metadata = normalized['metadata'];
    if (metadata is Map) {
      normalized['metadata'] = Map<String, dynamic>.from(metadata);
    }

    return normalized;
  }

  static dynamic _decodeStructuredValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key, _decodeStructuredValue(nestedValue)),
      );
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value).map(
        (key, nestedValue) =>
            MapEntry(key, _decodeStructuredValue(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_decodeStructuredValue).toList();
    }
    if (value is! String) {
      return value;
    }

    final text = value.trim();
    if (text.isEmpty) {
      return value;
    }
    if (!(text.startsWith('{') || text.startsWith('['))) {
      return value;
    }

    try {
      return _decodeStructuredValue(jsonDecode(text));
    } catch (_) {
      return value;
    }
  }

  static Map<String, dynamic> _decodeMap(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return const <String, dynamic>{};
  }

  static String? _normalizeRouteName(String? routeName) {
    final normalized = routeName?.trim() ?? '';
    if (normalized.isEmpty || !normalized.startsWith('/')) {
      return null;
    }
    return OfflineSessionService.resolveRoute(normalized);
  }

  static String _normalizedText(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }
}
