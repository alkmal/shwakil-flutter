import 'package:flutter/material.dart';

import '../../services/index.dart';
import '../../utils/app_theme.dart';
import '../shwakel_card.dart';

class AdminLocationCard extends StatelessWidget {
  final Map<String, dynamic> location;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const AdminLocationCard({
    super.key,
    required this.location,
    this.isSaving = false,
    this.isDeleting = false,
    required this.onEdit,
    required this.onDelete,
    required this.onMap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final title =
        location['title']?.toString() ??
        l.tr('widgets_admin_admin_location_card.001');
    final address =
        location['address']?.toString() ??
        l.tr('widgets_admin_admin_location_card.002');
    final isActive = location['isActive'] != false;
    final type =
        location['type']?.toString() ??
        l.tr('widgets_admin_admin_location_card.003');
    final status = location['status']?.toString() ?? 'approved';
    final linkedDisplay =
        location['linkedDisplayName']?.toString().trim() ?? '';
    final createdByDisplay =
        location['createdByDisplayName']?.toString().trim() ?? '';
    final statusColor = switch (status) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final statusLabel = switch (status) {
      'approved' => l.tr('widgets_admin_admin_location_card.006'),
      'rejected' => l.tr('widgets_admin_admin_location_card.007'),
      _ => l.tr('widgets_admin_admin_location_card.008'),
    };

    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                child: const Icon(Icons.place_rounded, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.bodyBold),
                    Text('$type • $address', style: AppTheme.caption),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: AppTheme.radiusSm,
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTheme.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isActive ? AppTheme.secondary : AppTheme.textTertiary)
                              .withValues(alpha: 0.1),
                      borderRadius: AppTheme.radiusSm,
                    ),
                    child: Text(
                      isActive
                          ? l.tr('widgets_admin_admin_location_card.004')
                          : l.tr('widgets_admin_admin_location_card.005'),
                      style: AppTheme.caption.copyWith(
                        color: isActive
                            ? AppTheme.secondary
                            : AppTheme.textTertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (linkedDisplay.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              l.tr(
                'widgets_admin_admin_location_card.009',
                params: {'account': linkedDisplay},
              ),
              style: AppTheme.caption.copyWith(color: AppTheme.primary),
            ),
          ],
          if (createdByDisplay.isNotEmpty && createdByDisplay != linkedDisplay) ...[
            const SizedBox(height: 4),
            Text(
              l.tr(
                'widgets_admin_admin_location_card.010',
                params: {'account': createdByDisplay},
              ),
              style: AppTheme.caption,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _iconButton(
                Icons.edit_rounded,
                AppTheme.primary,
                onEdit,
                isSaving,
              ),
              const SizedBox(width: 8),
              _iconButton(Icons.map_rounded, AppTheme.accent, onMap, isSaving),
              if (onApprove != null) ...[
                const SizedBox(width: 8),
                _iconButton(
                  Icons.check_circle_rounded,
                  AppTheme.success,
                  onApprove!,
                  isSaving,
                ),
              ],
              if (onReject != null) ...[
                const SizedBox(width: 8),
                _iconButton(
                  Icons.cancel_rounded,
                  AppTheme.error,
                  onReject!,
                  isSaving,
                ),
              ],
              const Spacer(),
              _iconButton(
                Icons.delete_rounded,
                AppTheme.warning,
                onDelete,
                isDeleting,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    IconData icon,
    Color color,
    VoidCallback onPressed,
    bool isLoading,
  ) {
    return InkWell(
      onTap: isLoading ? null : onPressed,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppTheme.radiusMd,
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, color: color, size: 20),
      ),
    );
  }
}
