import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../shwakel_card.dart';

class AdminCustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final bool isSelected;
  final VoidCallback onTap;

  const AdminCustomerCard({
    super.key,
    required this.customer,
    this.isSelected = false,
    required this.onTap,
  });

  String _displayName() {
    final fullName = customer['fullName']?.toString().trim() ?? '';
    final username = customer['username']?.toString().trim() ?? '';
    return fullName.isNotEmpty ? fullName : username;
  }

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  @override
  Widget build(BuildContext context) {
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
    final isNegative = balance < 0;
    final role = customer['role']?.toString() ?? '';
    final verificationStatus =
        customer['transferVerificationStatus']?.toString() ?? 'unverified';
    final statusLabel = verificationStatus == 'approved'
        ? 'موثق'
        : verificationStatus == 'pending'
        ? 'قيد المراجعة'
        : 'غير موثق';

    return ShwakelCard(
      padding: EdgeInsets.zero,
      shadowLevel: isSelected
          ? ShwakelShadowLevel.premium
          : ShwakelShadowLevel.soft,
      color: isSelected
          ? AppTheme.primary.withValues(alpha: 0.05)
          : Colors.white,
      borderWidth: isSelected ? 2 : 1,
      borderColor: isSelected
          ? AppTheme.primary
          : AppTheme.border.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusLg,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        (role == 'admin' ? AppTheme.accent : AppTheme.primary)
                            .withValues(alpha: 0.10),
                    child: Icon(
                      role == 'admin'
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
                      size: 20,
                      color: role == 'admin'
                          ? AppTheme.accent
                          : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _displayName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyBold,
                    ),
                  ),
                  if (verificationStatus == 'approved')
                    const Icon(
                      Icons.verified_rounded,
                      color: AppTheme.success,
                      size: 18,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الرصيد',
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      _currency(balance),
                      style: AppTheme.bodyBold.copyWith(
                        color: isNegative
                            ? AppTheme.warning
                            : (balance > 0
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    role == 'admin' ? 'نوع الحساب' : 'حالة التوثيق',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    role == 'admin' ? 'مسؤول' : statusLabel,
                    style: AppTheme.caption.copyWith(
                      color: verificationStatus == 'approved'
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (role == 'admin')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: AppTheme.radiusSm,
                  ),
                  child: Text(
                    'مسؤول نظام',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
