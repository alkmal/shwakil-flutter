import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'network_client_service.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();
  static final http.Client _client = NetworkClientService.client;

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _started = false;
  DateTime? _lastCheckedAt;
  static const Duration _minimumCheckGap = Duration(seconds: 4);

  Future<void> startMonitoring({
    Duration interval = const Duration(seconds: 15),
  }) async {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(checkNow());
    _pollingTimer = Timer.periodic(interval, (_) {
      unawaited(checkNow());
    });
  }

  Future<bool> checkNow() async {
    if (_isChecking) {
      return isOnline.value;
    }
    final now = DateTime.now();
    final lastCheckedAt = _lastCheckedAt;
    if (lastCheckedAt != null &&
        now.difference(lastCheckedAt) < _minimumCheckGap) {
      return isOnline.value;
    }
    _isChecking = true;
    _lastCheckedAt = now;
    try {
      final response = await _client
          .get(AppConfig.apiUri('health'))
          .timeout(const Duration(seconds: 3));
      final nextValue = response.statusCode < 500;
      if (isOnline.value != nextValue) {
        isOnline.value = nextValue;
      }
      return nextValue;
    } catch (_) {
      if (isOnline.value) {
        isOnline.value = false;
      }
      return false;
    } finally {
      _isChecking = false;
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _started = false;
  }
}
