import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../shwakel_card.dart';
import '../shwakel_button.dart';

class AdminDeviceRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool isProcessing;
  final Function(bool approve) onAction;
  final VoidCallback onTap;

  const AdminDeviceRequestCard({
    super.key,
    required this.request,
    this.isProcessing = false,
    required this.onAction,
    required this.onTap,
  });

  String _displayName() {
    final user = Map<String, dynamic>.from(request['user'] as Map? ?? const {});
    final fullName = user['fullName']?.toString().trim() ?? '';
    final username = user['username']?.toString().trim() ?? '';
    return fullName.isNotEmpty ? fullName : username;
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = request['deviceName']?.toString() ?? 'جهاز غير معروف';
    final deviceId = request['deviceId']?.toString() ?? 'ID غير متوفر';
    final createdAt = request['createdAt']?.toString() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: const Icon(
                Icons.important_devices_rounded,
                color: AppTheme.primary,
              ),
            ),
            title: InkWell(
              onTap: onTap,
              child: Text(_displayName(), style: AppTheme.bodyBold),
            ),
            subtitle: Text('$deviceName • $deviceId', style: AppTheme.caption),
          ),
          const SizedBox(height: 12),
          Text(
            'طلب الوصول: $createdAt',
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ShwakelButton(
                  label: 'قبول',
                  isLoading: isProcessing,
                  onPressed: () => onAction(true),
                  color: AppTheme.secondary,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShwakelButton(
                  label: 'رفض',
                  isLoading: isProcessing,
                  onPressed: () => onAction(false),
                  color: AppTheme.warning,
                  icon: Icons.cancel_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
