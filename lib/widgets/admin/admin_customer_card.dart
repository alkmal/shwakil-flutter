import 'package:flutter/material.dart';

import '../../services/index.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/user_display_name.dart';
import '../shwakel_card.dart';

class AdminCustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onResendCredentials;
  final VoidCallback? onSendOtp;

  const AdminCustomerCard({
    super.key,
    required this.customer,
    this.isSelected = false,
    required this.onTap,
    this.onResendCredentials,
    this.onSendOtp,
  });

  String _displayName() {
    final username = customer['username']?.toString().trim() ?? '';
    return UserDisplayName.fromMap(customer, fallback: username);
  }

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  String _formatCreatedAt() {
    final raw = customer['createdAt']?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    if (date == null) {
      return '-';
    }
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }

  String _contactLine() {
    final parts = <String>[
      customer['username']?.toString().trim() ?? '',
      customer['whatsapp']?.toString().trim() ?? '',
      customer['email']?.toString().trim() ?? '',
    ].where((item) => item.isNotEmpty).toList();

    return parts.isEmpty ? '-' : parts.join('  |  ');
  }

  String _roleLabel(BuildContext context) {
    final explicit = customer['roleLabel']?.toString().trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final l = context.loc;
    return switch (customer['role']?.toString() ?? '') {
      'driver' => l.tr('shared.role_driver'),
      'verified_member' => l.tr('shared.role_verified_member'),
      'advanced_member' => l.tr('shared.role_verified_member'),
      'marketer' => l.tr('shared.role_marketer'),
      'support' => 'دعم',
      'admin' => 'إداري',
      'basic' => 'أساسي',
      'restricted' => 'مقيد',
      _ => 'مستخدم',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
    final isNegative = balance < 0;
    final role = customer['role']?.toString() ?? '';
    final verificationStatus =
        customer['transferVerificationStatus']?.toString() ?? 'unverified';
    final statusLabel = verificationStatus == 'approved'
        ? l.tr('widgets_admin_admin_customer_card.001')
        : verificationStatus == 'pending'
        ? l.tr('widgets_admin_admin_customer_card.002')
        : l.tr('widgets_admin_admin_customer_card.003');

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color:
                          (role == 'admin' ? AppTheme.accent : AppTheme.primary)
                              .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            (role == 'admin'
                                    ? AppTheme.accent
                                    : AppTheme.primary)
                                .withValues(alpha: 0.12),
                      ),
                    ),
                    child: Icon(
                      role == 'admin'
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
                      size: 21,
                      color: role == 'admin'
                          ? AppTheme.accent
                          : AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyBold,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _contactLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (verificationStatus == 'approved')
                    const Icon(
                      Icons.verified_rounded,
                      color: AppTheme.success,
                      size: 18,
                    ),
                  if (onResendCredentials != null || onSendOtp != null)
                    PopupMenuButton<_CustomerAction>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.radiusMd,
                      ),
                      itemBuilder: (context) => [
                        if (onResendCredentials != null)
                          PopupMenuItem<_CustomerAction>(
                            value: _CustomerAction.resendCredentials,
                            child: Text(
                              l.tr('widgets_admin_admin_customer_card.009'),
                            ),
                          ),
                        if (onSendOtp != null)
                          const PopupMenuItem<_CustomerAction>(
                            value: _CustomerAction.sendOtp,
                            child: Text('إرسال OTP'),
                          ),
                      ],
                      onSelected: (action) {
                        if (action == _CustomerAction.resendCredentials) {
                          onResendCredentials?.call();
                        } else if (action == _CustomerAction.sendOtp) {
                          onSendOtp?.call();
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(
                    l.tr('widgets_admin_admin_customer_card.004'),
                    _currency(balance),
                    isNegative
                        ? AppTheme.warning
                        : (balance > 0
                              ? AppTheme.primary
                              : AppTheme.textPrimary),
                  ),
                  _infoChip(
                    role == 'admin'
                        ? l.tr('widgets_admin_admin_customer_card.005')
                        : l.tr('widgets_admin_admin_customer_card.006'),
                    role == 'admin' ? _roleLabel(context) : statusLabel,
                    role == 'admin'
                        ? AppTheme.accent
                        : verificationStatus == 'approved'
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                  ),
                  _infoChip(
                    l.tr('screens_admin_customers_screen.055'),
                    _formatCreatedAt(),
                    AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum _CustomerAction { resendCredentials, sendOtp }
