import 'package:flutter/material.dart';

import '../../localization/index.dart';
import '../../utils/app_theme.dart';
import '../../utils/currency_formatter.dart';
import '../shwakel_card.dart';

class AdminTransactionAuditCard extends StatelessWidget {
  const AdminTransactionAuditCard({super.key, required this.transaction});

  final Map<String, dynamic> transaction;

  String _currency(num? amount) => CurrencyFormatter.ils(amount);

  String _typeLabel(
    BuildContext context,
    String type,
    Map<String, dynamic> metadata,
  ) {
    final l = context.loc;
    switch (type) {
      case 'topup':
        return l.tr('widgets_admin_transaction_audit_card.001');
      case 'transfer_out':
        return l.tr('widgets_admin_transaction_audit_card.002');
      case 'transfer_in':
        return l.tr('widgets_admin_transaction_audit_card.003');
      case 'redeem_card':
        return l.tr('widgets_admin_transaction_audit_card.004');
      case 'resell_card':
        return l.tr('widgets_admin_transaction_audit_card.005');
      case 'issue_cards':
        return l.tr('widgets_admin_transaction_audit_card.006');
      case 'withdrawal_request':
        return l.tr('widgets_admin_transaction_audit_card.007');
      case 'withdrawal_rejected':
        return l.tr('widgets_admin_transaction_audit_card.008');
      case 'withdrawal_completed':
        return l.tr('widgets_admin_transaction_audit_card.009');
      case 'balance_credit':
        return (metadata['sourceType']?.toString() ?? '') ==
                'printing_debt_settlement'
            ? l.tr('widgets_admin_transaction_audit_card.010')
            : l.tr('widgets_admin_transaction_audit_card.011');
      case 'app_fee_credit':
        return l.tr('widgets_admin_transaction_audit_card.012');
      default:
        return type.trim().isEmpty
            ? l.tr('widgets_admin_transaction_audit_card.013')
            : type;
    }
  }

