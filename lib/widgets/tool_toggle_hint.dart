import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

class ToolToggleHint extends StatelessWidget {
  const ToolToggleHint({
    super.key,
    required this.message,
    this.icon = Icons.tune_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
