import 'dart:async';

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
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _user;
  int _unreadNotifications = 0;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadNotificationSummary();
    _notificationSubscription = RealtimeNotificationService.notificationsStream
        .listen((_) => _loadNotificationSummary());
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    setState(() => _user = user);
  }

  Future<void> _loadNotificationSummary() async {
    if (OfflineSessionService.isOfflineMode) {
      if (!mounted) {
        return;
      }
      setState(() => _unreadNotifications = 0);
      return;
    }
    try {
      final payload = await _apiService.getNotificationSummary();
      final summary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _unreadNotifications = (summary['unreadCount'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // The drawer should stay usable even if the notification endpoint is down.
    }
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: 'هذه الشاشة غير متاحة دون إنترنت',
      message:
          'أنت الآن في وضع الأوفلاين. هذه الشاشة تحتاج اتصالًا بالإنترنت حتى تعمل.',
    );
  }

  Future<void> _openRoute(String routeName) async {
    final normalizedRoute = OfflineSessionService.isOfflineMode &&
            routeName == '/scan-card'
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
    final canViewUsagePolicy = permissions.canViewUsagePolicy;
    final canViewSecuritySettings = permissions.canViewSecuritySettings;
    final canViewSubUsers = permissions.canViewSubUsers;
    final canViewAccountSettings = permissions.canViewAccountSettings;
    final canRequestVerification = permissions.canRequestVerification;
    final canIssueCards = permissions.canIssueCards;
    final canRequestCardPrinting = permissions.canRequestCardPrinting;
    final canScanCards = permissions.canOpenCardTools;
    final canViewCustomers = permissions.canViewCustomers;
    final canManageLocations = permissions.canManageLocations;
    final canManageSystemSettings = permissions.canManageSystemSettings;
    final canReviewWithdrawals = permissions.canReviewWithdrawals;
    final canReviewTopups = permissions.canReviewTopups;
    final canHandleCardPrintRequests = permissions.canManageCardPrintRequests;
    final canReviewDevices = permissions.canReviewDevices;
    final isOfflineMode = OfflineSessionService.isOfflineMode;
    final isRestrictedOfflineWorkspaceUser =
        permissions.canOfflineCardScan && !permissions.canIssueCards;

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
                  if (isOfflineMode || isRestrictedOfflineWorkspaceUser) ...[
                    _buildSectionLabel('مساحة الفحص'),
                    if (canScanCards)
                      _buildItem(
                        context,
                        icon: Icons.qr_code_scanner_rounded,
                        title: l.tr('widgets_app_sidebar.008'),
                        routeName: isOfflineMode
                            ? '/scan-card-offline'
                            : '/scan-card',
                      ),
                    if (permissions.canOfflineCardScan)
                      _buildItem(
                        context,
                        icon: Icons.cloud_done_rounded,
                        title: 'مركز الأوف لاين',
                        routeName: '/offline-center',
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
                    if (canViewInventory && canIssueCards)
                      _buildItem(
                        context,
                        icon: Icons.inventory_2_rounded,
                        title: l.tr('widgets_app_sidebar.006'),
                        routeName: '/inventory',
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
                  _buildSectionLabel(l.tr('widgets_app_sidebar.009')),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      canViewAccountSettings)
                    _buildItem(
                      context,
                      icon: Icons.person_rounded,
                      title: l.tr('widgets_app_sidebar.010'),
                      routeName: '/account-settings',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser && canViewQuickTransfer)
                    _buildItem(
                      context,
                      icon: Icons.send_to_mobile_rounded,
                      title: l.tr('widgets_app_sidebar.011'),
                      routeName: '/quick-transfer',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      verificationStatus != 'approved' &&
                      canRequestVerification)
                    _buildItem(
                      context,
                      icon: Icons.verified_user_rounded,
                      title: l.tr('widgets_app_sidebar.012'),
                      routeName: '/account-verification',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      canViewSecuritySettings)
                    _buildItem(
                      context,
                      icon: Icons.security_rounded,
                      title: l.tr('widgets_app_sidebar.013'),
                      routeName: '/security-settings',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser && canViewSubUsers)
                    _buildItem(
                      context,
                      icon: Icons.supervised_user_circle_rounded,
                      title: 'المستخدمون التابعون',
                      routeName: '/sub-users',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      (canViewCustomers ||
                          canReviewWithdrawals ||
                          canReviewTopups ||
                          canHandleCardPrintRequests ||
                          canReviewDevices ||
                          canManageLocations ||
                          canManageSystemSettings)) ...[
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
                        icon: Icons.settings_applications_rounded,
                        title: l.tr('widgets_app_sidebar.019'),
                        routeName: '/admin-system-settings',
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
                  if (!isRestrictedOfflineWorkspaceUser &&
                      !isOfflineMode &&
                      canViewUsagePolicy)
                    _buildItem(
                      context,
                      icon: Icons.policy_rounded,
                      title: l.tr('widgets_app_sidebar.021'),
                      routeName: '/usage-policy',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      !isOfflineMode &&
                      canViewContact)
                    _buildItem(
                      context,
                      icon: Icons.support_agent_rounded,
                      title: l.tr('widgets_app_sidebar.022'),
                      routeName: '/contact-us',
                    ),
                  if (!isRestrictedOfflineWorkspaceUser &&
                      !isOfflineMode &&
                      canViewLocations)
                    _buildItem(
                      context,
                      icon: Icons.storefront_rounded,
                      title: l.tr('widgets_app_sidebar.023'),
                      routeName: '/supported-locations',
                    ),
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
            const Divider(height: 1),
            ListTile(
              leading: _notificationIcon(),
              title: Text(
                l.text(
                  '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a',
                  'Notifications',
                ),
                style: AppTheme.bodyText.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _unreadNotifications > 0
                    ? l.text(
                        '\u0644\u062f\u064a\u0643 $_unreadNotifications \u0625\u0634\u0639\u0627\u0631\u0627\u062a \u063a\u064a\u0631 \u0645\u0642\u0631\u0648\u0621\u0629',
                        '$_unreadNotifications unread notifications',
                      )
                    : l.text(
                        '\u0643\u0644 \u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a \u0645\u0642\u0631\u0648\u0621\u0629',
                        'All notifications are read',
                      ),
                style: AppTheme.caption,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppTheme.textTertiary,
              ),
              onTap: () {
                if (OfflineSessionService.isOfflineMode) {
                  _showOfflineBlockedMessage();
                  return;
                }
                Navigator.pop(context);
                Navigator.pushNamed(context, '/notifications').then((_) {
                  if (mounted) {
                    _loadNotificationSummary();
                  }
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _notificationIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            color: AppTheme.primary,
          ),
        ),
        if (_unreadNotifications > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
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
        unawaited(_openRoute(routeName));
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
