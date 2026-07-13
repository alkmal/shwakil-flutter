import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/app_permissions.dart';

void main() {
  group('administrative workspace permissions', () {
    test('system settings permission owns settings-managed workflows', () {
      final permissions = AppPermissions.fromUser({
        'permissions': {
          'canManageSystemSettings': true,
          'canManageUsers': false,
        },
      });

      expect(permissions.canManageSystemSettings, isTrue);
      expect(permissions.canManageUsers, isFalse);
      expect(permissions.hasAdminWorkspaceAccess, isTrue);
      expect(permissions.canManagePrepaidMultipayApprovals, isTrue);
      expect(permissions.canManagePermissionTemplates, isTrue);
      expect(permissions.canManageAdminNotifications, isTrue);
      expect(permissions.canViewAdminCardScanReports, isFalse);
    });

    test('user management does not imply system settings management', () {
      final permissions = AppPermissions.fromUser({
        'permissions': {
          'canManageSystemSettings': false,
          'canManageUsers': true,
        },
      });

      expect(permissions.canManageUsers, isTrue);
      expect(permissions.canManageSystemSettings, isFalse);
      expect(permissions.hasAdminWorkspaceAccess, isTrue);
      expect(permissions.canManagePrepaidMultipayApprovals, isFalse);
      expect(permissions.canManagePermissionTemplates, isFalse);
      expect(permissions.canManageAdminNotifications, isFalse);
      expect(permissions.canViewAdminCardScanReports, isTrue);
    });
  });
}
