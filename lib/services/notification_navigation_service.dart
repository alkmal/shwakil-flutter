import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/admin_customer_screen.dart';
import '../utils/app_permissions.dart';
import 'api_service.dart';
import 'app_alert_service.dart';
import 'auth_service.dart';
import 'offline_session_service.dart';

class NotificationNavigationService {
  NotificationNavigationService._();

  static Map<String, dynamic>? _pendingPayload;
  static int _pendingAttempts = 0;
  static const int _maxPendingAttempts = 8;

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

    final route = _resolveRoute(
      payload,
      includeDefaultNotificationsRoute: includeDefaultNotificationsRoute,
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

    await navigator.pushNamed(route);
  }

  static Future<bool> _openCustomDestination(
    Map<String, dynamic> payload, {
    required bool includeDefaultNotificationsRoute,
  }) async {
    if (_isPendingVerificationNotification(payload)) {
      final route = _normalizeRouteName('/admin-verification-requests');
      final navigator = AppAlertService.navigatorKey.currentState;
      if (route == null || navigator == null) {
        _queuePayload(payload);
        return true;
      }
      await navigator.pushNamed(route);
      return true;
    }

    if (!_isNewUserRequestNotification(payload)) {
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
        await navigator.pushNamed(route);
      }
      return true;
    }

    final customer = await _findCustomerForRegistrationNotification(payload);
    if (customer == null) {
      final fallbackRoute = _resolveRoute(
        payload,
        includeDefaultNotificationsRoute: includeDefaultNotificationsRoute,
      );
      if (fallbackRoute == null || fallbackRoute.isEmpty) {
        return true;
      }
      final navigator = AppAlertService.navigatorKey.currentState;
      if (navigator == null) {
        _queuePayload(payload);
        return true;
      }
      await navigator.pushNamed(fallbackRoute);
      return true;
    }

    final currentUser = await AuthService().currentUser();
    final permissions = AppPermissions.fromUser(currentUser);
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
      unawaited(
        _openResolvedPayload(
          pending,
          includeDefaultNotificationsRoute: true,
        ).whenComplete(() {
          if (_pendingPayload == null || identical(_pendingPayload, pending)) {
            _pendingPayload = null;
            _pendingAttempts = 0;
          }
        }),
      );
    });
  }

  static String? _resolveRoute(
    Map<String, dynamic> payload, {
    required bool includeDefaultNotificationsRoute,
  }) {
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

    if (const {
      'card_print_request',
      'card_print_request_completed',
      'card_print_request_refund',
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

    if (type.contains('withdrawal') &&
        (sourceType == 'admin_custom_notification' ||
            category == 'account' ||
            category == 'general')) {
      return _normalizeRouteName('/withdrawal-requests');
    }

    if (type.contains('topup') &&
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

    if (type.contains('verification')) {
      return _normalizeRouteName('/account-verification');
    }

    if (type.contains('security') ||
        type.contains('device') ||
        type.contains('password') ||
        type.contains('credential')) {
      return _normalizeRouteName('/security-settings');
    }

    if (category == 'account' ||
        type == 'account_event' ||
        type.startsWith('account_') ||
        type.contains('profile') ||
        type.contains('registration')) {
      return _normalizeRouteName('/account-settings');
    }

    if (sourceType == 'admin_custom_notification' ||
        includeDefaultNotificationsRoute) {
      return _normalizeRouteName('/notifications');
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
