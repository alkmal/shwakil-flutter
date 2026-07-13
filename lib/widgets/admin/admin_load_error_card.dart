import 'package:flutter/material.dart';

import '../../localization/index.dart';
import '../../utils/app_theme.dart';
import '../shwakel_card.dart';

class AdminLoadErrorCard extends StatelessWidget {
  const AdminLoadErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return ShwakelCard(
      key: const ValueKey('admin-load-error'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 46,
            color: AppTheme.warning,
          ),
          const SizedBox(height: 14),
          Text(
            l.text(
              'تعذر تحميل البيانات مؤقتًا',
              'Data could not be loaded temporarily',
            ),
            style: AppTheme.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l.text('إعادة المحاولة', 'Retry')),
          ),
        ],
      ),
    );
  }
}
