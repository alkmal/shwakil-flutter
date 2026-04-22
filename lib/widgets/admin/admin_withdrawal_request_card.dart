import 'package:flutter/material.dart';

import '../../localization/index.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../shwakel_button.dart';
import '../shwakel_card.dart';

class AdminWithdrawalRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool isProcessing;
  final Function(bool approve) onAction;
  final VoidCallback onTap;

  const AdminWithdrawalRequestCard({
    super.key,
    required this.request,
    this.isProcessing = false,
    required this.onAction,
    required this.onTap,
  });

  String _displayName() {
    final user = Map<String, dynamic>.from(request['user'] as Map? ?? const {});
    final fullName = user['fullName']?.toString().trim() ?? '';
    final username = user['username']?.toString().trim() ?? '';
    return fullName.isNotEmpty ? fullName : username;
  }

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final amount = (request['amount'] as num?)?.toDouble() ?? 0;
    final method = request['method']?.toString() ??
        l.tr('widgets_admin_withdrawal_request_card.001');
    final details = request['methodDetails']?.toString() ??
        l.tr('widgets_admin_withdrawal_request_card.002');
    final createdAt = request['createdAt']?.toString() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.money_off_rounded,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName(), style: AppTheme.bodyBold),
                      const SizedBox(height: 2),
                      Text('$method - $details', style: AppTheme.caption),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Text(
                  _currency(amount),
                  style: AppTheme.h3.copyWith(color: AppTheme.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: AppTheme.radiusMd,
            ),
            child: Text(
              l.tr(
                'widgets_admin_withdrawal_request_card.003',
                params: {'date': createdAt},
              ),
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ShwakelButton(
                  label: l.tr('widgets_admin_withdrawal_request_card.004'),
                  isLoading: isProcessing,
                  onPressed: () => onAction(true),
                  color: AppTheme.secondary,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShwakelButton(
                  label: l.tr('widgets_admin_withdrawal_request_card.005'),
                  isLoading: isProcessing,
                  onPressed: () => onAction(false),
                  color: AppTheme.warning,
                  icon: Icons.cancel_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
