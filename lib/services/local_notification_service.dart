import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

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
      const AndroidNotificationChannel(
        'account_updates',
        'تحديثات الحساب',
        description: 'إشعارات الحساب والطلبات والتنبيهات المهمة',
        importance: Importance.max,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'balance_updates',
        'ØªØ­Ø¯ÙŠØ«Ø§Øª Ø§Ù„Ø±ØµÙŠØ¯',
        description: 'Ø¥Ø´Ø¹Ø§Ø±Ø§Øª Ø¥Ø¶Ø§ÙØ© ÙˆØ®ØµÙ… Ø§Ù„Ø±ØµÙŠØ¯',
        importance: Importance.max,
      ),
    );
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

    _initialized = true;
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

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'balance_updates',
        'تحديثات الرصيد',
        channelDescription: 'إشعارات إضافة وخصم الرصيد',
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
    String channelName = 'تحديثات الحساب',
  }) async {
    if (kIsWeb) {
      return;
    }

    await initialize();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'إشعارات الحساب والطلبات والتنبيهات المهمة',
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
}
