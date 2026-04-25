import 'package:flutter/material.dart';

import '../../localization/index.dart';
import '../../utils/app_theme.dart';
import '../shwakel_button.dart';

class AdminPaginationFooter extends StatelessWidget {
  final int currentPage;
  final int lastPage;
  final Function(int page) onPageChanged;
  final String? previousLabel;
  final String? nextLabel;
  final int? totalPages;
  final int? totalItems;
  final int? itemsPerPage;

  const AdminPaginationFooter({
    super.key,
    required this.currentPage,
    int? lastPage,
    this.totalPages,
    this.totalItems,
    this.itemsPerPage,
    required this.onPageChanged,
    this.previousLabel,
    this.nextLabel,
  }) : lastPage = lastPage ?? totalPages ?? 1;

  @override
  Widget build(BuildContext context) {
    if (lastPage <= 1) {
      return const SizedBox.shrink();
    }

    final l = context.loc;
    final textDirection = l.textDirection;

    return Directionality(
      textDirection: textDirection,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previousButton = ShwakelButton(
              label:
                  previousLabel ??
                  l.tr('widgets_admin_admin_pagination_footer.001'),
              isSecondary: true,
              onPressed: currentPage > 1
                  ? () => onPageChanged(currentPage - 1)
                  : null,
              icon: Icons.arrow_back_rounded,
              iconAtEnd: false,
            );
            final nextButton = ShwakelButton(
              label:
                  nextLabel ??
                  l.tr('widgets_admin_admin_pagination_footer.002'),
              onPressed: currentPage < lastPage
                  ? () => onPageChanged(currentPage + 1)
                  : null,
              icon: Icons.arrow_forward_rounded,
              iconAtEnd: true,
            );
            final pageBadge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.05),
                borderRadius: AppTheme.radiusMd,
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                ),
              ),
              child: Text(
                '$currentPage / $lastPage',
                style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
              ),
            );

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: previousButton),
                const SizedBox(width: 10),
                pageBadge,
                const SizedBox(width: 10),
                Flexible(child: nextButton),
              ],
            );
          },
        ),
      ),
    );
  }
}
