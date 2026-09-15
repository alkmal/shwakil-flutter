import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/app_permissions.dart';

void main() {
  group('administrative workspace permissions', () {
    test(
      'administrators can manage subscriptions without a duplicated flag',
      () {
        final permissions = AppPermissions.fromUser({
          'permissions': {'role': 'admin', 'canIssueCards': false},
        });

        expect(permissions.canManageSubscriptions, isTrue);
      },
    );

    test('card issuers can manage subscriptions', () {
      final permissions = AppPermissions.fromUser({
        'permissions': {'canIssueCards': true},
      });

      expect(permissions.canManageSubscriptions, isTrue);
    });

    test('regular users cannot open subscription management', () {
      final permissions = AppPermissions.fromUser({
        'permissions': {'canIssueCards': false},
      });

      expect(permissions.canManageSubscriptions, isFalse);
    });

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
