import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../shwakel_card.dart';

class AdminSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const AdminSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = color ?? AppTheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusLg,
      child: ShwakelCard(
        padding: const EdgeInsets.all(22),
        shadowLevel: ShwakelShadowLevel.soft,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.10),
                    borderRadius: AppTheme.radiusMd,
                  ),
                  child: Icon(icon, color: themeColor, size: 24),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: AppTheme.radiusSm,
                  ),
                  child: Text(
                    'مؤشر',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppTheme.h2.copyWith(
                color: themeColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminDashboardSummary extends StatelessWidget {
  final Map<String, dynamic> summary;

  const AdminDashboardSummary({super.key, required this.summary});

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  @override
  Widget build(BuildContext context) {
    final totalBalance = (summary['totalBalance'] as num?)?.toDouble() ?? 0;
    final customerCount = (summary['customerCount'] as num?)?.toInt() ?? 0;
    final adminCount = (summary['adminCount'] as num?)?.toInt() ?? 0;
    final totalPrintingDebt =
        (summary['totalPrintingDebt'] as num?)?.toDouble() ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width >= 1100
            ? (width - 48) / 4
            : width >= 720
            ? (width - 16) / 2
            : width;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: AdminSummaryCard(
                title: 'إجمالي الأرصدة',
                value: _currency(totalBalance),
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.primary,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AdminSummaryCard(
                title: 'عدد العملاء',
                value: customerCount.toString(),
                icon: Icons.people_alt_rounded,
                color: AppTheme.secondary,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AdminSummaryCard(
                title: 'ديون الطباعة',
                value: _currency(totalPrintingDebt),
                icon: Icons.print_rounded,
                color: AppTheme.warning,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AdminSummaryCard(
                title: 'المسؤولون',
                value: adminCount.toString(),
                icon: Icons.admin_panel_settings_rounded,
                color: AppTheme.accent,
              ),
            ),
          ],
        );
      },
    );
  }
}
