import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _started = false;

  Future<void> startMonitoring({
    Duration interval = const Duration(seconds: 8),
  }) async {
    if (_started) {
      return;
    }
    _started = true;
    await checkNow();
    _pollingTimer = Timer.periodic(interval, (_) {
      unawaited(checkNow());
    });
  }

  Future<bool> checkNow() async {
    if (_isChecking) {
      return isOnline.value;
    }
    _isChecking = true;
    try {
      final response = await http
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
