import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'auth_service.dart';
import 'error_message_service.dart';
import '../utils/app_theme.dart';

enum AppAlertType { success, error, info }

class AppAlertService {
  AppAlertService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> showSuccess(
    BuildContext context, {
    String title = 'نجاح',
    required String message,
  }) {
    return _show(
      context,
      type: AppAlertType.success,
      title: title,
      message: message,
    );
  }

  static Future<void> showError(
    BuildContext context, {
    String title = 'خطأ',
    required String message,
    Map<String, dynamic>? extraContext,
  }) {
    return _show(
      context,
      type: AppAlertType.error,
      title: title,
      message: message,
      extraContext: extraContext,
    );
  }

  static Future<void> showInfo(
    BuildContext context, {
    String title = 'معلومة',
    required String message,
  }) {
    return _show(
      context,
      type: AppAlertType.info,
      title: title,
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

    if (type == AppAlertType.error) {
      unawaited(
        _reportClientError(
          cleanTitle,
          cleanMessage,
          context,
          extraContext ?? const {},
        ),
      );
    }

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
                    label: const Text(
                      'تواصل عبر واتساب',
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
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: style.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'موافق',
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

  static Future<void> _reportClientError(
    String title,
    String message,
    BuildContext context,
    Map<String, dynamic> extraContext,
  ) async {
    try {
      final routeName = ModalRoute.of(context)?.settings.name ?? '';
      final authService = AuthService();
      final token = await authService.token();
      final currentUser = await authService.currentUser();

      final payload = <String, dynamic>{
        'title': title,
        'message': message,
        'appName': 'شواكل',
        'platform': defaultTargetPlatform.name,
        'route': routeName,
      };

      if (currentUser != null) {
        payload['accountId'] = currentUser['id']?.toString();
        payload['username'] = (currentUser['username'] ?? payload['username'])
            ?.toString();
        payload['fullName'] = currentUser['fullName']?.toString();
        payload['whatsapp'] = (currentUser['whatsapp'] ?? payload['whatsapp'])
            ?.toString();
        payload['role'] = (currentUser['roleLabel'] ?? currentUser['role'])
            ?.toString();
        payload['balance'] = currentUser['balance']?.toString();
      }

      extraContext.forEach((key, value) {
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
        AppConfig.apiUri('app/report-error'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } catch (_) {}
  }

  static Future<void> _openWhatsApp(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String? _extractWhatsAppNumber(String message) {
    if (!message.contains('واتس')) {
      return null;
    }
    final match = RegExp(r'(\+?\d[\d\s-]{7,}\d)').firstMatch(message);
    if (match == null) {
      return null;
    }
    final digits = match.group(0)?.replaceAll(RegExp(r'\D'), '') ?? '';
    return digits.length >= 8 ? digits : null;
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
