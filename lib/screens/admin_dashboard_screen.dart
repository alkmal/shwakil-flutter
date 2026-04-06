import 'package:flutter/material.dart';

import '../services/index.dart';
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final fullNameValue = _user?['fullName']?.toString().trim() ?? '';
    final usernameValue = _user?['username']?.toString().trim() ?? '';
    final fullName = fullNameValue.isNotEmpty
        ? fullNameValue
        : (usernameValue.isNotEmpty ? usernameValue : 'الإدارة');
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    final adminCards = <Widget>[
      if (permissions['canReviewCardPrintRequests'] == true ||
          permissions['canPrepareCardPrintRequests'] == true ||
          permissions['canFinalizeCardPrintRequests'] == true)
        _navCard(
          title: 'طلبات طباعة البطاقات',
          subtitle: 'مراجعة الطلب ثم بدء الطباعة ثم التجهيز والإكمال.',
          icon: Icons.print_rounded,
          color: AppTheme.primary,
          routeName: '/admin-card-print-requests',
        ),
      if (permissions['canViewCustomers'] == true ||
          permissions['canManageUsers'] == true)
        _navCard(
          title: 'إدارة العملاء',
          subtitle: 'بحث العملاء وفتح ملفاتهم وإضافة مستخدم جديد.',
          icon: Icons.people_alt_rounded,
          color: AppTheme.primary,
          routeName: '/admin-customers',
        ),
      if (permissions['canReviewDevices'] == true)
        _navCard(
          title: 'طلبات الأجهزة',
          subtitle: 'مراجعة طلبات ربط الأجهزة الجديدة فقط.',
          icon: Icons.devices_other_rounded,
          color: AppTheme.warning,
          routeName: '/admin-device-requests',
        ),
      if (permissions['canReviewWithdrawals'] == true)
        _navCard(
          title: 'طلبات السحب',
          subtitle: 'اعتماد أو رفض طلبات السحب من شاشة مستقلة.',
          icon: Icons.outbox_rounded,
          color: AppTheme.secondary,
          routeName: '/withdrawal-requests',
        ),
      if (permissions['canReviewTopups'] == true)
        _navCard(
          title: 'طلبات شحن الرصيد',
          subtitle: 'مراجعة طلبات الشحن واعتمادها أو رفضها بسرعة.',
          icon: Icons.add_card_rounded,
          color: AppTheme.accent,
          routeName: '/topup-requests',
        ),
      if (permissions['canManageLocations'] == true)
        _navCard(
          title: 'الفروع والمواقع',
          subtitle: 'إدارة الفروع والمواقع المدعومة دون تحميل بيانات أخرى.',
          icon: Icons.map_rounded,
          color: AppTheme.success,
          routeName: '/admin-locations',
        ),
      if (permissions['canManageSystemSettings'] == true)
        _navCard(
          title: 'إعدادات النظام',
          subtitle: 'التسجيل والدعم والسياسات وطرق شحن الرصيد.',
          icon: Icons.settings_applications_rounded,
          color: AppTheme.textPrimary,
          routeName: '/admin-system-settings',
        ),
      if (permissions['canManageSystemSettings'] == true)
        _navCard(
          title: 'قوالب الصلاحيات',
          subtitle: 'التحكم بما يراه ويستطيع استخدامه كل مستوى من الأعضاء.',
          icon: Icons.rule_folder_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-permissions',
        ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Ù…Ø±ÙƒØ² Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©')),
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
                      'Ù…Ø±ÙƒØ² Ø§Ù„Ø¥Ø¯Ø§Ø±Ø© Ø§Ù„Ø³Ø±ÙŠØ¹',
                      style: AppTheme.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ø£Ù‡Ù„Ù‹Ø§ $fullName. ÙƒÙ„ Ù‚Ø³Ù… Ø¥Ø¯Ø§Ø±ÙŠ Ø£ØµØ¨Ø­ ÙÙŠ Ø´Ø§Ø´Ø© Ù…Ø³ØªÙ‚Ù„Ø©ØŒ Ù„Ø°Ù„Ùƒ ÙŠØªÙ… Ø¬Ù„Ø¨ Ø¨ÙŠØ§Ù†Ø§ØªÙ‡ ÙÙ‚Ø· Ø¹Ù†Ø¯ ÙØªØ­Ù‡ Ù„Ø³Ø±Ø¹Ø© Ø£Ø¹Ù„Ù‰ ÙˆØªØ¬Ø±Ø¨Ø© Ø£ÙˆØ¶Ø­.',
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
                  final crossAxisCount = constraints.maxWidth > 1100
                      ? 3
                      : constraints.maxWidth > 720
                      ? 2
                      : 1;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.55,
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
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, routeName),
        borderRadius: AppTheme.radiusLg,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 18),
              Text(title, style: AppTheme.h3.copyWith(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.arrow_forward_rounded, color: color),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'فتح القسم',
                    style: AppTheme.bodyBold.copyWith(color: color),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

