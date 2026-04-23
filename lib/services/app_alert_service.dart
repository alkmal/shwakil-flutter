import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_localization.dart';
import '../localization/app_strings_ar.dart';
import '../localization/app_strings_en.dart';
import '../utils/app_theme.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'app_version_service.dart';
import 'error_message_service.dart';
import 'local_security_service.dart';
import 'offline_session_service.dart';
import 'realtime_notification_service.dart';

enum AppAlertType { success, error, info }

class AppAlertService {
  AppAlertService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> showSuccess(
    BuildContext context, {
    String? title,
    required String message,
  }) {
    return _show(
      context,
      type: AppAlertType.success,
      title: title ?? context.loc.tr('services_app_alert_service.001'),
      message: message,
    );
  }

  static Future<void> showError(
    BuildContext context, {
    String? title,
    required String message,
    Map<String, dynamic>? extraContext,
  }) {
    return _show(
      context,
      type: AppAlertType.error,
      title: title ?? context.loc.tr('services_app_alert_service.002'),
      message: message,
      extraContext: extraContext,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    String? title,
    required String message,
  }) {
    return _show(
      context,
      type: AppAlertType.info,
      title: title ?? context.loc.tr('services_app_alert_service.003'),
      message: message,
    );
  }

  static Future<void> showGlobalError({
    required String title,
    required String message,
    Map<String, dynamic>? extraContext,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('Global alert skipped: $title - $message');
      return Future.value();
    }

    return showError(
      context,
      title: title,
      message: message,
      extraContext: extraContext,
    );
  }

  static Future<void> reportUnhandledCrash({
    required String title,
    required String message,
    String? details,
    String? stackTrace,
    String? route,
    Map<String, dynamic>? extraContext,
  }) async {
    try {
      final authService = AuthService();
      final token = await authService.token();
      final currentUser = await authService.currentUser();

      final payload = <String, dynamic>{
        'title': ErrorMessageService.sanitize(title),
        'message': ErrorMessageService.sanitize(message),
        'appName':
            navigatorKey.currentContext?.loc.tr(
              'services_app_alert_service.004',
            ) ??
            'Shwakil',
        'platform': defaultTargetPlatform.name,
        'route': route ?? '',
      };

      if (details != null && details.trim().isNotEmpty) {
        payload['details'] = details.trim();
      }
      if (stackTrace != null && stackTrace.trim().isNotEmpty) {
        payload['stackTrace'] = stackTrace.trim();
      }

      if (currentUser != null) {
        payload['accountId'] = currentUser['id']?.toString();
        payload['username'] = currentUser['username']?.toString();
        payload['fullName'] = currentUser['fullName']?.toString();
        payload['whatsapp'] = currentUser['whatsapp']?.toString();
        payload['role'] = (currentUser['roleLabel'] ?? currentUser['role'])
            ?.toString();
        payload['balance'] = currentUser['balance']?.toString();
      }

      (extraContext ?? const <String, dynamic>{}).forEach((key, value) {
        if (value == null) {
          return;
        }
        final text = value.toString().trim();
        if (text.isEmpty) {
          return;
        }
        payload[key] = text;
      });

      await http.post(
        AppConfig.apiUri('app/report-crash'),
        headers: {
          ...await AppVersionService.publicHeaders(includeJsonContentType: true),
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  static Future<void> _show(
    BuildContext context, {
    required AppAlertType type,
    required String title,
    required String message,
    Map<String, dynamic>? extraContext,
  }) async {
    final style = _styleFor(type);
    final cleanTitle = ErrorMessageService.sanitize(title);
    final cleanMessage = ErrorMessageService.sanitize(message);
    final supportNumber = _extractWhatsAppNumber(cleanMessage);
    final returnToHomeOnAcknowledge =
        type == AppAlertType.error &&
        _shouldReturnHomeOnAcknowledge(cleanMessage);
    final canRelogin =
        type == AppAlertType.error && _shouldOfferRelogin(cleanMessage);

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x260F172A),
                blurRadius: 28,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: style.softColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: style.color.withValues(alpha: 0.18),
                    width: 2,
                  ),
                ),
                child: Icon(style.icon, color: style.color, size: 58),
              ),
              const SizedBox(height: 22),
              Text(
                cleanTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: style.color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                cleanMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.7,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              if (supportNumber != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(supportNumber),
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(
                      context.loc.tr('services_app_alert_service.005'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF16A34A),
                      side: const BorderSide(color: Color(0xFF16A34A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (canRelogin) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await _restartLoginFlow();
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      context.loc.tr('services_app_alert_service.009'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    if (returnToHomeOnAcknowledge) {
                      final navigator = navigatorKey.currentState;
                      if (navigator != null) {
                        navigator.pushNamedAndRemoveUntil(
                          '/home',
                          (route) => false,
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: style.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    context.loc.tr('services_app_alert_service.006'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _shouldReturnHomeOnAcknowledge(String message) {
    return _messageContainsAny(message, 'services_app_alert_service.007');
  }

  static bool _shouldOfferRelogin(String message) {
    return _messageContainsAny(message, 'services_error_message_service.010') ||
        _messageContainsAny(message, 'services_error_message_service.011');
  }

  static Future<void> _restartLoginFlow() async {
    final authService = AuthService();
    await RealtimeNotificationService.stop();
    await authService.logout();
    await LocalSecurityService.clearTrustedState();
    OfflineSessionService.setOfflineMode(false);

    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  static Future<void> _openWhatsApp(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String? _extractWhatsAppNumber(String message) {
    if (!_messageContainsAny(message, 'services_app_alert_service.008')) {
      return null;
    }
    final match = RegExp(r'(\+?\d[\d\s-]{7,}\d)').firstMatch(message);
    if (match == null) {
      return null;
    }
    final digits = match.group(0)?.replaceAll(RegExp(r'\D'), '') ?? '';
    return digits.length >= 8 ? digits : null;
  }

  static bool _messageContainsAny(String message, String key) {
    final current = navigatorKey.currentContext?.loc.tr(key);
    final arabic = appStringsAr[key];
    final english = appStringsEn[key];
    return [current, arabic, english].any(
      (candidate) => candidate != null && candidate.isNotEmpty && message.contains(candidate),
    );
  }

  static _AlertStyle _styleFor(AppAlertType type) {
    switch (type) {
      case AppAlertType.success:
        return _AlertStyle(
          color: AppTheme.success,
          softColor: AppTheme.successLight,
          icon: Icons.check_circle_rounded,
        );
      case AppAlertType.error:
        return _AlertStyle(
          color: AppTheme.error,
          softColor: AppTheme.errorLight,
          icon: Icons.cancel_rounded,
        );
      case AppAlertType.info:
        return _AlertStyle(
          color: AppTheme.info,
          softColor: AppTheme.infoLight,
          icon: Icons.info_rounded,
        );
    }
  }
}

class _AlertStyle {
  const _AlertStyle({
    required this.color,
    required this.softColor,
    required this.icon,
  });

  final Color color;
  final Color softColor;
  final IconData icon;
}
