import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminPrepaidMultipayApprovalsScreen extends StatefulWidget {
  const AdminPrepaidMultipayApprovalsScreen({super.key});

  @override
  State<AdminPrepaidMultipayApprovalsScreen> createState() =>
      _AdminPrepaidMultipayApprovalsScreenState();
}

class _AdminPrepaidMultipayApprovalsScreenState
    extends State<AdminPrepaidMultipayApprovalsScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _cards = const [];
  bool _isLoading = true;
  String? _actingCardId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = await _auth.currentUser();
      final payload = await _api.getAdminPendingPrepaidMultipayApprovals();
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
        _cards = (payload['cards'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل الطلبات',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _reviewCard(Map<String, dynamic> card, String action) async {
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == 'approve' ? 'اعتماد البطاقة' : 'رفض البطاقة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card['label']?.toString() ?? 'بطاقة دفع مسبق',
                style: AppTheme.bodyBold,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة للإدارة أو المستخدم',
                  hintText: 'اختيارية',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action == 'approve' ? 'اعتماد' : 'رفض'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      setState(() => _actingCardId = card['id']?.toString());
      await _api.reviewAdminPrepaidMultipayApproval(
        cardId: card['id']?.toString() ?? '',
        action: action,
        note: noteController.text,
      );
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: action == 'approve' ? 'تم اعتماد البطاقة' : 'تم رفض البطاقة',
        message: action == 'approve'
            ? 'أصبحت البطاقة جاهزة للاستخدام.'
            : 'تم رفض البطاقة وإرجاع الرصيد إلى صاحبها.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تنفيذ المراجعة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      noteController.dispose();
      if (mounted) {
        setState(() => _actingCardId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = AppPermissions.fromUser(_user);
    final canManage = permissions.canManageSystemSettings;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('موافقات البطاقات المسبقة'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('موافقات البطاقات المسبقة', style: AppTheme.h2),
                const SizedBox(height: 6),
                Text(
                  'كل بطاقة جديدة تبقى معلقة حتى تعتمدها الإدارة.',
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 16),
                if (!canManage)
                  ShwakelCard(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'لا تملك صلاحية مراجعة بطاقات الدفع المسبق.',
                      style: AppTheme.bodyAction,
                    ),
                  )
                else if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_cards.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'لا توجد بطاقات معلقة حاليًا.',
                      style: AppTheme.bodyAction,
                    ),
                  )
                else
                  for (final entry in _cards.asMap().entries)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: entry.key == _cards.length - 1 ? 0 : 12,
                      ),
                      child: _buildApprovalCard(entry.value),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> card) {
    final acting = _actingCardId == card['id']?.toString();
    final ownerName = card['ownerFullName']?.toString().trim();
    final ownerUsername = card['ownerUsername']?.toString().trim() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card['label']?.toString() ?? 'بطاقة دفع مسبق',
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card['cardNumber']?.toString() ?? '',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'بانتظار الموافقة',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _info(
                'المالك',
                ownerName?.isNotEmpty == true ? ownerName! : ownerUsername,
              ),
              _info('المستخدم', ownerUsername.isNotEmpty ? ownerUsername : '-'),
              _info(
                'الرصيد',
                CurrencyFormatter.ils(
                  (card['balance'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _info('الانتهاء', card['expiryLabel']?.toString() ?? '-'),
              _info('أنشئت', card['createdAt']?.toString() ?? '-'),
            ],
          ),
          if ((card['approvalNote']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              card['approvalNote']?.toString() ?? '',
              style: AppTheme.bodyAction,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: acting ? null : () => _reviewCard(card, 'approve'),
                  icon: acting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: const Text('اعتماد'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: acting ? null : () => _reviewCard(card, 'reject'),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('رفض'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
