import 'package:flutter/material.dart';

import '../../services/index.dart';
import '../../utils/app_theme.dart';
import '../shwakel_button.dart';
import '../shwakel_card.dart';

class AdminSettingsGroup extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final String? saveLabel;
  final bool isSaving;
  final VoidCallback? onSave;

  const AdminSettingsGroup({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.saveLabel,
    this.isSaving = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Icon(icon, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.h3),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (onSave != null)
                ShwakelButton(
                  label:
                      saveLabel ??
                      l.tr('widgets_admin_admin_settings_group.001'),
                  isLoading: isSaving,
                  onPressed: onSave,
                  isSecondary: true,
                  icon: Icons.save_rounded,
                ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}
