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
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _cards = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  String? _actingCardId;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = await _auth.currentUser();
      final payload = await _api.getAdminPendingPrepaidMultipayApprovals(
        status: _statusFilter,
        search: _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
        _cards = (payload['cards'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openRoute(String routeName) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      return;
    }
    Navigator.pushNamed(context, routeName);
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

  Future<void> _setCardStatus(Map<String, dynamic> card, String action) async {
    await _runAdminAction(
      card,
      title: action == 'freeze' ? 'تجميد البطاقة' : 'تفعيل البطاقة',
      action: () => _api.updateAdminPrepaidMultipayCardStatus(
        cardId: card['id']?.toString() ?? '',
        action: action,
      ),
    );
  }

  Future<void> _adjustBalance(Map<String, dynamic> card) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعديل رصيد البطاقة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  hintText: 'اكتب موجبًا للشحن أو سالبًا للخصم',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
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
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      final amount = double.tryParse(amountController.text.trim()) ?? 0;
      await _runAdminAction(
        card,
        title: 'تعديل رصيد البطاقة',
        action: () => _api.adjustAdminPrepaidMultipayCardBalance(
          cardId: card['id']?.toString() ?? '',
          amount: amount,
          note: noteController.text,
        ),
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _cancelCard(Map<String, dynamic> card) async {
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إلغاء البطاقة'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تأكيد الإلغاء'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      await _runAdminAction(
        card,
        title: 'إلغاء البطاقة',
        action: () => _api.cancelAdminPrepaidMultipayCard(
          cardId: card['id']?.toString() ?? '',
          note: noteController.text,
        ),
      );
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _runAdminAction(
    Map<String, dynamic> card, {
    required String title,
    required Future<Map<String, dynamic>> Function() action,
  }) async {
    try {
      setState(() => _actingCardId = card['id']?.toString());
      await action();
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم التنفيذ',
        message: title,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر التنفيذ',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
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
        title: const Text('إدارة البطاقات المسبقة'),
        actions: [
          if (permissions.canUsePrepaidMultipayCards)
            IconButton(
              onPressed: () => _openRoute('/prepaid-multipay-cards'),
              tooltip: 'إضافة بطاقة',
              icon: const Icon(Icons.add_card_rounded),
            ),
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
                Text('إدارة البطاقات المسبقة', style: AppTheme.h2),
                const SizedBox(height: 6),
                Text(
                  'كل البطاقات المسبقة في قائمة واحدة مع التحكم بالرصيد والحالة.',
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!canManage)
                  ShwakelCard(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'لا تملك صلاحية مراجعة بطاقات الدفع المسبق.',
                      style: AppTheme.bodyAction,
                    ),
                  )
                else ...[
                  _buildFiltersAndSummary(),
                  const SizedBox(height: 12),
                  if (_cards.isEmpty)
                    ShwakelCard(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'لا توجد بطاقات ضمن هذا الفلتر.',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltersAndSummary() {
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _info('الكل', '${(_summary['count'] as num?)?.toInt() ?? 0}'),
              _info(
                'معلقة',
                '${(_summary['pendingCount'] as num?)?.toInt() ?? 0}',
              ),
              _info(
                'نشطة',
                '${(_summary['activeCount'] as num?)?.toInt() ?? 0}',
              ),
              _info(
                'الرصيد',
                CurrencyFormatter.ils(
                  (_summary['totalBalance'] as num?)?.toDouble() ?? 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _statusFilter,
            decoration: const InputDecoration(labelText: 'الحالة'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('كل البطاقات')),
              DropdownMenuItem(value: 'pending_approval', child: Text('معلقة')),
              DropdownMenuItem(value: 'active', child: Text('نشطة')),
              DropdownMenuItem(value: 'frozen', child: Text('مجمدة')),
              DropdownMenuItem(value: 'spent', child: Text('مستهلكة')),
              DropdownMenuItem(value: 'cancelled', child: Text('ملغاة')),
              DropdownMenuItem(value: 'rejected', child: Text('مرفوضة')),
            ],
            onChanged: (value) {
              setState(() => _statusFilter = value ?? 'all');
              _load();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'بحث',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
        ],
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
                  _statusLabel(card['status']?.toString() ?? ''),
                  style: AppTheme.caption.copyWith(color: AppTheme.warning),
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if ((card['status']?.toString() ?? '') == 'pending_approval') ...[
                FilledButton.icon(
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
                OutlinedButton.icon(
                  onPressed: acting ? null : () => _reviewCard(card, 'reject'),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('رفض'),
                ),
              ],
              if ((card['status']?.toString() ?? '') == 'active')
                OutlinedButton.icon(
                  onPressed: acting
                      ? null
                      : () => _setCardStatus(card, 'freeze'),
                  icon: const Icon(Icons.pause_circle_rounded),
                  label: const Text('تجميد'),
                ),
              if ((card['status']?.toString() ?? '') == 'frozen')
                FilledButton.icon(
                  onPressed: acting
                      ? null
                      : () => _setCardStatus(card, 'activate'),
                  icon: const Icon(Icons.play_circle_rounded),
                  label: const Text('تفعيل'),
                ),
              OutlinedButton.icon(
                onPressed: acting ? null : () => _adjustBalance(card),
                icon: const Icon(Icons.account_balance_wallet_rounded),
                label: const Text('شحن/خصم'),
              ),
              if ([
                'pending_approval',
                'active',
                'frozen',
              ].contains(card['status']?.toString() ?? ''))
                OutlinedButton.icon(
                  onPressed: acting ? null : () => _cancelCard(card),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('إلغاء'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending_approval':
        return 'بانتظار الموافقة';
      case 'active':
        return 'نشطة';
      case 'frozen':
        return 'مجمدة';
      case 'spent':
        return 'مستهلكة';
      case 'cancelled':
        return 'ملغاة';
      case 'rejected':
        return 'مرفوضة';
      case 'expired':
        return 'منتهية';
      default:
        return status.isEmpty ? '-' : status;
    }
  }
}
