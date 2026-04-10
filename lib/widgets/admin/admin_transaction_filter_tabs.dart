import 'package:flutter/material.dart';

import '../../localization/index.dart';
import '../../utils/app_theme.dart';
import 'admin_enums.dart';

class AdminTransactionFilterTabs extends StatelessWidget {
  final AdminTransactionAuditFilter currentFilter;
  final Function(AdminTransactionAuditFilter filter) onFilterChanged;

  const AdminTransactionFilterTabs({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: AppTheme.radiusXl,
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterButton(
            l.tr('widgets_admin_transaction_filter_tabs.001'),
            AdminTransactionAuditFilter.all,
          ),
          _filterButton(
            l.tr('widgets_admin_transaction_filter_tabs.002'),
            AdminTransactionAuditFilter.nearBranch,
          ),
          _filterButton(
            l.tr('widgets_admin_transaction_filter_tabs.003'),
            AdminTransactionAuditFilter.outsideBranches,
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String label, AdminTransactionAuditFilter filter) {
    final isSelected = currentFilter == filter;
    return GestureDetector(
      onTap: () => onFilterChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: AppTheme.radiusXl,
          boxShadow: isSelected ? AppTheme.softShadow : null,
        ),
        child: Text(
          label,
          style: AppTheme.caption.copyWith(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
