import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../localization/app_localization.dart';
import '../localization/app_strings_ar.dart';
import '../localization/app_strings_en.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _permissionsRequested = false;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'account_updates',
        _tr('services_local_notification_service.001'),
        description: _tr('services_local_notification_service.002'),
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'balance_updates',
        _tr('services_local_notification_service.003'),
        description: _tr('services_local_notification_service.004'),
        importance: Importance.max,
      ),
    );
    _initialized = true;
  }

  static Future<void> ensurePermissionsRequested() async {
    if (_permissionsRequested || kIsWeb) {
      return;
    }
    await initialize();

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _permissionsRequested = true;
  }

  static Future<void> showBalanceChange({
    required String title,
    required String body,
    bool isCredit = true,
  }) async {
    if (kIsWeb) {
      return;
    }

    await initialize();
    await ensurePermissionsRequested();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'balance_updates',
        _tr('services_local_notification_service.003'),
        channelDescription: _tr('services_local_notification_service.004'),
        importance: Importance.max,
        priority: Priority.high,
        color: isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static Future<void> showPushNotification({
    required String title,
    required String body,
    String channelId = 'account_updates',
    String? channelName,
  }) async {
    if (kIsWeb) {
      return;
    }

    await initialize();
    await ensurePermissionsRequested();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName ?? _tr('services_local_notification_service.001'),
        channelDescription: _tr('services_local_notification_service.002'),
        importance: Importance.max,
        priority: Priority.high,
        color: const Color(0xFF0F766E),
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static String _tr(String key) {
    final current = AppLocaleService.instance.locale;
    if ((current?.languageCode ?? 'ar') == 'en') {
      return appStringsEn[key] ?? key;
    }
    return appStringsAr[key] ?? appStringsEn[key] ?? key;
  }
}