  String? _actorLine(
    BuildContext context,
    String type,
    Map<String, dynamic> metadata,
  ) {
    final l = context.loc;
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
          return l.tr(
            'widgets_admin_transaction_audit_card.014',
            params: {'username': byUsername},
          );
        }
        break;
      case 'transfer_out':
        if (recipientUsername != null && recipientUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.015',
            params: {'username': recipientUsername},
          );
        }
        break;
      case 'transfer_in':
        if (senderUsername != null && senderUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.016',
            params: {'username': senderUsername},
          );
        }
        break;
      case 'redeem_card':
        if (customerName != null && customerName.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.017',
            params: {'name': customerName},
          );
        }
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.014',
            params: {'username': byUsername},
          );
        }
        break;
      case 'resell_card':
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.014',
            params: {'username': byUsername},
          );
        }
        break;
      case 'balance_credit':
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.014',
            params: {'username': byUsername},
          );
        }
        break;
      case 'issue_cards':
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.018',
            params: {'username': byUsername},
          );
        }
        final usedDebt =
            (metadata['usedPrintingDebt'] as num?)?.toDouble() ?? 0;
        if (usedDebt > 0) {
          return l.tr(
            'widgets_admin_transaction_audit_card.019',
            params: {'amount': _currency(usedDebt)},
          );
        }
        break;
      case 'app_fee_credit':
        if (targetUsername != null && targetUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.020',
            params: {'username': targetUsername},
          );
        }
        if (sourceUsername != null && sourceUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.021',
            params: {'username': sourceUsername},
          );
        }
        if (sourceType != null && sourceType.isNotEmpty) {
          switch (sourceType) {
            case 'topup':
              return l.tr('widgets_admin_transaction_audit_card.022');
            case 'transfer':
              return l.tr('widgets_admin_transaction_audit_card.023');
            case 'card_redeem':
              return l.tr('widgets_admin_transaction_audit_card.024');
            case 'card_resell':
              return l.tr('widgets_admin_transaction_audit_card.025');
          }
        }
        break;
      case 'withdrawal_request':
        return l.tr('widgets_admin_transaction_audit_card.026');
      case 'withdrawal_rejected':
        return l.tr('widgets_admin_transaction_audit_card.027');
      case 'withdrawal_completed':
        return l.tr('widgets_admin_transaction_audit_card.028');
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
    final actorLine = _actorLine(context, type, metadata);
    final performedBy = _performedByLine(context, metadata);
    final sourceLine = _sourceLine(context, metadata);
    final accentColor = _accentColor(
      isRejected: isRejected,
      amount: amount,
      type: type,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;

        final leadingIcon = Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _iconFor(isRejected: isRejected, amount: amount, type: type),
            color: accentColor,
            size: 20,
          ),
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _typeLabel(context, type, metadata),
                  style: AppTheme.bodyBold,
                ),
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
                      context.loc.tr(
                        'widgets_admin_transaction_audit_card.029',
                      ),
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
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            if (actorLine != null) ...[
              const SizedBox(height: 4),
              Text(
                actorLine,
                style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            if (performedBy != null) ...[
              const SizedBox(height: 4),
              Text(
                context.loc.tr(
                  'screens_transactions_screen.104',
                  params: {'actor': performedBy},
                ),
                style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            if (sourceLine != null) ...[
              const SizedBox(height: 4),
              Text(
                context.loc.tr(
                  'screens_transactions_screen.105',
                  params: {'source': sourceLine},
                ),
                style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ],
        );

        final amountBlock = Column(
          crossAxisAlignment: isCompact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _currency(amount),
                style: AppTheme.bodyBold.copyWith(color: accentColor),
              ),
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
                  context.loc.tr(
                    isNearBranch
                        ? 'widgets_admin_transaction_audit_card.030'
                        : 'widgets_admin_transaction_audit_card.031',
                  ),
                  style: AppTheme.caption.copyWith(
                    color: isNearBranch ? AppTheme.primary : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ],
        );

        return ShwakelCard(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 16,
            vertical: isCompact ? 12 : 14,
          ),
          shadowLevel: ShwakelShadowLevel.soft,
          borderRadius: BorderRadius.circular(24),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leadingIcon,
                        const SizedBox(width: 12),
                        Expanded(child: details),
                      ],
                    ),
                    const SizedBox(height: 12),
                    amountBlock,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leadingIcon,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                    const SizedBox(width: 12),
                    amountBlock,
                  ],
                ),
        );
      },
    );
  }

  String? _performedByLine(
    BuildContext context,
    Map<String, dynamic> metadata,
  ) {
    return _metadataPersonLabel(
      metadata,
      const [
        'byDisplayName',
        'byFullName',
        'byAdminDisplayName',
        'byAdminFullName',
        'actorDisplayName',
        'actorFullName',
        'approvedByDisplayName',
        'approvedByFullName',
        'issuerDisplayName',
        'issuedByDisplayName',
        'redeemedByDisplayName',
        'sellerDisplayName',
        'merchantDisplayName',
      ],
      const [
        'byUsername',
        'byAdminUsername',
        'actorUsername',
        'approvedByUsername',
        'issuerUsername',
        'issuedByUsername',
        'redeemedByUsername',
        'sellerUsername',
        'merchantUsername',
      ],
    );
  }

  String? _sourceLine(BuildContext context, Map<String, dynamic> metadata) {
    final personSource = _metadataPersonLabel(
      metadata,
      const [
        'sourceDisplayName',
        'sourceFullName',
        'cardSourceDisplayName',
        'cardSourceFullName',
        'senderDisplayName',
        'buyerDisplayName',
        'ownerDisplayName',
        'targetDisplayName',
      ],
      const [
        'sourceUsername',
        'cardSourceUsername',
        'senderUsername',
        'buyerUsername',
        'ownerUsername',
        'targetUsername',
      ],
    );
    if (personSource != null) {
      return personSource;
    }

    final sourceType = metadata['sourceType']?.toString().trim();
    if (sourceType == null || sourceType.isEmpty) {
      return null;
    }

    final l = context.loc;
    switch (sourceType) {
      case 'topup':
      case 'finance_topup':
        return l.tr('screens_transactions_screen.111');
      case 'transfer':
        return l.tr('screens_transactions_screen.112');
      case 'card_redeem':
      case 'redeem_card':
        return l.tr('screens_transactions_screen.113');
      case 'card_resell':
      case 'resell_card':
        return l.tr('screens_transactions_screen.114');
      case 'card_print_request':
        return l.tr('screens_transactions_screen.106');
      case 'admin_manual_credit':
        return l.tr('screens_transactions_screen.107');
      case 'admin_manual_deduction':
        return l.tr('screens_transactions_screen.108');
      case 'printing_debt_settlement':
        return l.tr('widgets_admin_transaction_audit_card.010');
      case 'prepaid_multipay_card':
        return l.tr('screens_transactions_screen.109');
      case 'prepaid_multipay_card_payment':
      case 'prepaid_multipay_nfc_payment':
        return l.tr('screens_transactions_screen.110');
      default:
        return sourceType;
    }
  }

  String? _metadataPersonLabel(
    Map<String, dynamic> metadata,
    List<String> displayKeys,
    List<String> usernameKeys,
  ) {
    for (final key in displayKeys) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    for (final key in usernameKeys) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value.startsWith('@') ? value : '@$value';
      }
    }
    return null;
  }
}
