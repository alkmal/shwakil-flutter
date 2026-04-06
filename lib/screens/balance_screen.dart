import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> with RouteAware {
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _user;
  List<dynamic> _transactions = const [];
  bool _isLoading = true;
  _BalanceAuditFilter _auditFilter = _BalanceAuditFilter.all;
  int _page = 1;
  static const int _perPage = 8;
  int _lastPage = 1;
  bool _topupRequestEnabled = true;
  StreamSubscription<Map<String, dynamic>>? _balanceSubscription;
  bool _routeSubscribed = false;

  Map<String, dynamic> get _permissions =>
      Map<String, dynamic>.from(_user?['permissions'] as Map? ?? const {});

  bool get _canTransferAction => _permissions['canTransfer'] == true;
  bool get _canWithdrawAction => _permissions['canWithdraw'] == true;
  bool get _canManageUsersAction =>
      _permissions['canManageUsers'] == true || _user?['id']?.toString() == '1';
  bool get _canScanCardsAction => _permissions['canScanCards'] != false;
  bool get _isVerifiedAccount =>
      _user?['transferVerificationStatus']?.toString() == 'approved';

  @override
  void initState() {
    super.initState();
    _loadBalance();
    _balanceSubscription = RealtimeNotificationService.balanceUpdatesStream
        .listen((_) {
          if (mounted) _loadBalance();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPopNext() => _loadBalance();

  Future<void> _loadBalance() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getMyBalance(
        locationFilter: _apiLocationFilterValue,
        page: _page,
        perPage: _perPage,
        printingDebtOnly: _auditFilter == _BalanceAuditFilter.printingDebt,
      );
      final topupSettings = await _apiService.getTopupRequestSettings();
      final pagination = Map<String, dynamic>.from(
        data['pagination'] as Map? ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(
          data['user'] as Map? ?? <String, dynamic>{},
        );
        _transactions = List<dynamic>.from(
          data['transactions'] as List? ?? const [],
        );
        _topupRequestEnabled = topupSettings['enabled'] == true;
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'load_balance',
      );
    }
  }

  String get _apiLocationFilterValue {
    switch (_auditFilter) {
      case _BalanceAuditFilter.nearBranch:
        return 'near_branch';
      case _BalanceAuditFilter.outsideBranches:
        return 'outside_branches';
      case _BalanceAuditFilter.printingDebt:
      case _BalanceAuditFilter.all:
        return 'all';
    }
  }

  Future<void> _openTransferDialog() async {
    if (!_canTransferAction) {
      _showMessage(
        'هذه الخدمة غير متاحة لحسابك.',
        isError: true,
        operation: 'open_transfer_dialog',
      );
      return;
    }

    final result = await _showSearchableUserAmountDialog(
      title: 'تحويل رصيد',
      confirmLabel: 'تحويل الرصيد',
      notesLabel: 'ملاحظات التحويل',
      enablePhoneLookup: true,
    );
    if (result == null || !mounted) return;

    final securityResult = await TransferSecurityService.confirmTransfer(
      context,
    );
    if (!mounted || !securityResult.isVerified) return;

    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _apiService.transferBalance(
        recipientId: result.userId,
        amount: result.amount,
        notes: result.notes,
        otpCode: securityResult.otpCode,
        location: location,
      );
      await _loadBalance();
      if (!mounted) return;
      await _showTransferSuccessReport(response);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'wallet_transfer',
      );
    }
  }

  Future<void> _openWithdrawalDialog() async {
    if (!_canWithdrawAction || !_isVerifiedAccount) {
      _showMessage(
        'يجب توثيق الحساب قبل طلب السحب.',
        isError: true,
        operation: 'open_withdrawal_dialog',
      );
      return;
    }

    final result = await _showWithdrawalDialog();
    if (result == null || !mounted) return;

    final securityResult = await TransferSecurityService.confirmTransfer(
      context,
    );
    if (!mounted || !securityResult.isVerified) return;

    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _apiService.requestWithdrawal(
        amount: result.amount,
        destinationType: result.destinationType,
        destinationAccount: result.destinationAccount,
        accountHolderName: result.accountHolderName,
        bankName: result.bankName,
        notes: result.notes,
        agreementAccepted: true,
        location: location,
      );
      await _loadBalance();
      if (!mounted) return;
      _showMessage(
        response['message']?.toString() ??
            'تم تسجيل طلب السحب، وسيتم مراجعته خلال 24 ساعة.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'wallet_withdrawal',
      );
    }
  }

  Future<void> _openTopUpDialog() async {
    if (!_canManageUsersAction) {
      _showMessage(
        'شحن الأرصدة متاح للإدارة فقط.',
        isError: true,
        operation: 'open_topup_dialog',
      );
      return;
    }

    final result = await _showSearchableUserAmountDialog(
      title: 'شحن رصيد مستخدم',
      confirmLabel: 'إضافة الرصيد',
      notesLabel: 'سبب الشحن',
      amountHelperText: 'يُخصم 1% من قيمة الشحن كرسوم خدمة.',
    );
    if (result == null || !mounted) return;

    final securityResult = await TransferSecurityService.confirmTransfer(
      context,
    );
    if (!mounted || !securityResult.isVerified) return;

    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _apiService.topUpUser(
        userId: result.userId,
        amount: result.amount,
        notes: result.notes,
        otpCode: securityResult.otpCode,
        location: location,
      );
      await _loadBalance();
      if (!mounted) return;
      _showMessage(
        response['recipientNotified'] == true
            ? 'تم الشحن وإشعار المستخدم.'
            : 'تم الشحن وتعذر إرسال إشعار واتساب.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'wallet_topup',
      );
    }
  }

  Future<void> _openTopupRequestDialog() async {
    try {
      final options = await _apiService.getTopupRequestOptions();
      final topupRequest = Map<String, dynamic>.from(
        options['topupRequest'] as Map? ?? const {},
      );
      final methods = List<Map<String, dynamic>>.from(
        (options['methods'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      if (!mounted) {
        return;
      }
      if (topupRequest['enabled'] != true) {
        await AppAlertService.showInfo(
          context,
          title: 'الخدمة غير متاحة',
          message: 'طلبات شحن الرصيد متوقفة حاليًا. يمكنك التواصل مع الإدارة.',
        );
        return;
      }
      if (methods.isEmpty) {
        await AppAlertService.showInfo(
          context,
          title: 'لا توجد طرق دفع',
          message: 'لم تتم إضافة طرق شحن متاحة بعد من الإدارة.',
        );
        return;
      }

      final amountController = TextEditingController();
      final senderNameController = TextEditingController(
        text:
            _user?['fullName']?.toString() ??
            _user?['username']?.toString() ??
            '',
      );
      final senderPhoneController = TextEditingController(
        text: _user?['whatsapp']?.toString() ?? '',
      );
      final transferReferenceController = TextEditingController();
      final transferredAtController = TextEditingController();
      final notesController = TextEditingController();
      String? selectedMethodId = methods.first['id']?.toString();
      String? errorText;
      var isSubmitting = false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedMethod = methods.firstWhere(
              (item) => item['id']?.toString() == selectedMethodId,
              orElse: () => methods.first,
            );

            Future<void> submit() async {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0 || selectedMethodId == null) {
                setDialogState(
                  () =>
                      errorText = 'أدخل مبلغًا صحيحًا واختر طريقة شحن مناسبة.',
                );
                return;
              }
              setDialogState(() {
                isSubmitting = true;
                errorText = null;
              });
              try {
                final response = await _apiService.requestTopup(
                  amount: amount,
                  paymentMethodId: selectedMethodId!,
                  senderName: senderNameController.text,
                  senderPhone: senderPhoneController.text,
                  transferReference: transferReferenceController.text,
                  transferredAt: transferredAtController.text,
                  notes: notesController.text,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                if (!mounted) {
                  return;
                }
                await AppAlertService.showSuccess(
                  context,
                  title: 'تم إرسال الطلب',
                  message:
                      response['message']?.toString() ??
                      'تم تسجيل طلب شحن الرصيد وسيراجعه فريق الإدارة.',
                );
              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  isSubmitting = false;
                  errorText = ErrorMessageService.sanitize(error);
                });
              }
            }

            return AlertDialog(
              title: const Text('طلب شحن رصيد'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          topupRequest['instructions']?.toString() ??
                              'اختر طريقة الشحن المناسبة ثم أرسل بيانات الحوالة.',
                          style: AppTheme.bodyAction,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMethodId,
                        decoration: const InputDecoration(
                          labelText: 'طريقة الدفع',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_rounded,
                          ),
                        ),
                        items: methods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method['id']?.toString(),
                                child: Text(method['title']?.toString() ?? '-'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedMethodId = value),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedMethod['title']?.toString() ?? '-',
                              style: AppTheme.bodyBold,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'الرقم: ${selectedMethod['accountNumber']?.toString() ?? '-'}',
                              style: AppTheme.bodyAction,
                            ),
                            if ((selectedMethod['description']?.toString() ??
                                    '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                selectedMethod['description']?.toString() ?? '',
                                style: AppTheme.bodyAction.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'مبلغ الشحن',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: senderNameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المحول',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: senderPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'جوال المحول',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transferReferenceController,
                        decoration: const InputDecoration(
                          labelText: 'رقم العملية أو المرجع',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transferredAtController,
                        decoration: const InputDecoration(
                          labelText: 'وقت التحويل',
                          helperText: 'مثال: 2026-04-06 14:30',
                          prefixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات إضافية',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submit,
                  child: Text(isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطلب'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر فتح الخدمة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _showMessage(String text, {bool isError = false, String? operation}) {
    isError
        ? AppAlertService.showError(context, title: 'خطأ', message: text)
        : AppAlertService.showSuccess(context, title: 'نجاح', message: text);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('الرصيد والمعاملات')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadBalance,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 920;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroCard(isCompact: isCompact),
                    const SizedBox(height: 24),
                    if (isCompact) ...[
                      _buildActionsCard(isCompact: true),
                      const SizedBox(height: 16),
                      _buildPermissionSummaryCard(),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildActionsCard(isCompact: false),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: _buildPermissionSummaryCard(),
                          ),
                        ],
                      ),
                    const SizedBox(height: 36),
                    AdminSectionHeader(
                      title: 'آخر العمليات',
                      subtitle: 'آخر حركات حسابك.',
                      icon: Icons.history_rounded,
                      iconColor: AppTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    _buildAuditFilters(),
                    const SizedBox(height: 24),
                    if (_transactions.isEmpty)
                      _buildEmptyState()
                    else ...[
                      ..._transactions.map(
                        (tx) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AdminTransactionAuditCard(
                            transaction: Map<String, dynamic>.from(tx),
                          ),
                        ),
                      ),
                      AdminPaginationFooter(
                        currentPage: _page,
                        lastPage: _lastPage,
                        onPageChanged: (page) {
                          setState(() => _page = page);
                          _loadBalance();
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard({required bool isCompact}) {
    final balance = (_user?['balance'] as num?)?.toDouble() ?? 0;
    final printingDebtLimit =
        (_user?['printingDebtLimit'] as num?)?.toDouble() ?? 0;
    final availablePrinting =
        (_user?['availablePrintingBalance'] as num?)?.toDouble() ??
        (balance + printingDebtLimit);
    final debt =
        (_user?['outstandingDebt'] as num?)?.toDouble() ??
        (balance < 0 ? -balance : 0);
    final fullName =
        _user?['fullName']?.toString().trim() ??
        _user?['username']?.toString() ??
        '';

    return ShwakelCard(
      padding: const EdgeInsets.all(30),
      gradient: AppTheme.primaryGradient,
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShwakelLogo(size: 44, framed: true),
          const SizedBox(height: 20),
          Text(fullName, style: AppTheme.h2.copyWith(color: Colors.white)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _amountCol('الرصيد المتاح', balance, isCompact: isCompact),
              _amountCol('للطباعة', availablePrinting, isCompact: isCompact),
            ],
          ),
          if (printingDebtLimit > 0) ...[
            const SizedBox(height: 24),
            _debtBar(debt, printingDebtLimit),
          ],
        ],
      ),
    );
  }

  Widget _amountCol(String label, double amount, {required bool isCompact}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: isCompact ? 140 : 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.ils(amount),
            style: AppTheme.h1.copyWith(
              color: Colors.white,
              fontSize: isCompact ? 28 : 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _debtBar(double debt, double limit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerRight,
            widthFactor: (debt / limit).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'المستخدم من دين الطباعة: ${CurrencyFormatter.ils(debt)} / ${CurrencyFormatter.ils(limit)}',
          style: AppTheme.caption.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildActionsCard({required bool isCompact}) {
    final actionButtons = _buildActionButtons();

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الإجراءات المتاحة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            actionButtons.isEmpty
                ? 'لا توجد عمليات مالية متاحة لهذا الحساب حاليًا.'
                : 'تظهر لك فقط العمليات المسموح بها حسب صلاحيات حسابك.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          if (actionButtons.isEmpty)
            _buildLockedActionsHint()
          else if (isCompact)
            Column(
              children: actionButtons
                  .map(
                    (button) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: button,
                    ),
                  )
                  .toList(),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: actionButtons
                  .map((button) => SizedBox(width: 220, child: button))
                  .toList(),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildActionButtons() {
    final buttons = <Widget>[];

    if (_canManageUsersAction) {
      buttons.add(
        ShwakelButton(
          label: 'شحن رصيد مستخدم',
          icon: Icons.add_circle_outline_rounded,
          onPressed: _openTopUpDialog,
        ),
      );
    }
    if (_canTransferAction) {
      buttons.add(
        ShwakelButton(
          label: 'تحويل رصيد',
          icon: Icons.send_rounded,
          isSecondary: buttons.isNotEmpty,
          onPressed: _openTransferDialog,
        ),
      );
    }
    if (_topupRequestEnabled) {
      buttons.add(
        ShwakelButton(
          label: 'طلب شحن رصيد',
          icon: Icons.add_card_rounded,
          isSecondary: buttons.isNotEmpty,
          onPressed: _openTopupRequestDialog,
        ),
      );
    }
    if (_canWithdrawAction && _isVerifiedAccount) {
      buttons.add(
        ShwakelButton(
          label: 'طلب سحب',
          icon: Icons.outbox_rounded,
          isSecondary: true,
          onPressed: _openWithdrawalDialog,
        ),
      );
    }

    return buttons;
  }

  Widget _buildLockedActionsHint() {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      color: AppTheme.warning.withValues(alpha: 0.08),
      borderColor: AppTheme.warning.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: AppTheme.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isVerifiedAccount
                  ? 'لا توجد إجراءات إضافية متاحة لهذا الحساب.'
                  : 'بعض العمليات مثل التحويل والسحب تتطلب توثيق الحساب أولًا.',
              style: AppTheme.bodyText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSummaryCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      color: AppTheme.primary.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حالة الحساب',
            style: AppTheme.h3.copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          _permissionRow('نوع الحساب', _user?['roleLabel']?.toString() ?? '-'),
          _permissionRow('التوثيق', _isVerifiedAccount ? 'موثق' : 'غير موثق'),
          _permissionRow('التحويل', _canTransferAction ? 'متاح' : 'غير متاح'),
          _permissionRow(
            'السحب',
            (_canWithdrawAction && _isVerifiedAccount) ? 'متاح' : 'غير متاح',
          ),
          if (_canManageUsersAction) _permissionRow('شحن المستخدمين', 'متاح'),
          _permissionRow(
            'فحص البطاقات',
            _canScanCardsAction ? 'متاح' : 'غير متاح',
          ),
        ],
      ),
    );
  }

  Widget _permissionRow(String label, String value) {
    final isAvailable = value == 'متاح' || value == 'موثق';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.bodyText)),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTheme.bodyBold.copyWith(
              color: isAvailable ? AppTheme.success : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _filterChip('الكل', _BalanceAuditFilter.all),
        _filterChip('قرب فرع', _BalanceAuditFilter.nearBranch),
        _filterChip('خارج الفروع', _BalanceAuditFilter.outsideBranches),
        if (((_user?['printingDebtLimit'] as num?)?.toDouble() ?? 0) > 0)
          _filterChip('دين الطباعة', _BalanceAuditFilter.printingDebt),
      ],
    );
  }

  Widget _filterChip(String label, _BalanceAuditFilter filter) {
    final selected = _auditFilter == filter;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) {
        setState(() {
          _auditFilter = filter;
          _page = 1;
        });
        _loadBalance();
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.1),
      labelStyle: AppTheme.caption.copyWith(
        color: selected ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(44),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 14),
            Text('لا توجد معاملات حتى الآن', style: AppTheme.h3),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferSuccessReport(Map<String, dynamic> response) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم التحويل بنجاح'),
        content: const Text('تم إرسال الرصيد بنجاح.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<_UserAmountResult?> _showSearchableUserAmountDialog({
    required String title,
    required String confirmLabel,
    required String notesLabel,
    String? amountHelperText,
    bool enablePhoneLookup = false,
  }) async {
    final queryController = TextEditingController();
    final phoneController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    List<Map<String, dynamic>> searchResults = const [];
    Map<String, dynamic>? selectedUser;
    bool isSearching = false;
    bool isLookingUpPhone = false;
    String? searchError;
    String? phoneLookupMessage;
    String countryCode = PhoneNumberService.countries.first.dialCode;

    Future<void> performSearch(StateSetter setDialogState) async {
      final query = queryController.text.trim();
      if (query.isEmpty) {
        setDialogState(() {
          searchResults = const [];
          selectedUser = null;
          searchError = 'أدخل اسم المستخدم أو رقم واتساب للبحث.';
        });
        return;
      }

      setDialogState(() {
        isSearching = true;
        searchError = null;
      });

      try {
        final results = await _apiService.searchUsers(query);
        if (!mounted) return;
        setDialogState(() {
          searchResults = results;
          selectedUser = results.length == 1 ? results.first : null;
          isSearching = false;
          searchError = results.isEmpty
              ? 'لم يتم العثور على مستخدم مطابق.'
              : null;
        });
      } catch (error) {
        if (!mounted) return;
        setDialogState(() {
          isSearching = false;
          searchError = ErrorMessageService.sanitize(error);
        });
      }
    }

    Future<void> performPhoneLookup(StateSetter setDialogState) async {
      final phone = phoneController.text.trim();
      if (phone.isEmpty) {
        setDialogState(() => phoneLookupMessage = 'أدخل رقم الجوال أولًا.');
        return;
      }

      setDialogState(() {
        isLookingUpPhone = true;
        phoneLookupMessage = null;
      });

      try {
        final response = await _apiService.lookupUserByPhone(
          phone: phone,
          countryCode: countryCode,
        );
        if (!mounted) return;
        final user = response['user'] is Map
            ? Map<String, dynamic>.from(response['user'] as Map)
            : null;
        setDialogState(() {
          isLookingUpPhone = false;
          if (response['exists'] == true && user != null) {
            selectedUser = user;
            searchResults = [user];
            phoneLookupMessage = 'الرقم موجود ويمكن متابعة التحويل.';
          } else {
            selectedUser = null;
            phoneLookupMessage =
                response['message']?.toString() ?? 'الرقم غير موجود.';
          }
        });
      } catch (error) {
        if (!mounted) return;
        setDialogState(() {
          isLookingUpPhone = false;
          phoneLookupMessage = ErrorMessageService.sanitize(error);
        });
      }
    }

    return showDialog<_UserAmountResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enablePhoneLookup
                        ? 'أدخل رقم الجوال ثم افحصه للعثور على المستلم قبل تنفيذ التحويل.'
                        : 'ابحث عن المستخدم ثم أدخل مبلغ العملية.',
                    style: AppTheme.bodyAction,
                  ),
                  if (!enablePhoneLookup) ...[
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 360;
                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: queryController,
                                decoration: const InputDecoration(
                                  labelText: 'اسم المستخدم أو رقم واتساب',
                                ),
                                onSubmitted: (_) =>
                                    performSearch(setDialogState),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: isSearching
                                    ? null
                                    : () => performSearch(setDialogState),
                                icon: const Icon(Icons.search_rounded),
                                label: Text(
                                  isSearching ? 'جارٍ البحث...' : 'بحث',
                                ),
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: queryController,
                                decoration: const InputDecoration(
                                  labelText: 'اسم المستخدم أو رقم واتساب',
                                ),
                                onSubmitted: (_) =>
                                    performSearch(setDialogState),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: isSearching
                                  ? null
                                  : () => performSearch(setDialogState),
                              icon: isSearching
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search_rounded),
                              label: const Text('بحث'),
                            ),
                          ],
                        );
                      },
                    ),
                    if (searchError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        searchError!,
                        style: AppTheme.caption.copyWith(color: AppTheme.error),
                      ),
                    ],
                  ],
                  if (enablePhoneLookup) ...[
                    const SizedBox(height: 16),
                    Text('البحث برقم الجوال', style: AppTheme.bodyBold),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 360;
                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: countryCode,
                                decoration: const InputDecoration(
                                  labelText: 'رمز الدولة',
                                ),
                                items: PhoneNumberService.countries
                                    .map(
                                      (country) => DropdownMenuItem(
                                        value: country.dialCode,
                                        child: Text(
                                          '${country.name} (+${country.dialCode})',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => countryCode = value);
                                },
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'رقم الجوال',
                                  prefixIcon: Icon(Icons.phone_rounded),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: isLookingUpPhone
                                    ? null
                                    : () => performPhoneLookup(setDialogState),
                                icon: const Icon(Icons.verified_user_outlined),
                                label: Text(
                                  isLookingUpPhone
                                      ? 'جارٍ الفحص...'
                                      : 'فحص الرقم',
                                ),
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            SizedBox(
                              width: 150,
                              child: DropdownButtonFormField<String>(
                                initialValue: countryCode,
                                decoration: const InputDecoration(
                                  labelText: 'رمز الدولة',
                                ),
                                items: PhoneNumberService.countries
                                    .map(
                                      (country) => DropdownMenuItem(
                                        value: country.dialCode,
                                        child: Text('+${country.dialCode}'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() => countryCode = value);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'رقم الجوال',
                                  prefixIcon: Icon(Icons.phone_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: isLookingUpPhone
                                  ? null
                                  : () => performPhoneLookup(setDialogState),
                              child: Text(
                                isLookingUpPhone ? 'جارٍ الفحص...' : 'فحص',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    if (phoneLookupMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        phoneLookupMessage!,
                        style: AppTheme.caption.copyWith(
                          color: selectedUser != null
                              ? AppTheme.success
                              : AppTheme.error,
                        ),
                      ),
                    ],
                  ],
                  if (searchResults.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = searchResults[index];
                          final isSelected =
                              selectedUser?['id']?.toString() ==
                              item['id']?.toString();
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            selected: isSelected,
                            leading: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.person_outline_rounded,
                              color: isSelected
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                            ),
                            title: Text(item['username']?.toString() ?? '-'),
                            subtitle: Text(
                              enablePhoneLookup
                                  ? 'رقم المستخدم: ${item['id']}'
                                  : 'رقم المستخدم: ${item['id']} | الرصيد: ${CurrencyFormatter.ils((item['balance'] as num?)?.toDouble() ?? 0)}',
                            ),
                            onTap: () =>
                                setDialogState(() => selectedUser = item),
                          );
                        },
                      ),
                    ),
                  ],
                  if (selectedUser != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المستخدم المحدد',
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedUser!['username']?.toString() ?? '-',
                            style: AppTheme.bodyBold.copyWith(
                              color: AppTheme.primary,
                            ),
                          ),
                          if (enablePhoneLookup) ...[
                            const SizedBox(height: 4),
                            Text(
                              'تم إخفاء الرصيد حفاظًا على خصوصية المستخدم.',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                          if ((selectedUser!['whatsapp']?.toString() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              selectedUser!['whatsapp']?.toString() ?? '',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'المبلغ',
                      helperText: amountHelperText,
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: notesLabel,
                      prefixIcon: const Icon(Icons.notes_rounded),
                    ),
                    minLines: 2,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedUser == null) {
                  setDialogState(
                    () => searchError = enablePhoneLookup
                        ? 'افحص رقم الجوال أولًا لاختيار المستلم.'
                        : 'اختر مستخدمًا من النتائج أولًا.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _UserAmountResult(
                    userId: selectedUser!['id'].toString(),
                    amount: double.tryParse(amountController.text) ?? 0,
                    notes: notesController.text.trim(),
                  ),
                );
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<_WithdrawalRequestResult?> _showWithdrawalDialog() async {
    final amountController = TextEditingController();
    final accountController = TextEditingController();
    final fullName = (_user?['fullName']?.toString() ?? '').trim();
    final username = (_user?['username']?.toString() ?? '').trim();
    final accountHolderController = TextEditingController(
      text: fullName.isNotEmpty ? fullName : username,
    );
    final bankController = TextEditingController();
    final notesController = TextEditingController();
    String destinationType = 'wallet';
    String? formError;

    return showDialog<_WithdrawalRequestResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isBankTransfer = destinationType == 'bank';
          final accountLabel = isBankTransfer
              ? 'رقم الحساب أو الآيبان'
              : 'رقم المحفظة أو الحساب';

          return AlertDialog(
            title: const Text('طلب سحب الرصيد'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أدخل بيانات الجهة التي تريد استلام السحب عليها.',
                      style: AppTheme.bodyAction,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: destinationType,
                      decoration: const InputDecoration(
                        labelText: 'جهة السحب',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'wallet', child: Text('محفظة')),
                        DropdownMenuItem(
                          value: 'bank',
                          child: Text('حساب بنكي'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => destinationType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        helperText: 'الحد الأدنى للسحب 100 ₪',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountController,
                      decoration: InputDecoration(
                        labelText: accountLabel,
                        prefixIcon: const Icon(Icons.numbers_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountHolderController,
                      decoration: const InputDecoration(
                        labelText: 'اسم صاحب الحساب',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    if (isBankTransfer) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: bankController,
                        decoration: const InputDecoration(
                          labelText: 'اسم البنك',
                          prefixIcon: Icon(Icons.account_balance_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات إضافية',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      minLines: 2,
                      maxLines: 3,
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        formError!,
                        style: AppTheme.caption.copyWith(color: AppTheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) {
                    setDialogState(() => formError = 'أدخل مبلغًا صحيحًا.');
                    return;
                  }
                  if (accountController.text.trim().isEmpty ||
                      accountHolderController.text.trim().isEmpty) {
                    setDialogState(() {
                      formError = 'رقم الحساب واسم صاحب الحساب مطلوبان.';
                    });
                    return;
                  }
                  if (isBankTransfer && bankController.text.trim().isEmpty) {
                    setDialogState(() => formError = 'أدخل اسم البنك.');
                    return;
                  }

                  Navigator.pop(
                    context,
                    _WithdrawalRequestResult(
                      amount: amount,
                      destinationType: destinationType,
                      destinationAccount: accountController.text.trim(),
                      accountHolderName: accountHolderController.text.trim(),
                      bankName: bankController.text.trim(),
                      notes: notesController.text.trim(),
                    ),
                  );
                },
                child: const Text('إرسال الطلب'),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _BalanceAuditFilter { all, nearBranch, outsideBranches, printingDebt }

class _UserAmountResult {
  const _UserAmountResult({
    required this.userId,
    required this.amount,
    required this.notes,
  });

  final String userId;
  final double amount;
  final String notes;
}

class _WithdrawalRequestResult {
  const _WithdrawalRequestResult({
    required this.amount,
    required this.destinationType,
    required this.destinationAccount,
    required this.accountHolderName,
    required this.bankName,
    required this.notes,
  });

  final double amount;
  final String destinationType;
  final String destinationAccount;
  final String accountHolderName;
  final String bankName;
  final String notes;
}
