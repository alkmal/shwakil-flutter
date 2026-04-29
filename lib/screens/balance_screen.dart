import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen>
    with RouteAware, SingleTickerProviderStateMixin {
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
  bool _showHistoryFilters = false;
  late final TabController _tabController;

  AppPermissions get _appPermissions => AppPermissions.fromUser(_user);

  bool get _canTransferAction => _appPermissions.canTransfer;
  bool get _canWithdrawAction => _appPermissions.canWithdraw;
  bool get _canManageUsersAction =>
      _appPermissions.canManageUsers || _appPermissions.canFinanceTopup;
  bool get _canOpenBalanceWorkspace =>
      _appPermissions.canAccessRegulatedWalletFeatures;
  bool get _isVerifiedAccount =>
      _user?['transferVerificationStatus']?.toString() == 'approved';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
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
    _tabController.dispose();
    _balanceSubscription?.cancel();
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPopNext() => _loadBalance();

  Future<void> _loadBalance() async {
    final cachedUser = await AuthService().currentUser();
    final cachedPermissions = AppPermissions.fromUser(cachedUser);
    if (!cachedPermissions.canAccessRegulatedWalletFeatures) {
      if (!mounted) {
        return;
      }
      setState(() {
        _user = cachedUser;
        _transactions = const [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    final requestedPage = _page;
    try {
      final results = await Future.wait<dynamic>([
        _apiService.getMyBalance(
          locationFilter: _apiLocationFilterValue,
          page: requestedPage,
          perPage: _perPage,
          printingDebtOnly: _auditFilter == _BalanceAuditFilter.printingDebt,
        ),
        _apiService.getTopupRequestSettings(),
      ]);
      final data = Map<String, dynamic>.from(results[0] as Map);
      final topupSettings = Map<String, dynamic>.from(results[1] as Map);
      final pagination = Map<String, dynamic>.from(
        data['pagination'] as Map? ?? const {},
      );
      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage);
      if (requestedPage > lastPage && lastPage > 0) {
        if (!mounted) return;
        setState(() => _page = lastPage);
        await _loadBalance();
        return;
      }
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(
          data['user'] as Map? ?? <String, dynamic>{},
        );
        _transactions = List<dynamic>.from(
          data['transactions'] as List? ?? const [],
        );
        _topupRequestEnabled = topupSettings['enabled'] == true;
        _page = normalizedPage;
        _lastPage = lastPage;
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
        localAuthMethod: securityResult.method,
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
        localAuthMethod: securityResult.method,
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
      var selectedTransferredAt = DateTime.now();
      final transferredAtController = TextEditingController(
        text: _formatTopupRequestDateTime(selectedTransferredAt),
      );
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

            Future<void> pickTransferDate() async {
              final pickedDate = await showDatePicker(
                context: dialogContext,
                initialDate: selectedTransferredAt,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (pickedDate == null) {
                return;
              }
              final merged = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                selectedTransferredAt.hour,
                selectedTransferredAt.minute,
              );
              setDialogState(() {
                selectedTransferredAt = merged;
                transferredAtController.text = _formatTopupRequestDateTime(
                  merged,
                );
              });
            }

            Future<void> pickTransferTime() async {
              final pickedTime = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay.fromDateTime(selectedTransferredAt),
              );
              if (pickedTime == null) {
                return;
              }
              final merged = DateTime(
                selectedTransferredAt.year,
                selectedTransferredAt.month,
                selectedTransferredAt.day,
                pickedTime.hour,
                pickedTime.minute,
              );
              setDialogState(() {
                selectedTransferredAt = merged;
                transferredAtController.text = _formatTopupRequestDateTime(
                  merged,
                );
              });
            }

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
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShwakelCard(
                        padding: const EdgeInsets.all(18),
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(24),
                        shadowLevel: ShwakelShadowLevel.none,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.add_card_rounded,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.tr('screens_balance_screen.029'),
                                    style: AppTheme.h3,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    topupRequest['instructions']?.toString() ??
                                        l.tr('screens_balance_screen.059'),
                                    style: AppTheme.bodyAction.copyWith(
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildTopupRequestInfoCard(
                        icon: Icons.verified_user_outlined,
                        message: l.tr('screens_balance_screen.124'),
                      ),
                      const SizedBox(height: 12),
                      _buildTopupRequestInfoCard(
                        icon: Icons.hourglass_top_rounded,
                        message: l.tr('screens_balance_screen.125'),
                      ),
                      const SizedBox(height: 18),
                      ShwakelCard(
                        padding: const EdgeInsets.all(18),
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(24),
                        shadowLevel: ShwakelShadowLevel.none,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('screens_balance_screen.071'),
                              style: AppTheme.bodyBold,
                            ),
                            const SizedBox(height: 12),
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
                                      child: Text(
                                        method['title']?.toString() ?? '-',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setDialogState(
                                () => selectedMethodId = value,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(20),
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
                                  if ((selectedMethod['description']
                                              ?.toString() ??
                                          '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      selectedMethod['description']
                                              ?.toString() ??
                                          '',
                                      style: AppTheme.bodyAction.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      ShwakelCard(
                        padding: const EdgeInsets.all(18),
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(24),
                        shadowLevel: ShwakelShadowLevel.none,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('screens_balance_screen.072'),
                              style: AppTheme.bodyBold,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                ),
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
                              readOnly: true,
                              onTap: pickTransferDate,
                              decoration: InputDecoration(
                                labelText: l.tr('screens_balance_screen.066'),
                                helperText: l.tr('screens_balance_screen.067'),
                                prefixIcon: const Icon(Icons.schedule_rounded),
                                suffixIcon: SizedBox(
                                  width: 96,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: l.tr(
                                          'screens_balance_screen.126',
                                        ),
                                        onPressed: pickTransferDate,
                                        icon: const Icon(
                                          Icons.calendar_today_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l.tr(
                                          'screens_balance_screen.127',
                                        ),
                                        onPressed: pickTransferTime,
                                        icon: const Icon(
                                          Icons.access_time_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                          ],
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
                SizedBox(
                  width: 170,
                  child: ShwakelButton(
                    label: isSubmitting
                        ? l.tr('screens_balance_screen.070')
                        : l.tr('screens_balance_screen.071'),
                    isLoading: isSubmitting,
                    onPressed: isSubmitting ? null : submit,
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

  String _formatTopupRequestDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Widget _buildTopupRequestInfoCard({
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && !_canOpenBalanceWorkspace) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('الرصيد والحركات'),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: ResponsiveScaffoldContainer(
          child: Center(
            child: ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                'الميزات المالية غير مفعلة لهذا الحساب حالياً.',
                style: AppTheme.bodyAction,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_balance_screen.020')),
        actions: [
          if (_tabController.index == 1)
            IconButton(
              tooltip: _showHistoryFilters
                  ? l.tr('screens_balance_screen.073')
                  : l.tr('screens_balance_screen.074'),
              onPressed: () =>
                  setState(() => _showHistoryFilters = !_showHistoryFilters),
              icon: Icon(
                _showHistoryFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.filter_alt_rounded,
              ),
            ),
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadBalance,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: AppTheme.pagePadding(context, top: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 920;
                final isPhone = constraints.maxWidth < 640;
                final showingActionsTab = _tabController.index == 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBalanceOverviewCard(isPhone: isPhone),
                    const SizedBox(height: 14),
                    _buildTopTabs(isPhone: isPhone),
                    const SizedBox(height: 16),
                    if (showingActionsTab)
                      _buildActionsCard(isCompact: isCompact, isPhone: isPhone)
                    else ...[
                      if (_showHistoryFilters) ...[
                        _buildAuditFilters(compact: isCompact),
                        const SizedBox(height: 14),
                      ],
                      if (_transactions.isEmpty)
                        _buildEmptyState()
                      else ...[
                        _buildHistoryResultsHeader(),
                        const SizedBox(height: 10),
                        ..._transactions.map(
                          (tx) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildBalanceHistoryCard(
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopTabs({required bool isPhone}) {
    final l = context.loc;
    if (isPhone) {
      return Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              icon: Icons.flash_on_rounded,
              label: l.tr('screens_balance_screen.111'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTabButton(
              index: 1,
              icon: Icons.receipt_long_rounded,
              label: l.tr('screens_balance_screen.112'),
            ),
          ),
        ],
      );
    }
    return TabBar(
      controller: _tabController,
      isScrollable: false,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(vertical: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: [
        Tab(
          icon: const Icon(Icons.flash_on_rounded),
          text: context.loc.tr('screens_balance_screen.111'),
        ),
        Tab(
          icon: const Icon(Icons.receipt_long_rounded),
          text: context.loc.tr('screens_balance_screen.112'),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _tabController.index == index;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _tabController.animateTo(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.2)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyBold.copyWith(
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceOverviewCard({required bool isPhone}) {
    final l = context.loc;
    final balance = _userAmount('balance');
    final availablePrintingBalance = _userAmount('availablePrintingBalance');
    final printingDebtLimit = _userAmount('printingDebtLimit');
    final outstandingDebt = _userAmount('outstandingDebt');
    final showAvailablePrintingBalance =
        (availablePrintingBalance - balance).abs() > 0.0001;
    final showPrintingDebtLimit = printingDebtLimit > 0;
    final showOutstandingDebt = outstandingDebt > 0;
    final roleLabel = _user?['roleLabel']?.toString().trim() ?? '';
    final verificationLabel = _isVerifiedAccount
        ? l.tr('screens_balance_screen.036')
        : l.tr('screens_balance_screen.037');
    final details = <_BalanceOverviewItem>[
      if (showAvailablePrintingBalance)
        _BalanceOverviewItem(
          icon: Icons.print_rounded,
          label: l.tr('screens_balance_screen.117'),
          value: CurrencyFormatter.ils(availablePrintingBalance),
          color: AppTheme.accent,
        ),
      if (showPrintingDebtLimit)
        _BalanceOverviewItem(
          icon: Icons.credit_score_rounded,
          label: l.tr('screens_balance_screen.118'),
          value: CurrencyFormatter.ils(printingDebtLimit),
          color: AppTheme.warning,
        ),
      if (showOutstandingDebt)
        _BalanceOverviewItem(
          icon: Icons.trending_down_rounded,
          label: l.tr('screens_balance_screen.119'),
          value: CurrencyFormatter.ils(outstandingDebt),
          color: outstandingDebt > 0 ? AppTheme.error : AppTheme.success,
        ),
      _BalanceOverviewItem(
        icon: Icons.verified_user_rounded,
        label: l.tr('screens_balance_screen.120'),
        value: verificationLabel,
        color: _isVerifiedAccount ? AppTheme.success : AppTheme.warning,
      ),
      _BalanceOverviewItem(
        icon: Icons.send_rounded,
        label: l.tr('screens_balance_screen.121'),
        value: _canTransferAction
            ? l.tr('screens_balance_screen.039')
            : l.tr('screens_balance_screen.040'),
        color: _canTransferAction ? AppTheme.success : AppTheme.textSecondary,
      ),
      _BalanceOverviewItem(
        icon: Icons.account_circle_rounded,
        label: l.tr('screens_balance_screen.122'),
        value: roleLabel.isNotEmpty
            ? roleLabel
            : l.tr('screens_balance_screen.040'),
        color: AppTheme.primary,
      ),
    ];

    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(30),
      shadowLevel: ShwakelShadowLevel.premium,
      gradient: const LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF0F766E), Color(0xFF14B8A6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_balance_screen.116'),
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.ils(balance),
                      style: AppTheme.h1.copyWith(
                        color: Colors.white,
                        fontSize: isPhone ? 32 : 40,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.tr('screens_balance_screen.123'),
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: details
                .map(
                  (item) => SizedBox(
                    width: isPhone ? double.infinity : 220,
                    child: _buildBalanceOverviewTile(item),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceOverviewTile(_BalanceOverviewItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _userAmount(String key) {
    final value = _user?[key];
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
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

  Widget _buildAuditFilters({required bool compact}) {
    final l = context.loc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
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
          if (_userAmount('printingDebtLimit') > 0 ||
              _userAmount('outstandingDebt') > 0)
            _filterChip(
              l.tr('screens_balance_screen.047'),
              _BalanceAuditFilter.printingDebt,
              compact: compact,
            ),
        ],
      ),
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

  Widget _buildHistoryResultsHeader() {
    final l = context.loc;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        return Flex(
          direction: isCompact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: isCompact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (isCompact)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tr('screens_balance_screen.113'),
                    style: AppTheme.h3.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.tr('screens_balance_screen.114'),
                    style: AppTheme.caption,
                  ),
                ],
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_balance_screen.113'),
                      style: AppTheme.h3.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.tr('screens_balance_screen.114'),
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            if (_showHistoryFilters) ...[
              SizedBox(width: isCompact ? 0 : 12, height: isCompact ? 10 : 0),
              TextButton.icon(
                onPressed: () => setState(() => _showHistoryFilters = false),
                icon: const Icon(Icons.expand_less_rounded, size: 18),
                label: Text(l.tr('screens_balance_screen.115')),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBalanceHistoryCard({required Map<String, dynamic> transaction}) {
    final l = context.loc;
    final type = transaction['type']?.toString() ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final createdAt = transaction['createdAt']?.toString() ?? '';
    final status = transaction['status']?.toString() ?? 'completed';
    final metadata = Map<String, dynamic>.from(
      transaction['metadata'] as Map? ?? const {},
    );
    final audit = metadata['locationAudit'];
    final isNearBranch = audit is Map && audit['isNearSupportedBranch'] == true;
    final isRejected = status == 'rejected' || type == 'withdrawal_rejected';
    final accentColor = _historyAccentColor(
      type: type,
      amount: amount,
      isRejected: isRejected,
    );
    final actorLine = _historyActorLine(type: type, metadata: metadata);

    return ShwakelCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(22),
      shadowLevel: ShwakelShadowLevel.soft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final amountBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              CurrencyFormatter.ils(amount),
              style: AppTheme.bodyBold.copyWith(
                color: accentColor,
                fontSize: 13,
              ),
            ),
          );

          return Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _historyIcon(
                    type: type,
                    amount: amount,
                    isRejected: isRejected,
                  ),
                  color: accentColor,
                  size: 20,
                ),
              ),
              SizedBox(width: isCompact ? 0 : 12, height: isCompact ? 12 : 0),
              if (isCompact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _historyTypeLabel(type: type, metadata: metadata),
                      style: AppTheme.bodyBold.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    amountBadge,
                    const SizedBox(height: 6),
                    _buildHistoryMeta(
                      createdAt: createdAt,
                      isRejected: isRejected,
                      actorLine: actorLine,
                      isNearBranch: isNearBranch,
                      l: l,
                    ),
                  ],
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _historyTypeLabel(type: type, metadata: metadata),
                              style: AppTheme.bodyBold.copyWith(fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 8),
                          amountBadge,
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildHistoryMeta(
                        createdAt: createdAt,
                        isRejected: isRejected,
                        actorLine: actorLine,
                        isNearBranch: isNearBranch,
                        l: l,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryMeta({
    required String createdAt,
    required bool isRejected,
    required String? actorLine,
    required bool isNearBranch,
    required AppLocalizer l,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              createdAt,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            if (isRejected)
              Text(
                l.tr('widgets_admin_transaction_audit_card.029'),
                style: AppTheme.caption.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        if (actorLine != null) ...[
          const SizedBox(height: 4),
          Text(
            actorLine,
            style: AppTheme.caption.copyWith(
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              isNearBranch ? Icons.place_rounded : Icons.location_off_outlined,
              size: 14,
              color: isNearBranch ? AppTheme.primary : AppTheme.warning,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                isNearBranch
                    ? l.tr('widgets_admin_transaction_audit_card.030')
                    : l.tr('widgets_admin_transaction_audit_card.031'),
                style: AppTheme.caption.copyWith(
                  color: isNearBranch ? AppTheme.primary : AppTheme.warning,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _historyTypeLabel({
    required String type,
    required Map<String, dynamic> metadata,
  }) {
    final l = context.loc;
    switch (type) {
      case 'topup':
        return l.tr('widgets_admin_transaction_audit_card.001');
      case 'transfer_out':
        return l.tr('widgets_admin_transaction_audit_card.002');
      case 'transfer_in':
        return l.tr('widgets_admin_transaction_audit_card.003');
      case 'redeem_card':
        return l.tr('widgets_admin_transaction_audit_card.004');
      case 'resell_card':
        return l.tr('widgets_admin_transaction_audit_card.005');
      case 'issue_cards':
        return l.tr('widgets_admin_transaction_audit_card.006');
      case 'withdrawal_request':
        return l.tr('widgets_admin_transaction_audit_card.007');
      case 'withdrawal_rejected':
        return l.tr('widgets_admin_transaction_audit_card.008');
      case 'withdrawal_completed':
        return l.tr('widgets_admin_transaction_audit_card.009');
      case 'balance_credit':
        return (metadata['sourceType']?.toString() ?? '') ==
                'printing_debt_settlement'
            ? l.tr('widgets_admin_transaction_audit_card.010')
            : l.tr('widgets_admin_transaction_audit_card.011');
      case 'app_fee_credit':
        return l.tr('widgets_admin_transaction_audit_card.012');
      default:
        return type.trim().isEmpty
            ? l.tr('widgets_admin_transaction_audit_card.013')
            : type;
    }
  }

  String? _historyActorLine({
    required String type,
    required Map<String, dynamic> metadata,
  }) {
    final l = context.loc;
    final byUsername = metadata['byUsername']?.toString().trim();
    final senderUsername = metadata['senderUsername']?.toString().trim();
    final recipientUsername = metadata['recipientUsername']?.toString().trim();
    final customerName = metadata['customerName']?.toString().trim();
    final targetUsername = metadata['targetUsername']?.toString().trim();
    final sourceUsername = metadata['sourceUsername']?.toString().trim();
    final sourceType = metadata['sourceType']?.toString().trim();

    switch (type) {
      case 'topup':
      case 'redeem_card':
      case 'resell_card':
      case 'balance_credit':
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.014',
            params: {'username': byUsername},
          );
        }
        if (customerName != null && customerName.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.017',
            params: {'name': customerName},
          );
        }
        break;
      case 'transfer_out':
        if (recipientUsername != null && recipientUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.015',
            params: {'username': recipientUsername},
          );
        }
        break;
      case 'transfer_in':
        if (senderUsername != null && senderUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.016',
            params: {'username': senderUsername},
          );
        }
        break;
      case 'issue_cards':
        if (byUsername != null && byUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.018',
            params: {'username': byUsername},
          );
        }
        break;
      case 'app_fee_credit':
        if (targetUsername != null && targetUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.020',
            params: {'username': targetUsername},
          );
        }
        if (sourceUsername != null && sourceUsername.isNotEmpty) {
          return l.tr(
            'widgets_admin_transaction_audit_card.021',
            params: {'username': sourceUsername},
          );
        }
        if (sourceType != null && sourceType.isNotEmpty) {
          switch (sourceType) {
            case 'topup':
              return l.tr('widgets_admin_transaction_audit_card.022');
            case 'transfer':
              return l.tr('widgets_admin_transaction_audit_card.023');
            case 'card_redeem':
              return l.tr('widgets_admin_transaction_audit_card.024');
            case 'card_resell':
              return l.tr('widgets_admin_transaction_audit_card.025');
          }
        }
        break;
      case 'withdrawal_request':
        return l.tr('widgets_admin_transaction_audit_card.026');
      case 'withdrawal_rejected':
        return l.tr('widgets_admin_transaction_audit_card.027');
      case 'withdrawal_completed':
        return l.tr('widgets_admin_transaction_audit_card.028');
    }

    return null;
  }

  IconData _historyIcon({
    required String type,
    required double amount,
    required bool isRejected,
  }) {
    if (isRejected) return Icons.block_rounded;
    switch (type) {
      case 'transfer_out':
      case 'withdrawal_request':
      case 'resell_card':
        return Icons.north_east_rounded;
      case 'transfer_in':
      case 'topup':
      case 'balance_credit':
      case 'redeem_card':
        return Icons.south_west_rounded;
      case 'issue_cards':
        return Icons.add_card_rounded;
      default:
        return amount >= 0
            ? Icons.add_circle_rounded
            : Icons.remove_circle_rounded;
    }
  }

  Color _historyAccentColor({
    required String type,
    required double amount,
    required bool isRejected,
  }) {
    if (isRejected) return AppTheme.error;
    switch (type) {
      case 'transfer_out':
      case 'withdrawal_request':
      case 'resell_card':
        return AppTheme.warning;
      case 'issue_cards':
        return AppTheme.accent;
      default:
        return amount >= 0 ? AppTheme.primary : AppTheme.warning;
    }
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_transactions_screen.039'),
      message: l.tr('screens_balance_screen.080'),
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
    int recipientLookupTab = enablePhoneLookup ? 1 : 0;

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
          if (selectedUser != null && enablePhoneLookup) {
            recipientLookupTab = 2;
          }
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
            searchResults = const [];
            searchError = null;
            phoneLookupMessage = l.tr('screens_balance_screen.076');
            recipientLookupTab = 2;
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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShwakelCard(
                    padding: const EdgeInsets.all(18),
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(24),
                    shadowLevel: ShwakelShadowLevel.none,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AppTheme.h3),
                              const SizedBox(height: 4),
                              Text(
                                enablePhoneLookup
                                    ? l.tr('screens_balance_screen.128')
                                    : l.tr('screens_balance_screen.079'),
                                style: AppTheme.bodyAction.copyWith(
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enablePhoneLookup) ...[
                    const SizedBox(height: 18),
                    _buildRecipientLookupTabs(
                      selectedIndex: recipientLookupTab,
                      onChanged: (index) {
                        setDialogState(() {
                          recipientLookupTab = index;
                          searchError = null;
                          phoneLookupMessage = null;
                        });
                      },
                    ),
                  ],
                  if (!enablePhoneLookup || recipientLookupTab == 0) ...[
                    const SizedBox(height: 18),
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
                  if (enablePhoneLookup && recipientLookupTab == 1) ...[
                    const SizedBox(height: 18),
                    ShwakelCard(
                      padding: const EdgeInsets.all(18),
                      borderRadius: BorderRadius.circular(24),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.phone_rounded,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.tr('screens_balance_screen.083'),
                                      style: AppTheme.bodyBold,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l.tr('screens_balance_screen.129'),
                                      style: AppTheme.caption.copyWith(
                                        color: AppTheme.textSecondary,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 360;
                              if (isCompact) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: countryCode,
                                      decoration: InputDecoration(
                                        labelText: l.tr(
                                          'screens_balance_screen.084',
                                        ),
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
                                        setDialogState(
                                          () => countryCode = value,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: phoneController,
                                      keyboardType: TextInputType.phone,
                                      decoration: InputDecoration(
                                        labelText: l.tr(
                                          'screens_balance_screen.085',
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.phone_rounded,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ShwakelButton(
                                      label: isLookingUpPhone
                                          ? l.tr('screens_balance_screen.086')
                                          : l.tr('screens_balance_screen.087'),
                                      icon: Icons.verified_user_outlined,
                                      isSecondary: true,
                                      isLoading: isLookingUpPhone,
                                      onPressed: isLookingUpPhone
                                          ? null
                                          : () => performPhoneLookup(
                                              setDialogState,
                                            ),
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  SizedBox(
                                    width: 156,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: countryCode,
                                      decoration: InputDecoration(
                                        labelText: l.tr(
                                          'screens_balance_screen.084',
                                        ),
                                      ),
                                      items: PhoneNumberService.countries
                                          .map(
                                            (country) => DropdownMenuItem(
                                              value: country.dialCode,
                                              child: Text(
                                                '+${country.dialCode}',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(
                                          () => countryCode = value,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: phoneController,
                                      keyboardType: TextInputType.phone,
                                      decoration: InputDecoration(
                                        labelText: l.tr(
                                          'screens_balance_screen.085',
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.phone_rounded,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 140,
                                    child: ShwakelButton(
                                      label: isLookingUpPhone
                                          ? l.tr('screens_balance_screen.086')
                                          : l.tr('screens_balance_screen.088'),
                                      isSecondary: true,
                                      isLoading: isLookingUpPhone,
                                      onPressed: isLookingUpPhone
                                          ? null
                                          : () => performPhoneLookup(
                                              setDialogState,
                                            ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (phoneLookupMessage != null) ...[
                            const SizedBox(height: 10),
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
                      ),
                    ),
                  ],
                  if (searchResults.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      l.tr('screens_balance_screen.130'),
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = searchResults[index];
                          final isSelected =
                              selectedUser?['id']?.toString() ==
                              item['id']?.toString();
                          return ShwakelCard(
                            padding: const EdgeInsets.all(14),
                            borderRadius: BorderRadius.circular(20),
                            color: isSelected
                                ? AppTheme.tabSurface
                                : AppTheme.surface,
                            borderColor: isSelected
                                ? AppTheme.primary.withValues(alpha: 0.35)
                                : AppTheme.border,
                            shadowLevel: ShwakelShadowLevel.none,
                            onTap: () => setDialogState(() {
                              selectedUser = item;
                              if (enablePhoneLookup) {
                                recipientLookupTab = 2;
                              }
                            }),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppTheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.person_outline_rounded,
                                    color: isSelected
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['username']?.toString() ?? '-',
                                        style: AppTheme.bodyBold,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        enablePhoneLookup
                                            ? l.tr(
                                                'screens_balance_screen.089',
                                                params: {'id': '${item['id']}'},
                                              )
                                            : l.tr(
                                                'screens_balance_screen.090',
                                                params: {
                                                  'id': '${item['id']}',
                                                  'balance':
                                                      CurrencyFormatter.ils(
                                                        (item['balance']
                                                                    as num?)
                                                                ?.toDouble() ??
                                                            0,
                                                      ),
                                                },
                                              ),
                                        style: AppTheme.caption.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (enablePhoneLookup && recipientLookupTab == 2) ...[
                    const SizedBox(height: 16),
                    _buildSelectedRecipientPanel(selectedUser: selectedUser),
                  ] else if (!enablePhoneLookup && selectedUser != null) ...[
                    const SizedBox(height: 16),
                    _buildSelectedRecipientPanel(selectedUser: selectedUser),
                  ],
                  const SizedBox(height: 18),
                  ShwakelCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(24),
                    shadowLevel: ShwakelShadowLevel.none,
                    color: AppTheme.surfaceVariant,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_balance_screen.108'),
                          style: AppTheme.bodyBold,
                        ),
                        const SizedBox(height: 12),
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
                      ],
                    ),
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
                    () => searchError =
                        enablePhoneLookup && recipientLookupTab != 2
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

  Widget _buildRecipientLookupTabs({
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(6),
      borderRadius: BorderRadius.circular(18),
      shadowLevel: ShwakelShadowLevel.none,
      child: Row(
        children: [
          Expanded(
            child: _buildRecipientLookupTab(
              selected: selectedIndex == 0,
              icon: Icons.search_rounded,
              label: l.tr('screens_balance_screen.132'),
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildRecipientLookupTab(
              selected: selectedIndex == 1,
              icon: Icons.phone_iphone_rounded,
              label: l.tr('screens_balance_screen.133'),
              onTap: () => onChanged(1),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildRecipientLookupTab(
              selected: selectedIndex == 2,
              icon: Icons.person_pin_circle_rounded,
              label: l.tr('screens_balance_screen.134'),
              onTap: () => onChanged(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRecipientPanel({
    required Map<String, dynamic>? selectedUser,
  }) {
    final l = context.loc;
    if (selectedUser == null) {
      return ShwakelCard(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(22),
        shadowLevel: ShwakelShadowLevel.none,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.tr('screens_balance_screen.134'), style: AppTheme.bodyBold),
            const SizedBox(height: 8),
            Text(
              l.tr('screens_balance_screen.135'),
              style: AppTheme.caption.copyWith(
                color: AppTheme.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return ShwakelCard(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppTheme.primary.withValues(alpha: 0.05),
      borderColor: AppTheme.primary.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(22),
      shadowLevel: ShwakelShadowLevel.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_pin_circle_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_balance_screen.091'),
                      style: AppTheme.caption.copyWith(color: AppTheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedUser['username']?.toString() ?? '-',
                      style: AppTheme.bodyBold.copyWith(
                        color: AppTheme.primary,
                      ),
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
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l.tr('screens_balance_screen.131'),
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l.tr('screens_balance_screen.092'),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          if ((selectedUser['whatsapp']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              selectedUser['whatsapp']?.toString() ?? '',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecipientLookupTab({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.24)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
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
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShwakelCard(
                      padding: const EdgeInsets.all(18),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(24),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.outbox_rounded,
                              color: AppTheme.warning,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.tr('screens_balance_screen.030'),
                                  style: AppTheme.h3,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l.tr('screens_balance_screen.098'),
                                  style: AppTheme.bodyAction.copyWith(
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ShwakelCard(
                      padding: const EdgeInsets.all(18),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(24),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('screens_balance_screen.109'),
                            style: AppTheme.bodyBold,
                          ),
                          const SizedBox(height: 12),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    ShwakelCard(
                      padding: const EdgeInsets.all(18),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(24),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('screens_balance_screen.110'),
                            style: AppTheme.bodyBold,
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
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                            ),
                          ),
                          if (isBankTransfer) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: bankController,
                              decoration: InputDecoration(
                                labelText: l.tr('screens_balance_screen.104'),
                                prefixIcon: const Icon(
                                  Icons.account_balance_rounded,
                                ),
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
                        ],
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 12),
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
              SizedBox(
                width: 170,
                child: ShwakelButton(
                  label: l.tr('screens_balance_screen.071'),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _BalanceAuditFilter { all, nearBranch, outsideBranches, printingDebt }

class _BalanceOverviewItem {
  const _BalanceOverviewItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

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
