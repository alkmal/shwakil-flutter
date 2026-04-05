import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class AdminSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;

  const AdminSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = iconColor ?? AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 820 || trailing == null;
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.10),
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Icon(icon, color: themeColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.h2),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                if (trailing != null) ...[
                  const SizedBox(height: 14),
                  trailing!,
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: header),
              const SizedBox(width: 16),
              trailing!,
            ],
          );
        },
      ),
    );
  }
}
