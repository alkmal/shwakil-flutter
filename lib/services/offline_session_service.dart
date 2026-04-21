import 'package:flutter/foundation.dart';

class OfflineSessionService {
  OfflineSessionService._();

  static final ValueNotifier<bool> _isOfflineMode =
      ValueNotifier<bool>(false);

  static ValueListenable<bool> get listenable => _isOfflineMode;

  static bool get isOfflineMode => _isOfflineMode.value;

  static void setOfflineMode(bool value) {
    if (_isOfflineMode.value == value) {
      return;
    }
    _isOfflineMode.value = value;
  }

  static const Set<String> _offlineAllowedRoutes = {
    '/scan-card-offline',
    '/offline-center',
    '/debt-book',
    '/login-offline',
    '/unlock',
  };

  static bool canOpenRoute(String routeName) {
    if (!isOfflineMode) {
      return true;
    }
    return _offlineAllowedRoutes.contains(routeName);
  }
}
