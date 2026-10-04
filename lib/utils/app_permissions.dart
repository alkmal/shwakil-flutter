class AppPermissions {
  const AppPermissions._(this._raw);

  factory AppPermissions.fromUser(Map<String, dynamic>? user) {
    final rawPermissions = _coerceMap(user?['permissions']);
    if (user == null) {
      return AppPermissions._(rawPermissions);
    }

    final merged = <String, dynamic>{...rawPermissions};
    for (final key in _knownBooleanKeys) {
      if (!merged.containsKey(key) && user.containsKey(key)) {
        merged[key] = user[key];
      }
    }

    // بعض الجلسات القديمة تحفظ isSubUser أعلى كائن المستخدم بدل كائن
    // permissions؛ يجب أن تبقى صلاحيات التابع ظاهرة بعد تحديث التطبيق.
    if (!merged.containsKey('isSubUser') && user['isSubUser'] != null) {
      merged['isSubUser'] = user['isSubUser'];
    }
    if (!merged.containsKey('parentUserId') && user['parentUserId'] != null) {
      merged['parentUserId'] = user['parentUserId'];
    }

    if (!merged.containsKey('role') && user['role'] != null) {
      merged['role'] = user['role'];
    }
    if (!merged.containsKey('roleLabel') && user['roleLabel'] != null) {
      merged['roleLabel'] = user['roleLabel'];
    }

    return AppPermissions._(merged);
  }

  final Map<String, dynamic> _raw;

  static const List<String> _knownBooleanKeys = [
    'canViewBalance',
    'canViewTransactions',
    'canViewInventory',
    'canViewQuickTransfer',
    'canViewContact',
    'canViewLocations',
    'canViewUsagePolicy',
    'canViewSecuritySettings',
    'canViewAccountSettings',
    'canRequestVerification',
    'canIssueCards',
    'canIssueSubShekelCards',
    'canIssueHighValueCards',
    'canIssuePrivateCards',
    'canIssueSingleUseTickets',
    'canIssueAppointmentTickets',
    'canIssueQueueTickets',
    'canViewPrivateCards',
    'canReadOwnPrivateCardsOnly',
    'canPrintCards',
    'canDeleteCards',
    'canRequestCardPrinting',
    'canScanCards',
    'canOfflineCardScan',
    'canMonitorOfflineCards',
    'canTransfer',
    'canWithdraw',
    'canReviewCards',
    'canResellCards',
    'canUsePrepaidMultipayCards',
    'canReloadAnyPrepaidMultipayCard',
    'canAcceptPrepaidMultipayPayments',
    'canUsePrepaidMultipayNfc',
    'canUseExternalCardStore',
    'canRedeemCards',
    'canViewCustomers',
    'canLookupMembers',
    'canManageUsers',
    'canFinanceTopup',
    'canManageMarketingAccounts',
    'canManageDebtBook',
    'canAccessStoreManagement',
    'canManageStoreInventory',
    'canCreateStoreSales',
    'canCreateStorePurchases',
    'canManageStoreDebts',
    'canEditStorePrices',
    'canViewStoreProfits',
    'canViewStoreReports',
    'canViewExternalTransfers',
    'canReviewExternalTransfers',
    'canViewPublicStores',
    'canBuyPublicStoreProducts',
    'canPublishStorefront',
    'canManagePublicStorefront',
    'canManagePublicMarketplace',
    'canManageLocations',
    'canManageSystemSettings',
    'canManageSubUsers',
    'canViewSubUsers',
    'canReviewWithdrawals',
    'canReviewTopups',
    'canReviewDevices',
    'canViewAffiliateCenter',
    'canManageCardPrintRequests',
    'canReviewCardPrintRequests',
    'canPrepareCardPrintRequests',
    'canFinalizeCardPrintRequests',
    'canExportCustomerTransactions',
    'canOpenQuickTransfer',
    'canOpenCardTools',
    'externalCardStoreEnabled',
    'isAdmin',
    'isSupport',
    'isFinance',
  ];

  static Map<String, dynamic> _coerceMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  bool _isEnabled(String key, {bool defaultValue = false}) {
    final value = _raw[key];
    if (value == null) {
      return defaultValue;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized.isEmpty) {
      return false;
    }
    return defaultValue;
  }

  bool get canViewBalance => _isEnabled('canViewBalance');
  bool get canViewTransactions => _isEnabled('canViewTransactions');
  bool get canViewInventory => _isEnabled('canViewInventory');
  bool get canViewQuickTransfer => canTransfer;
  bool get canViewContact => _isEnabled('canViewContact', defaultValue: true);
  bool get canViewLocations =>
      _isEnabled('canViewLocations', defaultValue: true);
  bool get canViewUsagePolicy =>
      _isEnabled('canViewUsagePolicy', defaultValue: true);
  bool get canViewSecuritySettings =>
      _isEnabled('canViewSecuritySettings', defaultValue: true);
  bool get canViewAccountSettings =>
      _isEnabled('canViewAccountSettings', defaultValue: true);
  bool get canRequestVerification => _isEnabled('canRequestVerification');
  bool get canIssueCards => _isEnabled('canIssueCards');
  bool get canManageSubscriptions => canIssueCards || isAdminRole;
  bool get canIssueSubShekelCards => _isEnabled('canIssueSubShekelCards');
  bool get canIssueHighValueCards => _isEnabled('canIssueHighValueCards');
  bool get canIssuePrivateCards => _isEnabled('canIssuePrivateCards');
  bool get canIssueSingleUseTickets => _isEnabled('canIssueSingleUseTickets');
  bool get canIssueAppointmentTickets =>
      _isEnabled('canIssueAppointmentTickets');
  bool get canIssueQueueTickets => _isEnabled('canIssueQueueTickets');
  bool get canViewPrivateCards => _isEnabled('canViewPrivateCards');
  bool get canReadOwnPrivateCardsOnly =>
      _isEnabled('canReadOwnPrivateCardsOnly');
  bool get canPrintCards =>
      _isEnabled('canPrintCards') || canRequestCardPrinting;
  bool get canDeleteCards => _isEnabled('canDeleteCards');
  bool get canRequestCardPrinting => _isEnabled('canRequestCardPrinting');
  bool get canScanCards => _isEnabled('canScanCards');
  bool get canOfflineCardScan => _isEnabled('canOfflineCardScan');
  bool get canMonitorOfflineCards =>
      _isEnabled('canMonitorOfflineCards') ||
      canManageUsers ||
      canManageCardPrintRequests ||
      canReviewDevices;
  bool get canTransfer => _isEnabled('canTransfer');
  bool get canWithdraw => _isEnabled('canWithdraw');
  bool get canReviewCards => _isEnabled('canReviewCards');
  bool get canResellCards => _isEnabled('canResellCards');
  bool get canUsePrepaidMultipayCards =>
      _isEnabled('canUsePrepaidMultipayCards');
  bool get canReloadAnyPrepaidMultipayCard =>
      _isEnabled('canReloadAnyPrepaidMultipayCard');
  bool get canAcceptPrepaidMultipayPayments =>
      _isEnabled('canAcceptPrepaidMultipayPayments');
  bool get canUsePrepaidMultipayNfc => _isEnabled('canUsePrepaidMultipayNfc');
  bool get canUseExternalCardStore => _isEnabled('canUseExternalCardStore');
  bool get externalCardStoreEnabled => _isEnabled('externalCardStoreEnabled');
  bool get canOpenPrepaidMultipayCards =>
      canUsePrepaidMultipayCards || canAcceptPrepaidMultipayPayments;
  bool get canAcceptPrepaidMultipayContactless =>
      canAcceptPrepaidMultipayPayments && canUsePrepaidMultipayNfc;
  bool get canAccessRegulatedWalletFeatures =>
      canViewBalance ||
      canViewTransactions ||
      canTransfer ||
      canWithdraw ||
      canFinanceTopup ||
      canOpenPrepaidMultipayCards;
  bool get canOpenExternalCardStore =>
      externalCardStoreEnabled && canUseExternalCardStore;
  bool get canRedeemCards => _isEnabled('canRedeemCards');
  bool get canViewCustomers => _isEnabled('canViewCustomers');
  bool get canLookupMembers => _isEnabled('canLookupMembers');
  bool get canManageUsers => _isEnabled('canManageUsers');
  bool get canFinanceTopup => _isEnabled('canFinanceTopup');
  bool get canManageMarketingAccounts =>
      _isEnabled('canManageMarketingAccounts');
  bool get isPrimaryTrader => !isSubUser && !isAdminRole;
  bool get canManageDebtBook =>
      _isEnabled('canManageDebtBook') || isPrimaryTrader;
  bool get _hasStoreOwnerFallback => isAdminRole || canManageDebtBook;
  bool get canAccessStoreManagement =>
      _isEnabled('canAccessStoreManagement') ||
      isPrimaryTrader ||
      _hasStoreOwnerFallback ||
      canManageStoreInventory ||
      canCreateStoreSales ||
      canCreateStorePurchases ||
      canManageStoreDebts ||
      canViewStoreReports;
  bool get canManageStoreInventory =>
      _isEnabled('canManageStoreInventory') || _hasStoreOwnerFallback;
  bool get canCreateStoreSales =>
      _isEnabled('canCreateStoreSales') || _hasStoreOwnerFallback;
  bool get canCreateStorePurchases =>
      _isEnabled('canCreateStorePurchases') || _hasStoreOwnerFallback;
  bool get canManageStoreDebts =>
      _isEnabled('canManageStoreDebts') || _hasStoreOwnerFallback;
  bool get canEditStorePrices =>
      _isEnabled('canEditStorePrices') || _hasStoreOwnerFallback;
  bool get canViewStoreProfits =>
      _isEnabled('canViewStoreProfits') || _hasStoreOwnerFallback;
  bool get canViewStoreReports =>
      _isEnabled('canViewStoreReports') || _hasStoreOwnerFallback;
  bool get canViewExternalTransfers =>
      _isEnabled('canViewExternalTransfers') || isAdminRole || isPrimaryTrader;
  bool get canReviewExternalTransfers =>
      _isEnabled('canReviewExternalTransfers') || isAdminRole;
  bool get canViewPublicStores =>
      _isEnabled('canViewPublicStores', defaultValue: true);
  bool get canBuyPublicStoreProducts => _isEnabled('canBuyPublicStoreProducts');
  bool get canPublishStorefront => _isEnabled('canPublishStorefront');
  bool get canManagePublicStorefront =>
      _isEnabled('canManagePublicStorefront') || canManageStoreInventory;
  bool get canManagePublicMarketplace =>
      _isEnabled('canManagePublicMarketplace') || isAdminRole;
  bool get canManageLocations => _isEnabled('canManageLocations');
  bool get canManageSystemSettings => _isEnabled('canManageSystemSettings');
  bool get canManagePrepaidMultipayApprovals => canManageSystemSettings;
  bool get canManagePermissionTemplates => canManageSystemSettings;
  bool get canManageAdminNotifications => canManageSystemSettings;
  bool get canViewAdminCardScanReports => canManageUsers;
  bool get canManageSubUsers => _isEnabled('canManageSubUsers');
  bool get canViewSubUsers =>
      _isEnabled('canViewSubUsers') || canManageSubUsers;
  bool get canReviewWithdrawals => _isEnabled('canReviewWithdrawals');
  bool get canReviewTopups => _isEnabled('canReviewTopups');
  bool get canReviewDevices => _isEnabled('canReviewDevices');
  bool get canViewAffiliateCenter => _isEnabled('canViewAffiliateCenter');
  bool get canManageCardPrintRequests =>
      _isEnabled('canManageCardPrintRequests') ||
      _isEnabled('canReviewCardPrintRequests') ||
      _isEnabled('canPrepareCardPrintRequests') ||
      _isEnabled('canFinalizeCardPrintRequests');
  bool get canReviewCardPrintRequests => canManageCardPrintRequests;
  bool get canPrepareCardPrintRequests => canManageCardPrintRequests;
  bool get canFinalizeCardPrintRequests => canManageCardPrintRequests;
  bool get canExportCustomerTransactions =>
      _isEnabled('canExportCustomerTransactions');

  String get role => _raw['role']?.toString().trim().toLowerCase() ?? '';
  bool get isSubUser =>
      _isEnabled('isSubUser') ||
      (_raw['parentUserId']?.toString().trim().isNotEmpty ?? false);
  bool get isAdminRole =>
      _isEnabled('isAdmin') ||
      role == 'admin' ||
      role == 'super_admin' ||
      role == 'technical_admin';
  bool get isSupportRole => _raw['isSupport'] == true || role == 'support';
  bool get isFinanceRole => _raw['isFinance'] == true || role == 'finance';
  bool get isMarketerRole => role == 'marketer';
  bool get isDriverRole => role == 'driver';

  bool get hasAdminWorkspaceAccess =>
      isAdminRole ||
      isSupportRole ||
      canViewCustomers ||
      canLookupMembers ||
      canManageUsers ||
      canFinanceTopup ||
      canManageMarketingAccounts ||
      canManageDebtBook ||
      canReviewWithdrawals ||
      canReviewTopups ||
      canManageCardPrintRequests ||
      canReviewDevices ||
      canExportCustomerTransactions ||
      canManageLocations ||
      canManageSystemSettings;

  bool get shouldOpenAdminWorkspaceByDefault =>
      hasAdminWorkspaceAccess &&
      (isAdminRole || isSupportRole || isMarketerRole || isFinanceRole);

  bool get canOpenCardTools =>
      canScanCards ||
      canOfflineCardScan ||
      canReviewCards ||
      canResellCards ||
      canRedeemCards;

  bool get canOpenQuickTransfer => canTransfer;
}
