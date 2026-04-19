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
    setState(() {
      _user = user;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final fullNameValue = _user?['fullName']?.toString().trim() ?? '';
    final usernameValue = _user?['username']?.toString().trim() ?? '';
    final fullName = fullNameValue.isNotEmpty
        ? fullNameValue
        : (usernameValue.isNotEmpty
              ? usernameValue
              : l.tr('screens_admin_dashboard_screen.003'));
    final permissions = AppPermissions.fromUser(_user);
    final adminCards = <Widget>[
      if (permissions.canManageCardPrintRequests ||
          permissions.canReviewCardPrintRequests ||
          permissions.canPrepareCardPrintRequests ||
          permissions.canFinalizeCardPrintRequests)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.004'),
          subtitle: l.tr('screens_admin_dashboard_screen.005'),
          icon: Icons.print_rounded,
          color: AppTheme.primary,
          routeName: '/admin-card-print-requests',
        ),
      if (permissions.canViewCustomers)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.006'),
          subtitle: l.tr('screens_admin_dashboard_screen.007'),
          icon: Icons.people_alt_rounded,
          color: AppTheme.primary,
          routeName: '/admin-customers',
        ),
      if (permissions.canReviewDevices)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.008'),
          subtitle: l.tr('screens_admin_dashboard_screen.009'),
          icon: Icons.devices_other_rounded,
          color: AppTheme.warning,
          routeName: '/admin-device-requests',
        ),
      if (permissions.canReviewWithdrawals)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.010'),
          subtitle: l.tr('screens_admin_dashboard_screen.011'),
          icon: Icons.outbox_rounded,
          color: AppTheme.secondary,
          routeName: '/withdrawal-requests',
        ),
      if (permissions.canReviewTopups)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.012'),
          subtitle: l.tr('screens_admin_dashboard_screen.013'),
          icon: Icons.add_card_rounded,
          color: AppTheme.accent,
          routeName: '/topup-requests',
        ),
      if (permissions.canManageLocations)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.014'),
          subtitle: l.tr('screens_admin_dashboard_screen.015'),
          icon: Icons.map_rounded,
          color: AppTheme.success,
          routeName: '/admin-locations',
        ),
      if (permissions.canManageSystemSettings)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.016'),
          subtitle: l.tr('screens_admin_dashboard_screen.017'),
          icon: Icons.settings_applications_rounded,
          color: AppTheme.textPrimary,
          routeName: '/admin-system-settings',
        ),
      if (permissions.canManageSystemSettings)
        _navCard(
          title: l.tr('screens_admin_dashboard_screen.018'),
          subtitle: l.tr('screens_admin_dashboard_screen.019'),
          icon: Icons.rule_folder_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-permissions',
        ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.tr('screens_admin_dashboard_screen.001'))),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShwakelCard(
                padding: const EdgeInsets.all(28),
                gradient: AppTheme.primaryGradient,
                shadowLevel: ShwakelShadowLevel.premium,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_admin_dashboard_screen.002'),
                      style: AppTheme.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.tr(
                        'screens_admin_dashboard_screen.description',
                        params: {'name': fullName},
                      ),
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white70,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1120
                      ? 3
                      : constraints.maxWidth > 740
                      ? 2
                      : 1;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2.05,
                    children: adminCards,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String routeName,
  }) {
    return ShwakelCard(
      onTap: () => Navigator.pushNamed(context, routeName),
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppTheme.h3.copyWith(color: color)),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTheme.bodyAction.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.arrow_forward_rounded, color: color, size: 28),
        ],
      ),
    );
  }
}
