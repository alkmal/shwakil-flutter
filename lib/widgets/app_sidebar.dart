import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import 'shwakel_logo.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _user;

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
    setState(() => _user = user);
  }

  Future<void> _logout() async {
    await RealtimeNotificationService.stop();
    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final canUseTrustedUnlock =
        await LocalSecurityService.canUseTrustedUnlock();
    if (!canUseTrustedUnlock) {
      await _authService.logout();
      await LocalSecurityService.clearTrustedState();
    }

    navigator.pushNamedAndRemoveUntil(
      canUseTrustedUnlock ? '/unlock' : '/login',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = _user?['username']?.toString() ?? 'شواكل';
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final verificationStatus =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );

    final canViewBalance = permissions['canViewBalance'] != false;
    final canViewTransactions = permissions['canViewTransactions'] != false;
    final canViewInventory = permissions['canViewInventory'] == true;
    final canViewQuickTransfer = permissions['canViewQuickTransfer'] == true;
    final canViewContact = permissions['canViewContact'] != false;
    final canViewLocations = permissions['canViewLocations'] != false;
    final canViewUsagePolicy = permissions['canViewUsagePolicy'] != false;
    final canViewSecuritySettings =
        permissions['canViewSecuritySettings'] != false;
    final canViewAccountSettings =
        permissions['canViewAccountSettings'] != false;
    final canRequestVerification =
        permissions['canRequestVerification'] == true;
    final canIssueCards = permissions['canIssueCards'] == true;
    final canRequestCardPrinting =
        permissions['canRequestCardPrinting'] == true;
    final canScanCards = permissions['canScanCards'] == true;
    final canTransfer = permissions['canTransfer'] == true;
    final canViewCustomers = permissions['canViewCustomers'] == true;
    final canManageLocations = permissions['canManageLocations'] == true;
    final canManageSystemSettings =
        permissions['canManageSystemSettings'] == true;
    final canReviewWithdrawals =
        permissions['canReviewWithdrawals'] == true || canViewCustomers;
    final canReviewTopups = permissions['canReviewTopups'] == true;
    final canHandleCardPrintRequests =
        permissions['canReviewCardPrintRequests'] == true ||
        permissions['canPrepareCardPrintRequests'] == true ||
        permissions['canFinalizeCardPrintRequests'] == true;
    final canReviewDevices = permissions['canReviewDevices'] == true;

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
                  _buildSectionLabel('الرئيسية'),
                  _buildItem(
                    context,
                    icon: Icons.home_rounded,
                    title: 'الرئيسية',
                    routeName: '/home',
                  ),
                  if (canViewBalance)
                    _buildItem(
                      context,
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'الرصيد',
                      routeName: '/balance',
                    ),
                  if (canViewTransactions)
                    _buildItem(
                      context,
                      icon: Icons.receipt_long_rounded,
                      title: 'الحركات',
                      routeName: '/transactions',
                    ),
                  if (canViewInventory && canIssueCards)
                    _buildItem(
                      context,
                      icon: Icons.inventory_2_rounded,
                      title: 'البطاقات',
                      routeName: '/inventory',
                    ),
                  if (canRequestCardPrinting)
                    _buildItem(
                      context,
                      icon: Icons.print_rounded,
                      title: 'طلبات الطباعة',
                      routeName: '/card-print-requests',
                    ),
                  if (canScanCards)
                    _buildItem(
                      context,
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'فحص البطاقات',
                      routeName: '/scan-card',
                    ),
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel('الحساب'),
                  if (canViewAccountSettings)
                    _buildItem(
                      context,
                      icon: Icons.person_rounded,
                      title: 'الحساب',
                      routeName: '/account-settings',
                    ),
                  if (canTransfer && canViewQuickTransfer)
                    _buildItem(
                      context,
                      icon: Icons.send_to_mobile_rounded,
                      title: 'النقل السريع',
                      routeName: '/quick-transfer',
                    ),
                  if (verificationStatus != 'approved' && canRequestVerification)
                    _buildItem(
                      context,
                      icon: Icons.verified_user_rounded,
                      title: 'توثيق الحساب',
                      routeName: '/account-verification',
                    ),
                  if (canViewSecuritySettings)
                    _buildItem(
                      context,
                      icon: Icons.security_rounded,
                      title: 'الأمان',
                      routeName: '/security-settings',
                    ),
                  if (canViewCustomers ||
                      canReviewWithdrawals ||
                      canReviewTopups ||
                      canHandleCardPrintRequests ||
                      canReviewDevices ||
                      canManageLocations ||
                      canManageSystemSettings) ...[
                    const Divider(indent: 8, endIndent: 8, height: 28),
                    _buildSectionLabel('الإدارة'),
                    _buildItem(
                      context,
                      icon: Icons.dashboard_customize_rounded,
                      title: 'مركز الإدارة',
                      routeName: '/admin-dashboard',
                    ),
                    if (canViewCustomers)
                      _buildItem(
                        context,
                        icon: Icons.people_alt_rounded,
                        title: 'إدارة العملاء',
                        routeName: '/admin-customers',
                      ),
                    if (canReviewDevices)
                      _buildItem(
                        context,
                        icon: Icons.devices_other_rounded,
                        title: 'طلبات الأجهزة',
                        routeName: '/admin-device-requests',
                      ),
                    if (canReviewWithdrawals)
                      _buildItem(
                        context,
                        icon: Icons.outbox_rounded,
                        title: 'طلبات السحب',
                        routeName: '/withdrawal-requests',
                      ),
                    if (canReviewTopups)
                      _buildItem(
                        context,
                        icon: Icons.add_card_rounded,
                        title: 'طلبات شحن الرصيد',
                        routeName: '/topup-requests',
                      ),
                    if (canHandleCardPrintRequests)
                      _buildItem(
                        context,
                        icon: Icons.print_rounded,
                        title: 'طلبات طباعة البطاقات',
                        routeName: '/admin-card-print-requests',
                      ),
                    if (canManageLocations)
                      _buildItem(
                        context,
                        icon: Icons.map_rounded,
                        title: 'الفروع والمواقع',
                        routeName: '/admin-locations',
                      ),
                    if (canManageSystemSettings)
                      _buildItem(
                        context,
                        icon: Icons.settings_applications_rounded,
                        title: 'إعدادات النظام',
                        routeName: '/admin-system-settings',
                      ),
                    if (canManageSystemSettings)
                      _buildItem(
                        context,
                        icon: Icons.rule_folder_rounded,
                        title: 'قوالب الصلاحيات',
                        routeName: '/admin-permissions',
                      ),
                  ],
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel('المزيد'),
                  if (canViewUsagePolicy)
                    _buildItem(
                      context,
                      icon: Icons.policy_rounded,
                      title: 'سياسة الاستخدام',
                      routeName: '/usage-policy',
                    ),
                  if (canViewContact)
                    _buildItem(
                      context,
                      icon: Icons.support_agent_rounded,
                      title: 'الدعم',
                      routeName: '/contact-us',
                    ),
                  if (canViewLocations)
                    _buildItem(
                      context,
                      icon: Icons.storefront_rounded,
                      title: 'الوكلاء',
                      routeName: '/supported-locations',
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
              title: Text(
                'تسجيل الخروج',
                style: AppTheme.bodyText.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: _logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _verificationBadge(String status) {
    var label = 'غير موثق';
    var color = Colors.white24;
    if (status == 'approved') {
      label = 'موثق';
      color = AppTheme.success.withValues(alpha: 0.28);
    } else if (status == 'pending') {
      label = 'قيد المراجعة';
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

    return ListTile(
      minTileHeight: 50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        icon,
        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
      ),
      title: Text(
        title,
        style: AppTheme.bodyText.copyWith(
          color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.14)
              : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 14,
          color: isSelected ? AppTheme.primary : AppTheme.textTertiary,
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.tabSurface,
      onTap: () {
        Navigator.pop(context);
        if (!isSelected) {
          Navigator.pushNamed(context, routeName);
        }
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
