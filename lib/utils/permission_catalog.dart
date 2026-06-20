import 'package:flutter/widgets.dart';

import '../localization/app_localization.dart';

/// Central place for permission labels and their explanations.
///
/// We intentionally keep this in one file because the same permissions are
/// shown in multiple screens (admin customer, sub-users, settings), and we
/// want consistent wording.
class PermissionCatalog {
  static const List<Map<String, Object>> groups = [
    {
      'titleKey': 'permission_catalog.group_general',
      'icon': IconData(0xe88a, fontFamily: 'MaterialIcons'),
      'keys': [
        'canViewBalance',
        'canViewTransactions',
        'canViewInventory',
        'canViewContact',
        'canViewLocations',
        'canViewUsagePolicy',
        'canViewSecuritySettings',
        'canViewAccountSettings',
        'canRequestVerification',
        'canViewAffiliateCenter',
      ],
    },
    {
      'titleKey': 'permission_catalog.group_card_issuance',
      'icon': IconData(0xe870, fontFamily: 'MaterialIcons'),
      'keys': [
        'canIssueCards',
        'canIssuePrivateCards',
        'canIssueSubShekelCards',
        'canIssueHighValueCards',
        'canIssueSingleUseTickets',
        'canIssueAppointmentTickets',
        'canIssueQueueTickets',
      ],
    },
    {
      'titleKey': 'permission_catalog.group_card_reading',
      'icon': IconData(0xe3f4, fontFamily: 'MaterialIcons'),
      'keys': [
        'canScanCards',
        'canOfflineCardScan',
        'canReviewCards',
        'canRedeemCards',
        'canViewPrivateCards',
        'canReadOwnPrivateCardsOnly',
        'canDeleteCards',
        'canResellCards',
      ],
    },
    {
      'titleKey': 'permission_catalog.group_wallet',
      'icon': IconData(0xe8cc, fontFamily: 'MaterialIcons'),
      'keys': [
        'canTransfer',
        'canWithdraw',
        'canUsePrepaidMultipayCards',
        'canAcceptPrepaidMultipayPayments',
        'canUsePrepaidMultipayNfc',
        'canRequestCardPrinting',
        'canManageCardPrintRequests',
      ],
    },
    {
      'titleKey': 'permission_catalog.group_admin',
      'icon': IconData(0xe8b8, fontFamily: 'MaterialIcons'),
      'keys': [
        'canViewCustomers',
        'canLookupMembers',
        'canManageUsers',
        'canFinanceTopup',
        'canReviewTopups',
        'canReviewWithdrawals',
        'canReviewDevices',
        'canManageMarketingAccounts',
        'canViewSubUsers',
        'canManageSubUsers',
        'canManageLocations',
        'canManageSystemSettings',
        'canManageDebtBook',
        'canExportCustomerTransactions',
      ],
    },
    {
      'titleKey': 'permission_catalog.group_store_marketplace',
      'icon': IconData(0xe8d1, fontFamily: 'MaterialIcons'),
      'keys': [
        'canAccessStoreManagement',
        'canManageStoreInventory',
        'canCreateStoreSales',
        'canCreateStorePurchases',
        'canManageStoreDebts',
        'canEditStorePrices',
        'canViewStoreProfits',
        'canViewStoreReports',
        'canViewPublicStores',
        'canBuyPublicStoreProducts',
        'canPublishStorefront',
        'canManagePublicStorefront',
        'canManagePublicMarketplace',
      ],
    },
  ];

  static String label(BuildContext context, String key) {
    final l = context.loc;
    return l.tr(_labelKey(key), fallback: key);
  }

  static String description(BuildContext context, String key) {
    final l = context.loc;
    return l.tr(_descriptionKey(key), fallback: '');
  }

  static String groupTitle(BuildContext context, Map<String, Object> group) {
    final key = group['titleKey']?.toString() ?? '';
    return context.loc.tr(key, fallback: key);
  }

  static String _labelKey(String permissionKey) =>
      'permission_catalog.label.$permissionKey';

  static String _descriptionKey(String permissionKey) =>
      'permission_catalog.description.$permissionKey';
}
