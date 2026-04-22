import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../localization/app_localization.dart';
import '../localization/app_strings_ar.dart';
import '../localization/app_strings_en.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'app_version_service.dart';
import 'local_notification_service.dart';
import 'local_security_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase is optional until the native config files are added.
  }
}

class RealtimeNotificationService {
  RealtimeNotificationService._();

  static final StreamController<Map<String, dynamic>>
  _balanceUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get balanceUpdatesStream =>
      _balanceUpdatesController.stream;
  static final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get notificationsStream =>
      _notificationsController.stream;

  static final AuthService _authService = AuthService();
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static bool _initialized = false;
  static bool _firebaseAvailable = false;
  static bool _backgroundHandlerRegistered = false;

  static void registerBackgroundHandler() {
    if (kIsWeb || _backgroundHandlerRegistered) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  static Future<void> start() async {
    try {
      await _ensureInitialized();
    } catch (_) {
      return;
    }
    if (!_firebaseAvailable) {
      return;
    }

    await _syncCurrentToken();
    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((token) => unawaited(_registerToken(token)));
  }

  static Future<void> stop() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  static void notifyBalanceUpdated([Map<String, dynamic> payload = const {}]) {
    if (!_balanceUpdatesController.isClosed) {
      _balanceUpdatesController.add(payload);
    }
  }

  static void notifyNotificationsUpdated([
    Map<String, dynamic> payload = const {},
  ]) {
    if (!_notificationsController.isClosed) {
      _notificationsController.add(payload);
    }
  }

  static Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    try {
      await Firebase.initializeApp();
      registerBackgroundHandler();

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _waitForApplePushToken(messaging);

      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationOpen(initialMessage);
      }

      _firebaseAvailable = true;
    } catch (_) {
      _firebaseAvailable = false;
    }
  }

  static Future<void> _syncCurrentToken() async {
    try {
      await _waitForApplePushToken(FirebaseMessaging.instance);
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        return;
      }
      await _registerToken(token);
    } catch (_) {
      // Push token sync is optional and should never break the app.
    }
  }

  static Future<void> _registerToken(String token) async {
    final authToken = await _authService.token();
    if (authToken == null || authToken.isEmpty) {
      return;
    }

    final deviceId = await LocalSecurityService.getOrCreateDeviceId();
    final packageInfo = await PackageInfo.fromPlatform();
    final headers = <String, String>{
      ...await AppVersionService.publicHeaders(includeJsonContentType: true),
      'Authorization': 'Bearer $authToken',
    };

    try {
      await http
          .post(
            AppConfig.apiUri('notifications/push-token'),
            headers: headers,
            body: jsonEncode({
              'token': token,
              'platform': defaultTargetPlatform.name,
              'deviceId': deviceId,
              'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
            }),
          )
          .timeout(const Duration(seconds: 5));
    } on SocketException {
      // No internet / DNS issue: keep the app running and retry later.
    } on http.ClientException {
      // Network client errors should not surface to the user here.
    } on TimeoutException {
      // Slow networks should not block app startup or navigation.
    } catch (_) {
      // Token registration is best-effort only.
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final payload = Map<String, dynamic>.from(message.data);
    final type = payload['type']?.toString() ?? '';
    if (type.contains('balance') ||
        type.contains('topup') ||
        type.contains('transfer') ||
        type.contains('withdrawal') ||
        type.contains('card')) {
      notifyBalanceUpdated(payload);
    }
    notifyNotificationsUpdated(payload);

    final notification = message.notification;
    final title = notification?.title ?? payload['title']?.toString() ?? '';
    final body = notification?.body ?? payload['body']?.toString() ?? '';
    if (title.isNotEmpty || body.isNotEmpty) {
      unawaited(
        LocalNotificationService.showPushNotification(
          title: title.isEmpty ? _tr('services_app_alert_service.004') : title,
          body: body,
        ),
      );
    }
  }

  static void _handleNotificationOpen(RemoteMessage message) {
    final payload = Map<String, dynamic>.from(message.data);
    if (payload.isNotEmpty) {
      notifyBalanceUpdated(payload);
      notifyNotificationsUpdated(payload);
    }
  }

  static Future<void> _waitForApplePushToken(FirebaseMessaging messaging) async {
    if (kIsWeb || !Platform.isIOS) {
      return;
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static String _tr(String key) {
    if ((AppLocaleService.instance.locale?.languageCode ?? 'ar') == 'en') {
      return appStringsEn[key] ?? key;
    }
    return appStringsAr[key] ?? appStringsEn[key] ?? key;
  }
}
