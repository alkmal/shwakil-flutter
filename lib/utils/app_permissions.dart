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
    return value == true || value == 1 || value == '1';
  }

  bool get canViewBalance => _isEnabled('canViewBalance');
  bool get canViewTransactions => _isEnabled('canViewTransactions');
  bool get canViewInventory => _isEnabled('canViewInventory');
  bool get canViewQuickTransfer => canTransfer;
  bool get canViewContact => _raw['canViewContact'] != false;
  bool get canViewLocations => _raw['canViewLocations'] != false;
  bool get canViewUsagePolicy => _raw['canViewUsagePolicy'] != false;
  bool get canViewSecuritySettings => _raw['canViewSecuritySettings'] != false;
  bool get canViewAccountSettings => _raw['canViewAccountSettings'] != false;
  bool get canRequestVerification => _isEnabled('canRequestVerification');
  bool get canIssueCards => _isEnabled('canIssueCards');
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
  bool get canManageDebtBook => _isEnabled('canManageDebtBook');
  bool get _hasStoreOwnerFallback => isAdminRole || canManageDebtBook;
  bool get canAccessStoreManagement =>
      _isEnabled('canAccessStoreManagement') ||
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
  bool get canManageLocations => _isEnabled('canManageLocations');
  bool get canManageSystemSettings => _isEnabled('canManageSystemSettings');
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
  bool get isAdminRole =>
      _raw['isAdmin'] == true ||
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
