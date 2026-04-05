import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../shwakel_card.dart';

class AdminLocationCard extends StatelessWidget {
  final Map<String, dynamic> location;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMap;

  const AdminLocationCard({
    super.key,
    required this.location,
    this.isSaving = false,
    this.isDeleting = false,
    required this.onEdit,
    required this.onDelete,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    final title = location['title']?.toString() ?? 'فرع غير معروف';
    final address = location['address']?.toString() ?? 'لا يوجد عنوان';
    final isActive = location['isActive'] != false;
    final type = location['type']?.toString() ?? 'فرع';

    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.accent.withOpacity(0.1),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isActive ? AppTheme.secondary : AppTheme.textTertiary).withOpacity(0.1),
                  borderRadius: AppTheme.radiusSm,
                ),
                child: Text(
                  isActive ? 'مفعل' : 'معطل',
                  style: AppTheme.caption.copyWith(
                    color: isActive ? AppTheme.secondary : AppTheme.textTertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _iconButton(Icons.edit_rounded, AppTheme.primary, onEdit, isSaving),
              const SizedBox(width: 8),
              _iconButton(Icons.map_rounded, AppTheme.accent, onMap, false),
              const Spacer(),
              _iconButton(Icons.delete_rounded, AppTheme.warning, onDelete, isDeleting),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, Color color, VoidCallback onPressed, bool isLoading) {
    return InkWell(
      onTap: isLoading ? null : onPressed,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
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
