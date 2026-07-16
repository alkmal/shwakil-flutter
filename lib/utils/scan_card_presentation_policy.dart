import 'app_permissions.dart';

/// Keeps scan-screen visibility decisions consistent and easy to verify.
///
/// This class only controls presentation. It does not grant any backend
/// capability and must always be used in addition to the server permissions.
class ScanCardPresentationPolicy {
  const ScanCardPresentationPolicy._();

  static bool canShowNfc(
    Map<String, dynamic>? user, {
    required bool offlineMode,
  }) {
    if (offlineMode) {
      return false;
    }
    return AppPermissions.fromUser(user).canAcceptPrepaidMultipayContactless;
  }

  static bool canShowOfflineMode(Map<String, dynamic>? user) {
    return AppPermissions.fromUser(user).canOfflineCardScan;
  }

  static bool canRevealUsageIdentity(
    Map<String, dynamic>? user, {
    required bool offlineMode,
  }) {
    if (offlineMode) {
      return false;
    }
    final permissions = AppPermissions.fromUser(user);
    return permissions.isAdminRole || permissions.isSupportRole;
  }
}
