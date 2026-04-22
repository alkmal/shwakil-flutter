import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AffiliateCenterScreen extends StatefulWidget {
  const AffiliateCenterScreen({super.key});

  @override
  State<AffiliateCenterScreen> createState() => _AffiliateCenterScreenState();
}

class _AffiliateCenterScreenState extends State<AffiliateCenterScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  Map<String, dynamic> _affiliate = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await _apiService.getAffiliateDashboard();
      if (!mounted) {
        return;
      }
      setState(() {
        _affiliate = Map<String, dynamic>.from(
          payload['affiliate'] as Map? ?? const {},
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل التسويق بالعمولة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _copyValue(String label, String value) async {
    if (value.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    await AppAlertService.showSuccess(
      context,
      title: 'تم النسخ',
      message: 'تم نسخ $label بنجاح.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final enabled = _affiliate['enabled'] == true;
    final summary = Map<String, dynamic>.from(
      _affiliate['summary'] as Map? ?? const {},
    );
    final recentReferrals = List<Map<String, dynamic>>.from(
      (_affiliate['recentReferrals'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final recentCommissions = List<Map<String, dynamic>>.from(
      (_affiliate['recentCommissions'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('التسويق بالعمولة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHero(enabled),
                  const SizedBox(height: 20),
                  _buildShareCard(),
                  const SizedBox(height: 20),
                  _buildSummaryGrid(summary),
                  const SizedBox(height: 20),
                  _buildSectionTitle(
                    'آخر الإحالات',
                    'تابع حالة العملاء الذين سجلوا من خلالك.',
                  ),
                  const SizedBox(height: 12),
                  if (recentReferrals.isEmpty)
                    _buildEmptyCard('لا توجد إحالات مسجلة حتى الآن.')
                  else
                    ...recentReferrals.map(_buildReferralCard),
                  const SizedBox(height: 20),
                  _buildSectionTitle(
                    'آخر العمولات',
                    'كل عمولة تظهر هنا بعد أول شحن مؤهل للمحال.',
                  ),
                  const SizedBox(height: 12),
                  if (recentCommissions.isEmpty)
                    _buildEmptyCard('لا توجد عمولات مضافة حتى الآن.')
                  else
                    ...recentCommissions.map(_buildCommissionCard),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(bool enabled) {
    final rewardAmount = (_affiliate['rewardAmount'] as num?)?.toDouble() ?? 0;
    final minAmount = (_affiliate['firstTopupMinAmount'] as num?)?.toDouble() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اكسب عمولة على أول شحن مؤهل',
                      style: AppTheme.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      enabled
                          ? 'عند تسجيل عميل من خلالك ثم تنفيذ أول شحن مؤهل، تُضاف عمولتك مباشرة إلى الرصيد.'
                          : 'نظام التسويق بالعمولة متوقف حاليًا من الإعدادات.',
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroPill('العمولة', CurrencyFormatter.ils(rewardAmount)),
              _heroPill('الحد الأدنى للشحن', CurrencyFormatter.ils(minAmount)),
              _heroPill('الحالة', enabled ? 'مفعل' : 'متوقف'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareCard() {
    final shareCode = _affiliate['shareCode']?.toString() ?? '';
    final sharePhone = _affiliate['sharePhone']?.toString() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بيانات الإحالة الخاصة بك', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'يمكن للعميل إدخال اسم المستخدم أو رقم الواتساب الخاص بك أثناء التسجيل.',
            style: AppTheme.caption.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
          _shareRow('اسم المستخدم', shareCode, () => _copyValue('اسم المستخدم', shareCode)),
          const SizedBox(height: 12),
          _shareRow('رقم الواتساب', sharePhone, () => _copyValue('رقم الواتساب', sharePhone)),
        ],
      ),
    );
  }

  Widget _shareRow(String label, String value, VoidCallback onCopy) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 6),
                Text(value.isEmpty ? 'غير متوفر' : value, style: AppTheme.bodyBold),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: value.isEmpty ? null : onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid(Map<String, dynamic> summary) {
    final cards = [
      _summaryCard('إجمالي الإحالات', '${(summary['totalReferrals'] as num?)?.toInt() ?? 0}', Icons.groups_rounded),
      _summaryCard('إحالات نشطة', '${(summary['activeReferrals'] as num?)?.toInt() ?? 0}', Icons.local_fire_department_rounded),
      _summaryCard('إحالات مؤهلة', '${(summary['qualifiedReferrals'] as num?)?.toInt() ?? 0}', Icons.verified_rounded),
      _summaryCard('إجمالي العمولات', CurrencyFormatter.ils((summary['totalRewards'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet_rounded),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return GridView.count(
          crossAxisCount: compact ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: compact ? 1.18 : 1.28,
          children: cards,
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primarySoft,
            child: Icon(icon, color: AppTheme.primary),
          ),
          const Spacer(),
          Text(value, style: AppTheme.h2),
          const SizedBox(height: 6),
          Text(title, style: AppTheme.caption.copyWith(height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.h3),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTheme.caption.copyWith(height: 1.6)),
      ],
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'waiting_for_first_topup';
    final label = switch (status) {
      'rewarded' => 'تمت العمولة',
      'waiting_for_qualification' => 'بانتظار شحن مؤهل',
      _ => 'بانتظار أول شحن',
    };
    final color = switch (status) {
      'rewarded' => AppTheme.success,
      'waiting_for_qualification' => AppTheme.accent,
      _ => AppTheme.textTertiary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.10),
              child: Icon(Icons.person_add_alt_1_rounded, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['fullName']?.toString().trim().isNotEmpty == true
                        ? item['fullName'].toString()
                        : (item['username']?.toString() ?? 'عميل جديد'),
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${item['username'] ?? 'user'}',
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: AppTheme.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionCard(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.success.withValues(alpha: 0.10),
              child: const Icon(
                Icons.volunteer_activism_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['referredFullName']?.toString().trim().isNotEmpty == true
                        ? item['referredFullName'].toString()
                        : (item['referredUsername']?.toString() ?? 'عميل'),
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أول شحن مؤهل: ${CurrencyFormatter.ils((item['qualifyingAmount'] as num?)?.toDouble() ?? 0)}',
                    style: AppTheme.caption.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.ils(
                (item['commissionAmount'] as num?)?.toDouble() ?? 0,
              ),
              style: AppTheme.bodyBold.copyWith(color: AppTheme.success),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(height: 1.7),
        ),
      ),
    );
  }

  Widget _heroPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: AppTheme.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
