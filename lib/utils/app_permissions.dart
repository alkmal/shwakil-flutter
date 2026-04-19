class AppPermissions {
  const AppPermissions._(this._raw);

  factory AppPermissions.fromUser(Map<String, dynamic>? user) {
    return AppPermissions._(_coerceMap(user?['permissions']));
  }

  final Map<String, dynamic> _raw;

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
    return value == true;
  }

  bool get canViewBalance => _raw['canViewBalance'] != false;
  bool get canViewTransactions => _raw['canViewTransactions'] != false;
  bool get canViewInventory => _isEnabled('canViewInventory');
  bool get canViewQuickTransfer => _isEnabled('canViewQuickTransfer');
  bool get canViewContact => _raw['canViewContact'] != false;
  bool get canViewLocations => _raw['canViewLocations'] != false;
  bool get canViewUsagePolicy => _raw['canViewUsagePolicy'] != false;
  bool get canViewSecuritySettings => _raw['canViewSecuritySettings'] != false;
  bool get canViewAccountSettings => _raw['canViewAccountSettings'] != false;
  bool get canRequestVerification => _isEnabled('canRequestVerification');
  bool get canIssueCards => _isEnabled('canIssueCards');
  bool get canRequestCardPrinting => _isEnabled('canRequestCardPrinting');
  bool get canScanCards => _isEnabled('canScanCards');
  bool get canOfflineCardScan => _isEnabled('canOfflineCardScan');
  bool get canTransfer => _isEnabled('canTransfer');
  bool get canWithdraw => _isEnabled('canWithdraw');
  bool get canReviewCards => _isEnabled('canReviewCards');
  bool get canResellCards => _isEnabled('canResellCards');
  bool get canRedeemCards => _isEnabled('canRedeemCards');
  bool get canViewCustomers => _isEnabled('canViewCustomers');
  bool get canManageLocations => _isEnabled('canManageLocations');
  bool get canManageSystemSettings => _isEnabled('canManageSystemSettings');
  bool get canManageSubUsers => _isEnabled('canManageSubUsers');
  bool get canViewSubUsers =>
      _isEnabled('canViewSubUsers') || canManageSubUsers;
  bool get canReviewWithdrawals => _isEnabled('canReviewWithdrawals');
  bool get canReviewTopups => _isEnabled('canReviewTopups');
  bool get canReviewDevices => _isEnabled('canReviewDevices');
  bool get canManageCardPrintRequests =>
      _isEnabled('canManageCardPrintRequests') ||
      _isEnabled('canReviewCardPrintRequests') ||
      _isEnabled('canPrepareCardPrintRequests') ||
      _isEnabled('canFinalizeCardPrintRequests');
  bool get canReviewCardPrintRequests => canManageCardPrintRequests;
  bool get canPrepareCardPrintRequests => canManageCardPrintRequests;
  bool get canFinalizeCardPrintRequests => canManageCardPrintRequests;

  bool get canOpenCardTools =>
      canScanCards ||
      canOfflineCardScan ||
      canReviewCards ||
      canResellCards ||
      canRedeemCards;

  bool get canOpenQuickTransfer => canViewQuickTransfer || canTransfer;
}
