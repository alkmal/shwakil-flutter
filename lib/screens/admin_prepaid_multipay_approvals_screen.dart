import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/admin/admin_load_error_card.dart';
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
  String? _loadError;
  String? _actingCardId;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _isLoading = _user == null;
    });
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
        _loadError = null;
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
      setState(() => _loadError = ErrorMessageService.sanitize(error));
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
    final l = context.loc;
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
                decoration: InputDecoration(
                  labelText: l.text(
                    'ملاحظة للإدارة أو المستخدم',
                    'Note for admin or user',
                  ),
                  hintText: l.text('اختيارية', 'Optional'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.text('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                action == 'approve'
                    ? l.text('اعتماد', 'Approve')
                    : l.text('رفض', 'Reject'),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
      if (!mounted) {
        return;
      }

      final security = await TransferSecurityService.confirmTransfer(
        context,
        allowOtpFallback: true,
      );
      if (!mounted || !security.isVerified) {
        return;
      }

      setState(() => _actingCardId = card['id']?.toString());
      await _api.reviewAdminPrepaidMultipayApproval(
        cardId: card['id']?.toString() ?? '',
        action: action,
        note: noteController.text,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
        localAuthMethod: security.method,
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
        title: l.text('تعذر تنفيذ المراجعة', 'Review failed'),
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
    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      return;
    }

    await _runAdminAction(
      card,
      title: action == 'freeze' ? 'تجميد البطاقة' : 'تفعيل البطاقة',
      action: () => _api.updateAdminPrepaidMultipayCardStatus(
        cardId: card['id']?.toString() ?? '',
        action: action,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
        localAuthMethod: security.method,
      ),
    );
  }

  Future<void> _adjustBalance(Map<String, dynamic> card) async {
    final l = context.loc;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l.text('تعديل رصيد البطاقة', 'Edit card balance')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: l.text('المبلغ', 'Amount'),
                  hintText: l.text(
                    'اكتب موجبًا للشحن أو سالبًا للخصم',
                    'Positive to add, negative to deduct',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l.text('ملاحظة', 'Note'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.text('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.text('حفظ', 'Save')),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      if (!mounted) {
        return;
      }
      final amount = double.tryParse(amountController.text.trim()) ?? 0;
      if (amount.abs() < 0.01) {
        await AppAlertService.showError(
          context,
          title: l.text('قيمة غير صالحة', 'Invalid amount'),
          message: l.text(
            'أدخل قيمة موجبة للإضافة أو سالبة للخصم.',
            'Enter a positive value to credit or a negative value to debit.',
          ),
        );
        return;
      }
      final security = await TransferSecurityService.confirmTransfer(
        context,
        allowOtpFallback: true,
      );
      if (!mounted || !security.isVerified) {
        return;
      }
      await _runAdminAction(
        card,
        title: l.text('تعديل رصيد البطاقة', 'Edit card balance'),
        action: () => _api.adjustAdminPrepaidMultipayCardBalance(
          cardId: card['id']?.toString() ?? '',
          amount: amount,
          note: noteController.text,
          otpCode: security.otpCode,
          securityPin: security.securityPin,
          localAuthMethod: security.method,
        ),
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _cancelCard(Map<String, dynamic> card) async {
    final l = context.loc;
    final noteController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l.text('إلغاء البطاقة', 'Cancel card')),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l.text('سبب الإلغاء', 'Cancellation reason'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.text('رجوع', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.text('تأكيد الإلغاء', 'Confirm cancellation')),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
      if (!mounted) {
        return;
      }
      final security = await TransferSecurityService.confirmTransfer(
        context,
        allowOtpFallback: true,
      );
      if (!mounted || !security.isVerified) {
        return;
      }
      await _runAdminAction(
        card,
        title: l.text('إلغاء البطاقة', 'Cancel card'),
        action: () => _api.cancelAdminPrepaidMultipayCard(
          cardId: card['id']?.toString() ?? '',
          note: noteController.text,
          otpCode: security.otpCode,
          securityPin: security.securityPin,
          localAuthMethod: security.method,
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
    final l = context.loc;
    try {
      setState(() => _actingCardId = card['id']?.toString());
      await action();
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.text('تم التنفيذ', 'Done'),
        message: title,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.text('تعذر التنفيذ', 'Operation failed'),
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
    final l = context.loc;
    final permissions = AppPermissions.fromUser(_user);
    final canManage = permissions.canManagePrepaidMultipayApprovals;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.text('إدارة البطاقات المسبقة', 'Manage prepaid cards')),
        actions: [
          if (permissions.canUsePrepaidMultipayCards)
            IconButton(
              onPressed: () => _openRoute('/prepaid-multipay-cards'),
              tooltip: l.text('إضافة بطاقة', 'Add card'),
              icon: const Icon(Icons.add_card_rounded),
            ),
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l.text('تحديث', 'Refresh'),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.text('إدارة البطاقات المسبقة', 'Manage prepaid cards'),
                  style: AppTheme.h2,
                ),
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
                else if (_loadError != null && _user == null)
                  AdminLoadErrorCard(message: _loadError!, onRetry: _load)
                else if (!canManage)
                  ShwakelCard(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'لا تملك صلاحية مراجعة بطاقات الدفع المسبق.',
                      style: AppTheme.bodyAction,
                    ),
                  )
                else ...[
                  if (_loadError != null) ...[
                    AdminLoadErrorCard(message: _loadError!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
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
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cards.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildApprovalCard(_cards[index]),
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
    final l = context.loc;
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
            decoration: InputDecoration(labelText: l.text('الحالة', 'Status')),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(l.text('كل البطاقات', 'All cards')),
              ),
              DropdownMenuItem(
                value: 'pending_approval',
                child: Text(l.text('معلقة', 'Pending')),
              ),
              DropdownMenuItem(
                value: 'active',
                child: Text(l.text('نشطة', 'Active')),
              ),
              DropdownMenuItem(
                value: 'frozen',
                child: Text(l.text('مجمدة', 'Frozen')),
              ),
              DropdownMenuItem(
                value: 'spent',
                child: Text(l.text('مستهلكة', 'Spent')),
              ),
              DropdownMenuItem(
                value: 'cancelled',
                child: Text(l.text('ملغاة', 'Cancelled')),
              ),
              DropdownMenuItem(
                value: 'rejected',
                child: Text(l.text('مرفوضة', 'Rejected')),
              ),
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
              labelText: l.text('بحث', 'Search'),
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
    final l = context.loc;
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
                  label: Text(l.text('اعتماد', 'Approve')),
                ),
                OutlinedButton.icon(
                  onPressed: acting ? null : () => _reviewCard(card, 'reject'),
                  icon: const Icon(Icons.cancel_rounded),
                  label: Text(l.text('رفض', 'Reject')),
                ),
              ],
              if ((card['status']?.toString() ?? '') == 'active')
                OutlinedButton.icon(
                  onPressed: acting
                      ? null
                      : () => _setCardStatus(card, 'freeze'),
                  icon: const Icon(Icons.pause_circle_rounded),
                  label: Text(l.text('تجميد', 'Freeze')),
                ),
              if ((card['status']?.toString() ?? '') == 'frozen')
                FilledButton.icon(
                  onPressed: acting
                      ? null
                      : () => _setCardStatus(card, 'activate'),
                  icon: const Icon(Icons.play_circle_rounded),
                  label: Text(l.text('تفعيل', 'Activate')),
                ),
              OutlinedButton.icon(
                onPressed: acting ? null : () => _adjustBalance(card),
                icon: const Icon(Icons.account_balance_wallet_rounded),
                label: Text(l.text('شحن/خصم', 'Credit/Debit')),
              ),
              if ([
                'pending_approval',
                'active',
                'frozen',
              ].contains(card['status']?.toString() ?? ''))
                OutlinedButton.icon(
                  onPressed: acting ? null : () => _cancelCard(card),
                  icon: const Icon(Icons.block_rounded),
                  label: Text(l.text('إلغاء', 'Cancel')),
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
