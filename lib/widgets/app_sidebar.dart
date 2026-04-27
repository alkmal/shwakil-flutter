import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import 'shwakel_logo.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _user = AuthService.peekCurrentUser();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    final previousRaw = _user?.toString();
    final nextRaw = user?.toString();
    if (previousRaw == nextRaw) {
      return;
    }
    setState(() => _user = user);
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: context.loc.tr('widgets_app_sidebar.035'),
      message: context.loc.tr('widgets_app_sidebar.036'),
    );
  }

  Future<void> _openRoute(String routeName) async {
    final normalizedRoute =
        OfflineSessionService.isOfflineMode && routeName == '/scan-card'
        ? '/scan-card-offline'
        : routeName;
    if (!OfflineSessionService.canOpenRoute(normalizedRoute)) {
      await _showOfflineBlockedMessage();
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    Navigator.pushNamed(context, normalizedRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final username =
        _user?['username']?.toString() ?? l.tr('widgets_app_sidebar.001');
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final verificationStatus =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    final permissions = AppPermissions.fromUser(_user);

    final canViewBalance = permissions.canViewBalance;
    final canViewTransactions = permissions.canViewTransactions;
    final canViewInventory = permissions.canViewInventory;
    final canViewQuickTransfer = permissions.canOpenQuickTransfer;
    final canViewContact = permissions.canViewContact;
    final canViewLocations = permissions.canViewLocations;
    final canViewNotifications = permissions.canViewTransactions || canViewBalance;
    final canViewUsagePolicy = permissions.canViewUsagePolicy;
    final canViewSecuritySettings = permissions.canViewSecuritySettings;
    final canViewSubUsers = permissions.canViewSubUsers;
    final canManageDebtBook = permissions.canManageDebtBook;
    final canViewAccountSettings = permissions.canViewAccountSettings;
    final canRequestVerification = permissions.canRequestVerification;
    final canViewAffiliateCenter = permissions.canViewAffiliateCenter;
    final canIssueCards = permissions.canIssueCards;
    final canRequestCardPrinting = permissions.canRequestCardPrinting;
    final canScanCards = permissions.canOpenCardTools;
    final hasAdminWorkspaceAccess = permissions.hasAdminWorkspaceAccess;
    final canViewCustomers = permissions.canViewCustomers;
    final canManageUsers = permissions.canManageUsers;
    final canManageMarketingAccounts = permissions.canManageMarketingAccounts;
    final canManageLocations = permissions.canManageLocations;
    final canManageSystemSettings = permissions.canManageSystemSettings;
    final canReviewWithdrawals = permissions.canReviewWithdrawals;
    final canReviewTopups = permissions.canReviewTopups;
    final canHandleCardPrintRequests = permissions.canManageCardPrintRequests;
    final canReviewDevices = permissions.canReviewDevices;
    final isOfflineMode = OfflineSessionService.isOfflineMode;
    return Drawer(
      backgroundColor: AppTheme.sidebarSurface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.secondary, AppTheme.primary],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const ShwakelLogo(size: 48, framed: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName.isEmpty ? username : fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.h2.copyWith(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyText.copyWith(
                                color: AppTheme.textMutedOnDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _verificationBadge(verificationStatus),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                children: [
                  if (isOfflineMode) ...[
                    _buildSectionLabel(l.tr('widgets_app_sidebar.037')),
                    _buildItem(
                      context,
                      icon: Icons.home_rounded,
                      title: l.tr('widgets_app_sidebar.003'),
                      routeName: '/home',
                    ),
                    if (canScanCards)
                      _buildItem(
                        context,
                        icon: Icons.qr_code_scanner_rounded,
                        title: l.tr('widgets_app_sidebar.008'),
                        routeName: isOfflineMode
                            ? '/scan-card-offline'
                            : '/scan-card',
                      ),
                    if (canManageDebtBook)
                      _buildItem(
                        context,
                        icon: Icons.menu_book_rounded,
                        title: l.tr('widgets_app_sidebar.040'),
                        routeName: '/debt-book',
                      ),
                    if (canViewAffiliateCenter)
                      _buildItem(
                        context,
                        icon: Icons.campaign_rounded,
                        title: l.tr('widgets_app_sidebar.041'),
                        routeName: '/affiliate-center',
                      ),
                    const Divider(indent: 8, endIndent: 8, height: 28),
                  ] else ...[
                    _buildSectionLabel(l.tr('widgets_app_sidebar.002')),
                    _buildItem(
                      context,
                      icon: Icons.home_rounded,
                      title: l.tr('widgets_app_sidebar.003'),
                      routeName: '/home',
                    ),
                    if (canViewBalance)
                      _buildItem(
                        context,
                        icon: Icons.account_balance_wallet_rounded,
                        title: l.tr('widgets_app_sidebar.004'),
                        routeName: '/balance',
                      ),
                    if (canViewTransactions)
                      _buildItem(
                        context,
                        icon: Icons.receipt_long_rounded,
                        title: l.tr('widgets_app_sidebar.005'),
                        routeName: '/transactions',
                      ),
                    if (canViewNotifications)
                      _buildItem(
                        context,
                        icon: Icons.notifications_active_rounded,
                        title: l.tr('widgets_app_sidebar.044'),
                        routeName: '/notifications',
                      ),
                    if (canViewInventory && canIssueCards)
                      _buildItem(
                        context,
                        icon: Icons.inventory_2_rounded,
                        title: l.tr('widgets_app_sidebar.006'),
                        routeName: '/inventory',
                      ),
                    if (permissions.canOpenPrepaidMultipayCards)
                      _buildItem(
                        context,
                        icon: Icons.credit_card_rounded,
                        title: 'بطاقات دفع مسبق',
                        routeName: '/prepaid-multipay-cards',
                      ),
                    if (canRequestCardPrinting)
                      _buildItem(
                        context,
                        icon: Icons.print_rounded,
                        title: l.tr('widgets_app_sidebar.007'),
                        routeName: '/card-print-requests',
                      ),
                    if (canScanCards)
                      _buildItem(
                        context,
                        icon: Icons.qr_code_scanner_rounded,
                        title: l.tr('widgets_app_sidebar.008'),
                        routeName: isOfflineMode
                            ? '/scan-card-offline'
                            : '/scan-card',
                      ),
                    const Divider(indent: 8, endIndent: 8, height: 28),
                  ],
                  if (!isOfflineMode) ...[
                    _buildSectionLabel(l.tr('widgets_app_sidebar.009')),
                    if (canViewAccountSettings)
                      _buildItem(
                        context,
                        icon: Icons.person_rounded,
                        title: l.tr('widgets_app_sidebar.010'),
                        routeName: '/account-settings',
                      ),
                    if (canViewQuickTransfer)
                      _buildItem(
                        context,
                        icon: Icons.send_to_mobile_rounded,
                        title: l.tr('widgets_app_sidebar.011'),
                        routeName: '/quick-transfer',
                      ),
                    if (verificationStatus != 'approved' &&
                        canRequestVerification)
                      _buildItem(
                        context,
                        icon: Icons.verified_user_rounded,
                        title: l.tr('widgets_app_sidebar.012'),
                        routeName: '/account-verification',
                      ),
                    if (canViewSecuritySettings)
                      _buildItem(
                        context,
                        icon: Icons.security_rounded,
                        title: l.tr('widgets_app_sidebar.013'),
                        routeName: '/security-settings',
                      ),
                    if (canViewAffiliateCenter)
                      _buildItem(
                        context,
                        icon: Icons.campaign_rounded,
                        title: l.tr('widgets_app_sidebar.041'),
                        routeName: '/affiliate-center',
                      ),
                    if (canViewSubUsers)
                      _buildItem(
                        context,
                        icon: Icons.supervised_user_circle_rounded,
                        title: l.tr('widgets_app_sidebar.039'),
                        routeName: '/sub-users',
                      ),
                    if (canManageDebtBook)
                      _buildItem(
                        context,
                        icon: Icons.menu_book_rounded,
                        title: l.tr('widgets_app_sidebar.040'),
                        routeName: '/debt-book',
                      ),
                    if (hasAdminWorkspaceAccess) ...[
                      const Divider(indent: 8, endIndent: 8, height: 28),
                      _buildSectionLabel(l.tr('widgets_app_sidebar.014')),
                      _buildItem(
                        context,
                        icon: Icons.dashboard_customize_rounded,
                        title: l.tr('widgets_app_sidebar.015'),
                        routeName: '/admin-dashboard',
                      ),
                      if (canViewCustomers)
                        _buildItem(
                          context,
                          icon: Icons.people_alt_rounded,
                          title: l.tr('widgets_app_sidebar.030'),
                          routeName: '/admin-customers',
                        ),
                      if (canManageUsers || canManageMarketingAccounts)
                        _buildItem(
                          context,
                          icon: Icons.person_add_alt_1_rounded,
                          title: l.tr('widgets_app_sidebar.042'),
                          routeName: '/admin-pending-registrations',
                        ),
                      if (canReviewDevices)
                        _buildItem(
                          context,
                          icon: Icons.devices_other_rounded,
                          title: l.tr('widgets_app_sidebar.016'),
                          routeName: '/admin-device-requests',
                        ),
                      if (canReviewWithdrawals)
                        _buildItem(
                          context,
                          icon: Icons.outbox_rounded,
                          title: l.tr('widgets_app_sidebar.031'),
                          routeName: '/withdrawal-requests',
                        ),
                      if (canReviewTopups)
                        _buildItem(
                          context,
                          icon: Icons.add_card_rounded,
                          title: l.tr('widgets_app_sidebar.017'),
                          routeName: '/topup-requests',
                        ),
                      if (canHandleCardPrintRequests)
                        _buildItem(
                          context,
                          icon: Icons.print_rounded,
                          title: l.tr('widgets_app_sidebar.032'),
                          routeName: '/admin-card-print-requests',
                        ),
                      if (canManageLocations)
                        _buildItem(
                          context,
                          icon: Icons.map_rounded,
                          title: l.tr('widgets_app_sidebar.018'),
                          routeName: '/admin-locations',
                        ),
                      if (canManageSystemSettings)
                        _buildItem(
                          context,
                          icon: Icons.approval_rounded,
                          title: l.tr('widgets_app_sidebar.045'),
                          routeName: '/admin-prepaid-multipay-approvals',
                        ),
                      if (canManageSystemSettings)
                        _buildItem(
                          context,
                          icon: Icons.settings_applications_rounded,
                          title: l.tr('widgets_app_sidebar.019'),
                          routeName: '/admin-system-settings',
                        ),
                      if (canManageSystemSettings)
                        _buildItem(
                          context,
                          icon: Icons.campaign_rounded,
                          title: l.tr('widgets_app_sidebar.043'),
                          routeName: '/admin-notifications',
                        ),
                      if (canManageSystemSettings)
                        _buildItem(
                          context,
                          icon: Icons.rule_folder_rounded,
                          title: l.tr('widgets_app_sidebar.033'),
                          routeName: '/admin-permissions',
                        ),
                    ],
                    const Divider(indent: 8, endIndent: 8, height: 28),
                    _buildSectionLabel(l.tr('widgets_app_sidebar.020')),
                    if (canViewUsagePolicy)
                      _buildItem(
                        context,
                        icon: Icons.policy_rounded,
                        title: l.tr('widgets_app_sidebar.021'),
                        routeName: '/usage-policy',
                      ),
                    if (canViewContact)
                      _buildItem(
                        context,
                        icon: Icons.support_agent_rounded,
                        title: l.tr('widgets_app_sidebar.022'),
                        routeName: '/contact-us',
                      ),
                    if (canViewLocations)
                      _buildItem(
                        context,
                        icon: Icons.storefront_rounded,
                        title: l.tr('widgets_app_sidebar.023'),
                        routeName: '/supported-locations',
                      ),
                  ],
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel(l.tr('widgets_app_sidebar.024')),
                  ListTile(
                    minTileHeight: 50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: const Icon(
                      Icons.language_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    title: Text(
                      l.tr('widgets_app_sidebar.025'),
                      style: AppTheme.bodyText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l.tr('widgets_app_sidebar.034'),
                      style: AppTheme.caption,
                    ),
                    onTap: () async {
                      await AppLocaleService.instance.toggleLocale();
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _verificationBadge(String status) {
    final l = context.loc;
    var label = l.tr('widgets_app_sidebar.027');
    var color = Colors.white24;
    if (status == 'approved') {
      label = l.tr('widgets_app_sidebar.028');
      color = AppTheme.success.withValues(alpha: 0.28);
    } else if (status == 'pending') {
      label = l.tr('widgets_app_sidebar.029');
      color = AppTheme.warning.withValues(alpha: 0.28);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String routeName,
  }) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final isSelected = currentRoute == routeName;
    final isArabic = context.loc.isArabic;
    final isBlockedOffline = !OfflineSessionService.canOpenRoute(routeName);

    return ListTile(
      minTileHeight: 50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        icon,
        color: isBlockedOffline
            ? AppTheme.textTertiary
            : (isSelected ? AppTheme.primary : AppTheme.textSecondary),
      ),
      title: Text(
        title,
        style: AppTheme.bodyText.copyWith(
          color: isBlockedOffline
              ? AppTheme.textTertiary
              : (isSelected ? AppTheme.primary : AppTheme.textPrimary),
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isBlockedOffline
              ? AppTheme.surfaceMuted.withValues(alpha: 0.7)
              : (isSelected
                    ? AppTheme.primary.withValues(alpha: 0.14)
                    : AppTheme.surfaceMuted),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isArabic
              ? Icons.arrow_forward_ios_rounded
              : Icons.arrow_back_ios_new_rounded,
          size: 14,
          color: isBlockedOffline
              ? AppTheme.textTertiary
              : (isSelected ? AppTheme.primary : AppTheme.textTertiary),
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.tabSurface,
      onTap: () {
        if (isSelected) {
          Navigator.pop(context);
          return;
        }
        _openRoute(routeName);
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: AppTheme.textTertiary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
