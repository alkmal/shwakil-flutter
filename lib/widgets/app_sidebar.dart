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
    final l = context.loc;
    final username =
        _user?['username']?.toString() ?? l.text('شواكل', 'Shawakel');
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
                  _buildSectionLabel(l.text('الرئيسية', 'Main')),
                  _buildItem(
                    context,
                    icon: Icons.home_rounded,
                    title: l.text('الرئيسية', 'Home'),
                    routeName: '/home',
                  ),
                  if (canViewBalance)
                    _buildItem(
                      context,
                      icon: Icons.account_balance_wallet_rounded,
                      title: l.text('الرصيد', 'Balance'),
                      routeName: '/balance',
                    ),
                  if (canViewTransactions)
                    _buildItem(
                      context,
                      icon: Icons.receipt_long_rounded,
                      title: l.text('الحركات', 'Transactions'),
                      routeName: '/transactions',
                    ),
                  if (canViewInventory && canIssueCards)
                    _buildItem(
                      context,
                      icon: Icons.inventory_2_rounded,
                      title: l.text('البطاقات', 'Cards'),
                      routeName: '/inventory',
                    ),
                  if (canRequestCardPrinting)
                    _buildItem(
                      context,
                      icon: Icons.print_rounded,
                      title: l.text('طلبات الطباعة', 'Print Requests'),
                      routeName: '/card-print-requests',
                    ),
                  if (canScanCards)
                    _buildItem(
                      context,
                      icon: Icons.qr_code_scanner_rounded,
                      title: l.text('فحص البطاقات', 'Scan Cards'),
                      routeName: '/scan-card',
                    ),
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel(l.text('الحساب', 'Account')),
                  if (canViewAccountSettings)
                    _buildItem(
                      context,
                      icon: Icons.person_rounded,
                      title: l.text('الحساب', 'Account'),
                      routeName: '/account-settings',
                    ),
                  if (canTransfer && canViewQuickTransfer)
                    _buildItem(
                      context,
                      icon: Icons.send_to_mobile_rounded,
                      title: l.text('النقل السريع', 'Quick Transfer'),
                      routeName: '/quick-transfer',
                    ),
                  if (verificationStatus != 'approved' && canRequestVerification)
                    _buildItem(
                      context,
                      icon: Icons.verified_user_rounded,
                      title: l.text('توثيق الحساب', 'Verify Account'),
                      routeName: '/account-verification',
                    ),
                  if (canViewSecuritySettings)
                    _buildItem(
                      context,
                      icon: Icons.security_rounded,
                      title: l.text('الأمان', 'Security'),
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
                    _buildSectionLabel(l.text('الإدارة', 'Admin')),
                    _buildItem(
                      context,
                      icon: Icons.dashboard_customize_rounded,
                      title: l.text('مركز الإدارة', 'Admin Center'),
                      routeName: '/admin-dashboard',
                    ),
                    if (canViewCustomers)
                      _buildItem(
                        context,
                        icon: Icons.people_alt_rounded,
                        title: l.text(
                          'إدارة العملاء',
                          'Customer Management',
                        ),
                        routeName: '/admin-customers',
                      ),
                    if (canReviewDevices)
                      _buildItem(
                        context,
                        icon: Icons.devices_other_rounded,
                        title: l.text('طلبات الأجهزة', 'Device Requests'),
                        routeName: '/admin-device-requests',
                      ),
                    if (canReviewWithdrawals)
                      _buildItem(
                        context,
                        icon: Icons.outbox_rounded,
                        title: l.text(
                          'طلبات السحب',
                          'Withdrawal Requests',
                        ),
                        routeName: '/withdrawal-requests',
                      ),
                    if (canReviewTopups)
                      _buildItem(
                        context,
                        icon: Icons.add_card_rounded,
                        title: l.text('طلبات شحن الرصيد', 'Top-up Requests'),
                        routeName: '/topup-requests',
                      ),
                    if (canHandleCardPrintRequests)
                      _buildItem(
                        context,
                        icon: Icons.print_rounded,
                        title: l.text(
                          'طلبات طباعة البطاقات',
                          'Card Print Requests',
                        ),
                        routeName: '/admin-card-print-requests',
                      ),
                    if (canManageLocations)
                      _buildItem(
                        context,
                        icon: Icons.map_rounded,
                        title: l.text('الفروع والمواقع', 'Branches & Locations'),
                        routeName: '/admin-locations',
                      ),
                    if (canManageSystemSettings)
                      _buildItem(
                        context,
                        icon: Icons.settings_applications_rounded,
                        title: l.text('إعدادات النظام', 'System Settings'),
                        routeName: '/admin-system-settings',
                      ),
                    if (canManageSystemSettings)
                      _buildItem(
                        context,
                        icon: Icons.rule_folder_rounded,
                        title: l.text(
                          'قوالب الصلاحيات',
                          'Permission Templates',
                        ),
                        routeName: '/admin-permissions',
                      ),
                  ],
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel(l.text('المزيد', 'More')),
                  if (canViewUsagePolicy)
                    _buildItem(
                      context,
                      icon: Icons.policy_rounded,
                      title: l.text('سياسة الاستخدام', 'Usage Policy'),
                      routeName: '/usage-policy',
                    ),
                  if (canViewContact)
                    _buildItem(
                      context,
                      icon: Icons.support_agent_rounded,
                      title: l.text('الدعم', 'Support'),
                      routeName: '/contact-us',
                    ),
                  if (canViewLocations)
                    _buildItem(
                      context,
                      icon: Icons.storefront_rounded,
                      title: l.text('الوكلاء', 'Agents'),
                      routeName: '/supported-locations',
                    ),
                  const Divider(indent: 8, endIndent: 8, height: 28),
                  _buildSectionLabel(l.text('اللغة', 'Language')),
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
                      l.text('العربية / English', 'English / العربية'),
                      style: AppTheme.bodyText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l.text(
                        'اضغط للتبديل بين اللغتين',
                        'Tap to switch between Arabic and English',
                      ),
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
              leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
              title: Text(
                l.text('تسجيل الخروج', 'Log Out'),
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
    final l = context.loc;
    var label = l.text('غير موثق', 'Unverified');
    var color = Colors.white24;
    if (status == 'approved') {
      label = l.text('موثق', 'Verified');
      color = AppTheme.success.withValues(alpha: 0.28);
    } else if (status == 'pending') {
      label = l.text('قيد المراجعة', 'Under Review');
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
          isArabic
              ? Icons.arrow_back_ios_new_rounded
              : Icons.arrow_forward_ios_rounded,
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
