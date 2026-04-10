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
  bool get _canScanCardsAction =>
      _permissions['canScanCards'] != false ||
      _permissions['canOfflineCardScan'] == true;
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
    final l = context.loc;
    if (!_canTransferAction) {
      _showMessage(
        l.tr('screens_balance_screen.002'),
        isError: true,
        operation: 'open_transfer_dialog',
      );
      return;
    }

    final result = await _showSearchableUserAmountDialog(
      title: l.tr('screens_balance_screen.003'),
      confirmLabel: l.tr('screens_balance_screen.004'),
      notesLabel: l.tr('screens_balance_screen.005'),
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
        fallbackTitle: l.tr('screens_balance_screen.006'),
      );
    }
  }

  Future<void> _openWithdrawalDialog() async {
    final l = context.loc;
    if (!_canWithdrawAction || !_isVerifiedAccount) {
      _showMessage(
        l.tr('screens_balance_screen.007'),
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
        response['message']?.toString() ?? l.tr('screens_balance_screen.008'),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'wallet_withdrawal',
        fallbackTitle: l.tr('screens_balance_screen.009'),
      );
    }
  }

  Future<void> _openTopUpDialog() async {
    final l = context.loc;
    if (!_canManageUsersAction) {
      _showMessage(
        l.tr('screens_balance_screen.010'),
        isError: true,
        operation: 'open_topup_dialog',
      );
      return;
    }

    final result = await _showSearchableUserAmountDialog(
      title: l.tr('screens_balance_screen.011'),
      confirmLabel: l.tr('screens_balance_screen.012'),
      notesLabel: l.tr('screens_balance_screen.013'),
      amountHelperText: l.tr('screens_balance_screen.014'),
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
            ? l.tr('screens_balance_screen.015')
            : l.tr('screens_balance_screen.016'),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        operation: 'wallet_topup',
        fallbackTitle: l.tr('screens_balance_screen.017'),
      );
    }
  }

  Future<void> _openTopupRequestDialog() async {
    final l = context.loc;
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
          title: l.tr('screens_balance_screen.052'),
          message: l.tr('screens_balance_screen.053'),
        );
        return;
      }
      if (methods.isEmpty) {
        await AppAlertService.showInfo(
          context,
          title: l.tr('screens_balance_screen.054'),
          message: l.tr('screens_balance_screen.055'),
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
                  () => errorText = l.tr('screens_balance_screen.056'),
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
                  title: l.tr('screens_balance_screen.057'),
                  message:
                      response['message']?.toString() ??
                      l.tr('screens_balance_screen.058'),
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
              title: Text(l.tr('screens_balance_screen.029')),
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
                              l.tr('screens_balance_screen.059'),
                          style: AppTheme.bodyAction,
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMethodId,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.060'),
                          prefixIcon: const Icon(
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
                              l.tr(
                                'screens_balance_screen.061',
                                params: {
                                  'number':
                                      selectedMethod['accountNumber']
                                          ?.toString() ??
                                      '-',
                                },
                              ),
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
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.062'),
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: senderNameController,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.063'),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: senderPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.064'),
                          prefixIcon: const Icon(Icons.phone_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transferReferenceController,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.065'),
                          prefixIcon: const Icon(Icons.tag_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: transferredAtController,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.066'),
                          helperText: l.tr('screens_balance_screen.067'),
                          prefixIcon: const Icon(Icons.schedule_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.068'),
                          prefixIcon: const Icon(Icons.notes_rounded),
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
                  child: Text(l.tr('screens_balance_screen.069')),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submit,
                  child: Text(
                    isSubmitting
                        ? l.tr('screens_balance_screen.070')
                        : l.tr('screens_balance_screen.071'),
                  ),
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
        title: l.tr('screens_balance_screen.072'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _showMessage(
    String text, {
    bool isError = false,
    String? operation,
    String? fallbackTitle,
  }) {
    final l = context.loc;
    final title =
        fallbackTitle ??
        (isError
            ? l.tr('screens_balance_screen.018')
            : l.tr('screens_balance_screen.019'));
    isError || operation != null
        ? AppAlertService.showError(context, title: title, message: text)
        : AppAlertService.showSuccess(context, title: title, message: text);
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
      appBar: AppBar(title: Text(context.loc.tr('screens_balance_screen.020'))),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadBalance,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 920;
                final isPhone = constraints.maxWidth < 640;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopSection(isCompact: isCompact, isPhone: isPhone),
                    const SizedBox(height: 24),
                    _buildHistorySection(isCompact: isCompact),
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
                    if (isCompact) ...[
                      const SizedBox(height: 24),
                      _buildPermissionSummaryCard(compact: true),
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

  Widget _buildTopSection({required bool isCompact, required bool isPhone}) {
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(isCompact: true),
          const SizedBox(height: 16),
          _buildActionsCard(isCompact: true, isPhone: isPhone),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildHeroCard(isCompact: false),
              const SizedBox(height: 18),
              _buildActionsCard(isCompact: false, isPhone: false),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _buildPermissionSummaryCard(compact: false)),
      ],
    );
  }

  Widget _buildHistorySection({required bool isCompact}) {
    final l = context.loc;
    return ShwakelCard(
      padding: EdgeInsets.all(isCompact ? 18 : 24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_balance_screen.021'),
            subtitle: l.tr('screens_balance_screen.022'),
            icon: Icons.history_rounded,
            iconColor: AppTheme.primary,
          ),
          const SizedBox(height: 16),
          _buildAuditFilters(compact: isCompact),
        ],
      ),
    );
  }

  Widget _buildHeroCard({required bool isCompact}) {
    final l = context.loc;
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
      padding: EdgeInsets.all(isCompact ? 22 : 30),
      gradient: AppTheme.primaryGradient,
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: AppTheme.h2.copyWith(
                        color: Colors.white,
                        fontSize: isCompact ? 20 : 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.tr('screens_balance_screen.020'),
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const ShwakelLogo(size: 44, framed: true),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isCompact ? 16 : 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              children: [
                _amountCol(
                  l.tr('screens_balance_screen.023'),
                  balance,
                  isCompact: isCompact,
                ),
                _amountCol(
                  l.tr('screens_balance_screen.024'),
                  availablePrinting,
                  isCompact: isCompact,
                ),
              ],
            ),
          ),
          if (printingDebtLimit > 0) ...[
            const SizedBox(height: 18),
            _debtBar(debt, printingDebtLimit),
          ],
        ],
      ),
    );
  }

  Widget _amountCol(String label, double amount, {required bool isCompact}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: isCompact ? 132 : 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.ils(amount),
            style: AppTheme.h1.copyWith(
              color: Colors.white,
              fontSize: isCompact ? 24 : 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _debtBar(double debt, double limit) {
    final l = context.loc;
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
          l.tr(
            'screens_balance_screen.025',
            params: {
              'debt': CurrencyFormatter.ils(debt),
              'limit': CurrencyFormatter.ils(limit),
            },
          ),
          style: AppTheme.caption.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildActionsCard({required bool isCompact, required bool isPhone}) {
    final l = context.loc;
    final actionButtons = _buildActionButtons();

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.tr('screens_balance_screen.026'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            actionButtons.isEmpty
                ? l.tr('screens_balance_screen.027')
                : l.tr('screens_balance_screen.028'),
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          if (actionButtons.isEmpty)
            _buildLockedActionsHint()
          else if (isCompact)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: actionButtons
                  .map(
                    (button) => SizedBox(
                      width: isPhone ? double.infinity : 220,
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
    final l = context.loc;
    final buttons = <Widget>[];

    if (_canManageUsersAction) {
      buttons.add(
        ShwakelButton(
          label: l.tr('screens_balance_screen.011'),
          icon: Icons.add_circle_outline_rounded,
          onPressed: _openTopUpDialog,
        ),
      );
    }
    if (_canTransferAction) {
      buttons.add(
        ShwakelButton(
          label: l.tr('screens_balance_screen.003'),
          icon: Icons.send_rounded,
          isSecondary: buttons.isNotEmpty,
          onPressed: _openTransferDialog,
        ),
      );
    }
    if (_topupRequestEnabled) {
      buttons.add(
        ShwakelButton(
          label: l.tr('screens_balance_screen.029'),
          icon: Icons.add_card_rounded,
          isSecondary: buttons.isNotEmpty,
          onPressed: _openTopupRequestDialog,
        ),
      );
    }
    if (_canWithdrawAction && _isVerifiedAccount) {
      buttons.add(
        ShwakelButton(
          label: l.tr('screens_balance_screen.030'),
          icon: Icons.outbox_rounded,
          isSecondary: true,
          onPressed: _openWithdrawalDialog,
        ),
      );
    }

    return buttons;
  }

  Widget _buildLockedActionsHint() {
    final l = context.loc;
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
                  ? l.tr('screens_balance_screen.031')
                  : l.tr('screens_balance_screen.032'),
              style: AppTheme.bodyText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSummaryCard({required bool compact}) {
    final l = context.loc;
    return ShwakelCard(
      padding: EdgeInsets.all(compact ? 20 : 24),
      color: AppTheme.primary.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.tr('screens_balance_screen.033'),
            style: AppTheme.h3.copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          _permissionRow(
            l.tr('screens_balance_screen.034'),
            _user?['roleLabel']?.toString() ?? '-',
          ),
          _permissionRow(
            l.tr('screens_balance_screen.035'),
            _isVerifiedAccount
                ? l.tr('screens_balance_screen.036')
                : l.tr('screens_balance_screen.037'),
          ),
          _permissionRow(
            l.tr('screens_balance_screen.038'),
            _canTransferAction
                ? l.tr('screens_balance_screen.039')
                : l.tr('screens_balance_screen.040'),
          ),
          _permissionRow(
            l.tr('screens_balance_screen.041'),
            (_canWithdrawAction && _isVerifiedAccount)
                ? l.tr('screens_balance_screen.039')
                : l.tr('screens_balance_screen.040'),
          ),
          if (_canManageUsersAction)
            _permissionRow(
              l.tr('screens_balance_screen.042'),
              l.tr('screens_balance_screen.039'),
            ),
          _permissionRow(
            l.tr('screens_balance_screen.043'),
            _canScanCardsAction
                ? l.tr('screens_balance_screen.039')
                : l.tr('screens_balance_screen.040'),
          ),
        ],
      ),
    );
  }

  Widget _permissionRow(String label, String value) {
    final l = context.loc;
    final isAvailable =
        value == l.tr('screens_balance_screen.039') ||
        value == l.tr('screens_balance_screen.036');
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

  Widget _buildAuditFilters({required bool compact}) {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.tr('screens_balance_screen.026'),
          style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(
              l.tr('screens_balance_screen.044'),
              _BalanceAuditFilter.all,
              compact: compact,
            ),
            _filterChip(
              l.tr('screens_balance_screen.045'),
              _BalanceAuditFilter.nearBranch,
              compact: compact,
            ),
            _filterChip(
              l.tr('screens_balance_screen.046'),
              _BalanceAuditFilter.outsideBranches,
              compact: compact,
            ),
            if (((_user?['printingDebtLimit'] as num?)?.toDouble() ?? 0) > 0)
              _filterChip(
                l.tr('screens_balance_screen.047'),
                _BalanceAuditFilter.printingDebt,
                compact: compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(
    String label,
    _BalanceAuditFilter filter, {
    required bool compact,
  }) {
    final selected = _auditFilter == filter;
    return ChoiceChip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
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
    final l = context.loc;
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
            Text(l.tr('screens_balance_screen.048'), style: AppTheme.h3),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferSuccessReport(Map<String, dynamic> response) async {
    final l = context.loc;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('screens_balance_screen.049')),
        content: Text(l.tr('screens_balance_screen.050')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.tr('screens_balance_screen.051')),
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
    final l = context.loc;
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
          searchError = l.tr('screens_balance_screen.073');
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
              ? l.tr('screens_balance_screen.074')
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
        setDialogState(() {
          phoneLookupMessage = l.tr('screens_balance_screen.075');
        });
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
            phoneLookupMessage = l.tr('screens_balance_screen.076');
          } else {
            selectedUser = null;
            phoneLookupMessage =
                response['message']?.toString() ??
                l.tr('screens_balance_screen.077');
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
                        ? l.tr('screens_balance_screen.078')
                        : l.tr('screens_balance_screen.079'),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.080'),
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
                                  isSearching
                                      ? l.tr('screens_balance_screen.081')
                                      : l.tr('screens_balance_screen.082'),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.080'),
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
                              label: Text(l.tr('screens_balance_screen.082')),
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
                    Text(
                      l.tr('screens_balance_screen.083'),
                      style: AppTheme.bodyBold,
                    ),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.084'),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.085'),
                                  prefixIcon: const Icon(Icons.phone_rounded),
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
                                      ? l.tr('screens_balance_screen.086')
                                      : l.tr('screens_balance_screen.087'),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.084'),
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
                                decoration: InputDecoration(
                                  labelText: l.tr('screens_balance_screen.085'),
                                  prefixIcon: const Icon(Icons.phone_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: isLookingUpPhone
                                  ? null
                                  : () => performPhoneLookup(setDialogState),
                              child: Text(
                                isLookingUpPhone
                                    ? l.tr('screens_balance_screen.086')
                                    : l.tr('screens_balance_screen.088'),
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
                                  ? l.tr(
                                      'screens_balance_screen.089',
                                      params: {'id': '${item['id']}'},
                                    )
                                  : l.tr(
                                      'screens_balance_screen.090',
                                      params: {
                                        'id': '${item['id']}',
                                        'balance': CurrencyFormatter.ils(
                                          (item['balance'] as num?)
                                                  ?.toDouble() ??
                                              0,
                                        ),
                                      },
                                    ),
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
                            l.tr('screens_balance_screen.091'),
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
                              l.tr('screens_balance_screen.092'),
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
                      labelText: l.tr('screens_balance_screen.093'),
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
                  if (searchError != null && enablePhoneLookup) ...[
                    const SizedBox(height: 8),
                    Text(
                      searchError!,
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
              child: Text(l.tr('screens_balance_screen.069')),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedUser == null) {
                  setDialogState(
                    () => searchError = enablePhoneLookup
                        ? l.tr('screens_balance_screen.094')
                        : l.tr('screens_balance_screen.095'),
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
    final l = context.loc;
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
              ? l.tr('screens_balance_screen.096')
              : l.tr('screens_balance_screen.097');

          return AlertDialog(
            title: Text(l.tr('screens_balance_screen.030')),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_balance_screen.098'),
                      style: AppTheme.bodyAction,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: destinationType,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_balance_screen.099'),
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'wallet',
                          child: Text(l.tr('screens_balance_screen.100')),
                        ),
                        DropdownMenuItem(
                          value: 'bank',
                          child: Text(l.tr('screens_balance_screen.101')),
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
                      decoration: InputDecoration(
                        labelText: l.tr('screens_balance_screen.093'),
                        helperText: l.tr('screens_balance_screen.102'),
                        prefixIcon: const Icon(Icons.payments_outlined),
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
                      decoration: InputDecoration(
                        labelText: l.tr('screens_balance_screen.103'),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    if (isBankTransfer) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: bankController,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_balance_screen.104'),
                          prefixIcon: const Icon(Icons.account_balance_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_balance_screen.068'),
                        prefixIcon: const Icon(Icons.notes_rounded),
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
                child: Text(l.tr('screens_balance_screen.069')),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) {
                    setDialogState(() {
                      formError = l.tr('screens_balance_screen.105');
                    });
                    return;
                  }
                  if (accountController.text.trim().isEmpty ||
                      accountHolderController.text.trim().isEmpty) {
                    setDialogState(() {
                      formError = l.tr('screens_balance_screen.106');
                    });
                    return;
                  }
                  if (isBankTransfer && bankController.text.trim().isEmpty) {
                    setDialogState(() {
                      formError = l.tr('screens_balance_screen.107');
                    });
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
                child: Text(l.tr('screens_balance_screen.071')),
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
