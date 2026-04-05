import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../shwakel_card.dart';

class AdminTransactionAuditCard extends StatelessWidget {
  const AdminTransactionAuditCard({super.key, required this.transaction});

  final Map<String, dynamic> transaction;

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  String _typeLabel(String type, Map<String, dynamic> metadata) {
    switch (type) {
      case 'topup':
        return 'شحن رصيد';
      case 'transfer_out':
        return 'تحويل صادر';
      case 'transfer_in':
        return 'تحويل وارد';
      case 'redeem_card':
        return 'اعتماد بطاقة';
      case 'resell_card':
        return 'إعادة بيع بطاقة';
      case 'issue_cards':
        return 'إصدار بطاقات';
      case 'withdrawal_request':
        return 'طلب سحب';
      case 'withdrawal_rejected':
        return 'رفض طلب السحب';
      case 'withdrawal_completed':
        return 'تنفيذ السحب';
      case 'balance_credit':
        return (metadata['sourceType']?.toString() ?? '') ==
                'printing_debt_settlement'
            ? 'تسوية دين الطباعة'
            : 'إضافة رصيد';
      case 'app_fee_credit':
        return 'رسوم خدمة';
      default:
        return type.trim().isEmpty ? 'حركة غير معروفة' : type;
    }
  }

  String? _actorLine(String type, Map<String, dynamic> metadata) {
    final byUsername = metadata['byUsername']?.toString().trim();
    final senderUsername = metadata['senderUsername']?.toString().trim();
    final recipientUsername = metadata['recipientUsername']?.toString().trim();
    final customerName = metadata['customerName']?.toString().trim();
    final targetUsername = metadata['targetUsername']?.toString().trim();
    final sourceUsername = metadata['sourceUsername']?.toString().trim();
    final sourceType = metadata['sourceType']?.toString().trim();

    switch (type) {
      case 'topup':
        if (byUsername != null && byUsername.isNotEmpty) {
          return 'نفّذها: @$byUsername';
        }
        break;
      case 'transfer_out':
        if (recipientUsername != null && recipientUsername.isNotEmpty) {
          return 'إلى: @$recipientUsername';
        }
        break;
      case 'transfer_in':
        if (senderUsername != null && senderUsername.isNotEmpty) {
          return 'من: @$senderUsername';
        }
        break;
      case 'redeem_card':
        if (customerName != null && customerName.isNotEmpty) {
          return 'العميل: $customerName';
        }
        if (byUsername != null && byUsername.isNotEmpty) {
          return 'نفّذها: @$byUsername';
        }
        break;
      case 'resell_card':
        if (byUsername != null && byUsername.isNotEmpty) {
          return 'نفّذها: @$byUsername';
        }
        break;
      case 'balance_credit':
        if (byUsername != null && byUsername.isNotEmpty) {
          return 'نفّذها: @$byUsername';
        }
        break;
      case 'issue_cards':
        if (byUsername != null && byUsername.isNotEmpty) {
          return 'أصدرها: @$byUsername';
        }
        final usedDebt =
            (metadata['usedPrintingDebt'] as num?)?.toDouble() ?? 0;
        if (usedDebt > 0) {
          return 'استخدم من دين الطباعة: ${_currency(usedDebt)}';
        }
        break;
      case 'app_fee_credit':
        if (targetUsername != null && targetUsername.isNotEmpty) {
          return 'مرتبطة بـ: @$targetUsername';
        }
        if (sourceUsername != null && sourceUsername.isNotEmpty) {
          return 'مأخوذة من: @$sourceUsername';
        }
        if (sourceType != null && sourceType.isNotEmpty) {
          switch (sourceType) {
            case 'topup':
              return 'مصدرها: شحن رصيد';
            case 'transfer':
              return 'مصدرها: تحويل رصيد';
            case 'card_redeem':
              return 'مصدرها: اعتماد بطاقة';
            case 'card_resell':
              return 'مصدرها: إعادة بيع بطاقة';
          }
        }
        break;
      case 'withdrawal_request':
        return 'بانتظار مراجعة الإدارة';
      case 'withdrawal_rejected':
        return 'أعيد الرصيد إلى الحساب';
      case 'withdrawal_completed':
        return 'تم تنفيذ الطلب';
    }

    return null;
  }

  IconData _iconFor({
    required bool isRejected,
    required double amount,
    required String type,
  }) {
    if (isRejected) return Icons.block_rounded;

    switch (type) {
      case 'transfer_out':
      case 'withdrawal_request':
      case 'resell_card':
        return Icons.north_east_rounded;
      case 'transfer_in':
      case 'topup':
      case 'balance_credit':
      case 'redeem_card':
        return Icons.south_west_rounded;
      case 'issue_cards':
        return Icons.add_card_rounded;
      default:
        return amount > 0
            ? Icons.add_circle_rounded
            : Icons.remove_circle_rounded;
    }
  }

  Color _accentColor({
    required bool isRejected,
    required double amount,
    required String type,
  }) {
    if (isRejected) return AppTheme.error;

    switch (type) {
      case 'transfer_out':
      case 'withdrawal_request':
      case 'resell_card':
        return AppTheme.warning;
      case 'issue_cards':
        return AppTheme.accent;
      default:
        return amount >= 0 ? AppTheme.primary : AppTheme.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = transaction['type']?.toString() ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final createdAt = transaction['createdAt']?.toString() ?? '';
    final metadata = Map<String, dynamic>.from(
      transaction['metadata'] as Map? ?? const {},
    );
    final audit = metadata['locationAudit'];
    final isNearBranch = audit is Map && audit['isNearSupportedBranch'] == true;
    final status = transaction['status']?.toString() ?? 'completed';
    final isRejected = status == 'rejected' || type == 'withdrawal_rejected';
    final actorLine = _actorLine(type, metadata);
    final accentColor = _accentColor(
      isRejected: isRejected,
      amount: amount,
      type: type,
    );

    return ShwakelCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconFor(isRejected: isRejected, amount: amount, type: type),
              color: accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_typeLabel(type, metadata), style: AppTheme.bodyBold),
                    if (isRejected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.10),
                          borderRadius: AppTheme.radiusSm,
                        ),
                        child: Text(
                          'مرفوضة',
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  createdAt,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (actorLine != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    actorLine,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currency(amount),
                style: AppTheme.bodyBold.copyWith(color: accentColor),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isNearBranch
                        ? Icons.place_rounded
                        : Icons.location_off_outlined,
                    color: isNearBranch ? AppTheme.primary : AppTheme.warning,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isNearBranch ? 'قرب فرع' : 'خارج النطاق',
                    style: AppTheme.caption.copyWith(
                      color: isNearBranch ? AppTheme.primary : AppTheme.warning,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
