import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isAuthorized = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.currentUser();
    final permissions = AppPermissions.fromUser(user);
    final isAuthorized =
        permissions.canViewCustomers ||
        permissions.canReviewWithdrawals ||
        permissions.canReviewTopups ||
        permissions.canManageCardPrintRequests ||
        permissions.canReviewDevices ||
        permissions.canManageLocations ||
        permissions.canManageSystemSettings;
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _isAuthorized = isAuthorized;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: Text(l.tr('screens_admin_dashboard_screen.001'))),
        drawer: const AppSidebar(),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  'لا تملك صلاحية الوصول إلى لوحة الإدارة',
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fullNameValue = _user?['fullName']?.toString().trim() ?? '';
    final usernameValue = _user?['username']?.toString().trim() ?? '';
    final fullName = fullNameValue.isNotEmpty
        ? fullNameValue
        : (usernameValue.isNotEmpty
              ? usernameValue
              : l.tr('screens_admin_dashboard_screen.003'));
    final permissions = AppPermissions.fromUser(_user);
    final adminCards = <_AdminEntry>[
      if (permissions.canManageCardPrintRequests ||
          permissions.canReviewCardPrintRequests ||
          permissions.canPrepareCardPrintRequests ||
          permissions.canFinalizeCardPrintRequests)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.004'),
          subtitle: l.tr('screens_admin_dashboard_screen.005'),
          icon: Icons.print_rounded,
          color: AppTheme.primary,
          routeName: '/admin-card-print-requests',
          badge: 'طلبات',
        ),
      if (permissions.canViewCustomers)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.006'),
          subtitle: l.tr('screens_admin_dashboard_screen.007'),
          icon: Icons.people_alt_rounded,
          color: AppTheme.primary,
          routeName: '/admin-customers',
          badge: 'عملاء',
        ),
      if (permissions.canReviewDevices)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.008'),
          subtitle: l.tr('screens_admin_dashboard_screen.009'),
          icon: Icons.devices_other_rounded,
          color: AppTheme.warning,
          routeName: '/admin-device-requests',
          badge: 'أجهزة',
        ),
      if (permissions.canReviewWithdrawals)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.010'),
          subtitle: l.tr('screens_admin_dashboard_screen.011'),
          icon: Icons.outbox_rounded,
          color: AppTheme.secondary,
          routeName: '/withdrawal-requests',
          badge: 'سحب',
        ),
      if (permissions.canReviewTopups)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.012'),
          subtitle: l.tr('screens_admin_dashboard_screen.013'),
          icon: Icons.add_card_rounded,
          color: AppTheme.accent,
          routeName: '/topup-requests',
          badge: 'شحن',
        ),
      if (permissions.canManageLocations)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.014'),
          subtitle: l.tr('screens_admin_dashboard_screen.015'),
          icon: Icons.map_rounded,
          color: AppTheme.success,
          routeName: '/admin-locations',
          badge: 'مناطق',
        ),
      if (permissions.canManageSystemSettings)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.016'),
          subtitle: l.tr('screens_admin_dashboard_screen.017'),
          icon: Icons.settings_applications_rounded,
          color: AppTheme.textPrimary,
          routeName: '/admin-system-settings',
          badge: 'إعدادات',
        ),
      if (permissions.canManageSystemSettings)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.018'),
          subtitle: l.tr('screens_admin_dashboard_screen.019'),
          icon: Icons.rule_folder_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-permissions',
          badge: 'صلاحيات',
        ),
    ];
    final quickStats = [
      _AdminStat(
        label: 'الوحدات المتاحة',
        value: '${adminCards.length}',
        hint: 'أقسام الإدارة الجاهزة',
        icon: Icons.dashboard_customize_rounded,
        color: AppTheme.primary,
      ),
      _AdminStat(
        label: 'المستخدم الحالي',
        value: usernameValue.isNotEmpty ? usernameValue : 'مدير',
        hint: 'هوية جلسة الإدارة',
        icon: Icons.verified_user_rounded,
        color: AppTheme.success,
      ),
      _AdminStat(
        label: 'وضع التشغيل',
        value: permissions.canManageSystemSettings ? 'كامل' : 'مخصص',
        hint: 'مستوى الوصول الحالي',
        icon: Icons.tune_rounded,
        color: AppTheme.secondary,
      ),
    ];
    final adminWidgets = adminCards.map((item) => _navCard(item)).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_admin_dashboard_screen.001')),
        actions: [
          IconButton(
            tooltip: l.text('مساعدة', 'Help'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(fullName: fullName, stats: quickStats),
              const SizedBox(height: 24),
              _buildSectionHeader(
                title: 'ملخص العمل',
                subtitle: 'نظرة سريعة على مستوى الوصول والصفحات المتاحة لك.',
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  if (compact) {
                    return Column(
                      children: quickStats
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildStatCard(item),
                            ),
                          )
                          .toList(),
                    );
                  }

                  return Row(
                    children: quickStats
                        .map(
                          (item) => Expanded(
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: item == quickStats.first ? 0 : 12,
                              ),
                              child: _buildStatCard(item),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
              _buildSectionHeader(
                title: 'الوحدات الإدارية',
                subtitle:
                    'ادخل مباشرة إلى العمليات الأساسية من بطاقات مرتبة وواضحة.',
                actionLabel: '${adminCards.length} أقسام',
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1120
                      ? 3
                      : constraints.maxWidth > 740
                      ? 2
                      : 1;
                  final childAspectRatio = constraints.maxWidth > 1120
                      ? 1.45
                      : constraints.maxWidth > 740
                      ? 1.18
                      : 1.32;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 18,
                    childAspectRatio: childAspectRatio,
                    children: adminWidgets,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero({
    required String fullName,
    required List<_AdminStat> stats,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.heroGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      borderColor: Colors.white.withValues(alpha: 0.18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final identityBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.loc.tr('screens_admin_dashboard_screen.002'),
                style: AppTheme.h1.copyWith(color: Colors.white, height: 1.2),
              ),
              const SizedBox(height: 10),
              Text(
                context.loc.tr(
                  'screens_admin_dashboard_screen.description',
                  params: {'name': fullName},
                ),
                style: AppTheme.bodyAction.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _heroChip(
                    icon: Icons.manage_accounts_rounded,
                    label: fullName,
                  ),
                  _heroChip(
                    icon: Icons.grid_view_rounded,
                    label: '${stats.first.value} وحدات جاهزة',
                  ),
                ],
              ),
            ],
          );

          final spotlight = Container(
            width: compact ? double.infinity : 290,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جاهزية الإدارة',
                  style: AppTheme.h3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'لوحة مرتبة لفتح الأقسام الأساسية بسرعة ومتابعة العمل من نقطة واحدة.',
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 18),
                ...stats
                    .take(2)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _heroMetric(item),
                      ),
                    ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identityBlock, const SizedBox(height: 18), spotlight],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identityBlock),
              const SizedBox(width: 22),
              spotlight,
            ],
          );
        },
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.text('مساعدة سريعة', 'Quick help'),
      message: l.text(
        'هذه الصفحة للوصول السريع إلى الوحدات الإدارية. استخدم البطاقات مباشرة لفتح القسم المطلوب.',
        'This page is for quick access to admin modules. Use the cards directly to open the section you need.',
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? actionLabel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.dashboard_customize_rounded,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.h2.copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              actionLabel,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(_AdminStat item) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(26),
      shadowLevel: ShwakelShadowLevel.medium,
      borderColor: item.color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: item.color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h3.copyWith(color: item.color),
                ),
                const SizedBox(height: 4),
                Text(item.hint, style: AppTheme.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(_AdminStat item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: AppTheme.caption.copyWith(color: Colors.white70),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.value,
            style: AppTheme.bodyBold.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _navCard(_AdminEntry item) {
    return ShwakelCard(
      onTap: () => Navigator.pushNamed(context, item.routeName),
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      borderColor: item.color.withValues(alpha: 0.10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      item.color.withValues(alpha: 0.16),
                      item.color.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(item.icon, color: item.color, size: 30),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.badge,
                  style: AppTheme.caption.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.h3.copyWith(color: item.color, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'فتح القسم',
                style: AppTheme.bodyBold.copyWith(color: item.color),
              ),
              const Spacer(),
              Icon(Icons.arrow_back_rounded, color: item.color, size: 24),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminEntry {
  const _AdminEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.routeName,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String routeName;
  final String badge;
}

class _AdminStat {
  const _AdminStat({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
}
