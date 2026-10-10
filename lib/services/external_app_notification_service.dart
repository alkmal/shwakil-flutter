import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalAppNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'com.alkmal.shwakil/external_notifications',
  );

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> hasNotificationAccess() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openAccessSettings');
  }

  Future<List<Map<String, dynamic>>> getApps() async {
    if (!isSupported) return <Map<String, dynamic>>[];
    final result =
        await _channel.invokeListMethod<dynamic>('getApps') ?? const [];
    return result
        .whereType<Map>()
        .map((app) => Map<String, dynamic>.from(app))
        .toList();
  }

  Future<List<String>> getSelectedPackages() async {
    if (!isSupported) return <String>[];
    return (await _channel.invokeListMethod<String>('getSelectedPackages')) ??
        <String>[];
  }

  Future<void> setSelectedPackages(List<String> packages) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setSelectedPackages', <String, dynamic>{
      'packages': packages,
    });
  }

  Future<void> setActiveWorkspaceId(String? workspaceId) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setActiveWorkspaceId', <String, dynamic>{
      'workspaceId': workspaceId,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingEvents() async {
    if (!isSupported) return <Map<String, dynamic>>[];
    final result =
        await _channel.invokeListMethod<dynamic>('getPendingEvents') ??
        const [];
    return result
        .whereType<Map>()
        .map((event) => Map<String, dynamic>.from(event))
        .toList();
  }

  Future<void> acknowledgeEvents(List<String> eventIds) async {
    if (!isSupported || eventIds.isEmpty) return;
    await _channel.invokeMethod<void>('acknowledgeEvents', <String, dynamic>{
      'eventIds': eventIds,
    });
  }
}
