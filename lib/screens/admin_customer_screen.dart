import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_enums.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';

class AdminCustomerScreen extends StatefulWidget {
  const AdminCustomerScreen({
    super.key,
    required this.customer,
    this.canExport = false,
    this.canManageUsers = false,
    this.canManageMarketingAccounts = false,
  });

  final Map<String, dynamic> customer;
  final bool canExport;
  final bool canManageUsers;
  final bool canManageMarketingAccounts;

  @override
  State<AdminCustomerScreen> createState() => _AdminCustomerScreenState();
}

class _AdminCustomerScreenState extends State<AdminCustomerScreen> {
  final _api = ApiService();
  final _maxDevicesController = TextEditingController();
  final _printingDebtLimitController = TextEditingController();
  final _topupFeeController = TextEditingController();
  final _withdrawFeeController = TextEditingController();
  final _transferFeeController = TextEditingController();
  final _redeemFeeController = TextEditingController();
  final _resellFeeController = TextEditingController();
  final _cardPrintRequestFeeController = TextEditingController();

  late Map<String, dynamic> _customer;
  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _devices = const [];
  Map<String, dynamic>? _verificationRequest;
  Map<String, String> _verificationImageHeaders = const {};
  bool _firstLoad = true;
  bool _busy = false;
  String _role = 'restricted';
  String _verification = 'unverified';
  int _txPage = 1;
  static const _perPage = 10;
  AdminTransactionAuditFilter _auditFilter = AdminTransactionAuditFilter.all;
  bool _showTransactionFilters = false;

  bool get _canManageAccountControls =>
      widget.canManageUsers || widget.canManageMarketingAccounts;

  bool get _isMarketingManagerOnly =>
      widget.canManageMarketingAccounts && !widget.canManageUsers;

  bool get _isStaffAccount {
    final role = _customer['role']?.toString().trim().toLowerCase() ?? '';
    return role == 'admin' || role == 'support' || role == 'marketer';
  }

  @override
  void initState() {
    super.initState();
    _customer = Map<String, dynamic>.from(widget.customer);
    _syncFields();
    _loadCustomer(full: true);
  }

  @override
  void dispose() {
    _maxDevicesController.dispose();
    _printingDebtLimitController.dispose();
    _topupFeeController.dispose();
    _withdrawFeeController.dispose();
    _transferFeeController.dispose();
    _redeemFeeController.dispose();
    _resellFeeController.dispose();
    _cardPrintRequestFeeController.dispose();
    super.dispose();
  }

  String _t(String key) => context.loc.tr(key);

  void _syncFields() {
    _role = _customer['role']?.toString() ?? 'restricted';
    _verification =
        _customer['transferVerificationStatus']?.toString() ?? 'unverified';
    _maxDevicesController.text =
        ((_customer['maxDevices'] as num?)?.toInt() ?? 1).toString();
    _printingDebtLimitController.text =
        ((_customer['printingDebtLimit'] as num?)?.toDouble() ?? 5)
            .toStringAsFixed(2);
    _topupFeeController.text = _formatPct(_customer['customTopupFeePercent']);
    _withdrawFeeController.text = _formatPct(
      _customer['customWithdrawFeePercent'],
    );
    _transferFeeController.text = _formatPct(
      _customer['customTransferFeePercent'],
    );
    _redeemFeeController.text = _formatPct(
      _customer['customCardRedeemFeePercent'],
    );
    _resellFeeController.text = _formatPct(
      _customer['customCardResellFeePercent'],
    );
    _cardPrintRequestFeeController.text = _formatPct(
      _customer['customCardPrintRequestFeePercent'],
    );
  }

  String _formatPct(Object? v) {
    if (v == null) return '';
    final d = (v as num).toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Future<void> _loadCustomer({bool full = false}) async {
    setState(() => full ? _firstLoad = true : _busy = true);
    try {
      final id = _customer['id']?.toString() ?? '';
      final filter = _auditFilter == AdminTransactionAuditFilter.nearBranch
          ? 'near_branch'
          : (_auditFilter == AdminTransactionAuditFilter.outsideBranches
                ? 'outside_branches'
                : 'all');
      final results = await Future.wait<dynamic>([
        _api.getAdminCustomerTransactions(id, locationFilter: filter),
        widget.canManageUsers
            ? _api.getAdminUserDevices(id)
            : Future.value(const <String, dynamic>{'devices': []}),
        widget.canManageUsers
            ? _api.getAdminUserVerification(id)
            : Future.value(const <String, dynamic>{
                'verificationRequest': null,
              }),
        widget.canManageUsers
            ? _api.authenticatedHeaders()
            : Future.value(const <String, String>{}),
      ]);
      if (!mounted) return;
      final txData = Map<String, dynamic>.from(results[0] as Map);
      final dvData = Map<String, dynamic>.from(results[1] as Map);
      final verificationData = Map<String, dynamic>.from(results[2] as Map);
      setState(() {
        _customer = Map<String, dynamic>.from(
          txData['customer'] as Map? ?? _customer,
        );
        _transactions = List<Map<String, dynamic>>.from(
          txData['transactions'] as List? ?? [],
        );
        _devices = widget.canManageUsers
            ? List<Map<String, dynamic>>.from(dvData['devices'] as List? ?? [])
            : const [];
        _verificationRequest =
            widget.canManageUsers &&
                verificationData['verificationRequest'] is Map
            ? Map<String, dynamic>.from(
                verificationData['verificationRequest'] as Map,
              )
            : null;
        _verificationImageHeaders = widget.canManageUsers
            ? Map<String, String>.from(results[3] as Map)
            : const {};
        _txPage = 1;
        _syncFields();
        _firstLoad = false;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _firstLoad = false;
          _busy = false;
        });
      }
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  Future<void> _updateAccount() async {
    if (!_canManageAccountControls) {
      return;
    }

    setState(() => _busy = true);
    try {
      final payload = await _api.updateAdminUserAccountControls(
        userId: _customer['id'].toString(),
        isDisabled: _customer['isDisabled'] == true,
        transferVerificationStatus: _verification,
        role: _role,
        printingDebtLimit:
            double.tryParse(_printingDebtLimitController.text) ?? 0,
        customTopupFeePercent: double.tryParse(_topupFeeController.text),
        customWithdrawFeePercent: double.tryParse(_withdrawFeeController.text),
        customTransferFeePercent: double.tryParse(_transferFeeController.text),
        customCardRedeemFeePercent: double.tryParse(_redeemFeeController.text),
        customCardResellFeePercent: double.tryParse(_resellFeeController.text),
        customCardPrintRequestFeePercent: double.tryParse(
          _cardPrintRequestFeeController.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        _customer = Map<String, dynamic>.from(payload['user']);
        _syncFields();
        _busy = false;
      });
      AppAlertService.showSuccess(
        context,
        message: context.loc.tr('screens_admin_customer_screen.065'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  Future<void> _resendAccountDetails() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_admin_customer_screen.001')),
        content: Text(context.loc.tr('screens_admin_customer_screen.066')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('screens_admin_customer_screen.002')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('screens_admin_customer_screen.003')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final response = await _api.resendAdminUserAccountDetails(
        userId: _customer['id'].toString(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_admin_customer_screen.004'),
        message:
            response['message']?.toString() ??
            context.loc.tr('screens_admin_customer_screen.067'),
      );
      await _loadCustomer(full: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_customer_screen.005'),
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  Future<void> _showBalanceAdjustmentDialog({required bool isCredit}) async {
    if (!widget.canManageUsers) {
      return;
    }

    final amountController = TextEditingController();
    final notesController = TextEditingController(
      text: isCredit
          ? 'إضافة رصيد من صفحة المستخدم'
          : 'سحب رصيد من صفحة المستخدم',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isCredit ? 'إضافة رصيد' : 'سحب رصيد'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customer['username']?.toString() ?? '',
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    prefixText: '₪ ',
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'),
                    );
                    if (amount == null || amount <= 0) {
                      return 'أدخل مبلغًا صحيحًا';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  maxLength: 250,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                if (!isCredit) ...[
                  const SizedBox(height: 8),
                  Text(
                    'سيتم خصم الرصيد إداريًا، وقد يصبح الحساب بالسالب إذا كان المبلغ أكبر من الرصيد الحالي.',
                    style: AppTheme.caption.copyWith(color: AppTheme.warning),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() != true) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              icon: Icon(
                isCredit
                    ? Icons.add_card_rounded
                    : Icons.remove_circle_outline_rounded,
              ),
              label: Text(isCredit ? 'إضافة الرصيد' : 'سحب الرصيد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      amountController.dispose();
      notesController.dispose();
      return;
    }

    final amount =
        double.tryParse(amountController.text.trim().replaceAll(',', '.')) ?? 0;
    final notes = notesController.text.trim();
    amountController.dispose();
    notesController.dispose();

    setState(() => _busy = true);
    try {
      final response = isCredit
          ? await _api.addAdminUserBalance(
              userId: _customer['id'].toString(),
              amount: amount,
              notes: notes,
            )
          : await _api.deductAdminUserBalance(
              userId: _customer['id'].toString(),
              amount: amount,
              notes: notes,
            );

      if (!mounted) {
        return;
      }
      await _loadCustomer(full: true);
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ??
            (isCredit ? 'تمت إضافة الرصيد بنجاح.' : 'تم سحب الرصيد بنجاح.'),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tabs = <Tab>[
      Tab(
        text: _t('screens_admin_customer_screen.007'),
        icon: const Icon(Icons.info_outline_rounded, size: 20),
      ),
      Tab(
        text: _t('screens_admin_customer_screen.008'),
        icon: const Icon(Icons.receipt_long_rounded, size: 20),
      ),
      if (_canManageAccountControls)
        Tab(
          text: _t('screens_admin_customer_screen.009'),
          icon: const Icon(Icons.manage_accounts_rounded, size: 20),
        ),
      if (widget.canManageUsers)
        Tab(
          text: _t('screens_admin_customer_screen.010'),
          icon: const Icon(Icons.security_rounded, size: 20),
        ),
      if (widget.canManageUsers)
        Tab(
          text: _t('screens_admin_customer_screen.011'),
          icon: const Icon(Icons.devices_rounded, size: 20),
        ),
      if (widget.canManageUsers)
        const Tab(
          text: 'توثيق الحساب',
          icon: Icon(Icons.verified_user_rounded, size: 20),
        ),
    ];
    final views = <Widget>[
      _buildOverviewTab(),
      _buildTransactionsTab(),
      if (_canManageAccountControls) _buildManagementTab(),
      if (widget.canManageUsers) _buildPermissionsTab(),
      if (widget.canManageUsers) _buildDevicesTab(),
      if (widget.canManageUsers) _buildVerificationTab(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              tooltip: _showTransactionFilters
                  ? _t('screens_admin_customer_screen.073')
                  : _t('screens_admin_customer_screen.074'),
              onPressed: () => setState(
                () => _showTransactionFilters = !_showTransactionFilters,
              ),
              icon: Icon(
                _showTransactionFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.filter_alt_rounded,
              ),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(74),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  isScrollable: true,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  tabs: tabs,
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(children: views),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final isPhone = AppTheme.isPhone(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            _buildProfileHero(),
            if (widget.canManageUsers) ...[
              const SizedBox(height: 16),
              ShwakelCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('screens_admin_customer_screen.012'),
                      style: AppTheme.h3,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.loc.tr('screens_admin_customer_screen.068'),
                      style: AppTheme.bodyAction,
                    ),
                    const SizedBox(height: 16),
                    ShwakelButton(
                      label: _t('screens_admin_customer_screen.075'),
                      icon: Icons.mark_chat_unread_rounded,
                      onPressed: _busy ? null : _resendAccountDetails,
                      isLoading: _busy,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: isPhone ? double.infinity : 420,
                  child: _buildMetricCard(
                    _t('screens_admin_customer_screen.013'),
                    CurrencyFormatter.ils(
                      ((_customer['balance'] as num?) ?? 0).toDouble(),
                    ),
                    Icons.account_balance_wallet_rounded,
                    AppTheme.primary,
                  ),
                ),
                SizedBox(
                  width: isPhone ? double.infinity : 420,
                  child: _buildMetricCard(
                    _t('screens_admin_customer_screen.014'),
                    _customer['isDisabled'] == true
                        ? _t('screens_admin_customer_screen.015')
                        : _t('screens_admin_customer_screen.016'),
                    Icons.verified_user_rounded,
                    _customer['isDisabled'] == true
                        ? AppTheme.error
                        : AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('screens_admin_customer_screen.017'),
                    style: AppTheme.h3,
                  ),
                  const SizedBox(height: 16),
                  _infoRow(
                    _t('screens_admin_customer_screen.018'),
                    _customer['username'] ?? '-',
                  ),
                  _infoRow(
                    _t('screens_admin_customer_screen.019'),
                    _customer['fullName'] ?? '-',
                  ),
                  _infoRow(
                    _t('screens_admin_customer_screen.020'),
                    _customer['whatsapp'] ?? '-',
                  ),
                  _infoRow(
                    _t('screens_admin_customer_screen.021'),
                    _customer['createdAt'] ?? '-',
                  ),
                ],
              ),
            ),
            if (widget.canManageUsers) ...[
              const SizedBox(height: 24),
              _buildBalanceManagementCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceManagementCard() {
    final balance = ((_customer['balance'] as num?) ?? 0).toDouble();

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إدارة الرصيد', style: AppTheme.h3),
                    const SizedBox(height: 2),
                    Text(
                      'الرصيد الحالي: ${CurrencyFormatter.ils(balance)}',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ShwakelButton(
                width: 180,
                height: 48,
                label: 'إضافة رصيد',
                icon: Icons.add_card_rounded,
                onPressed: _busy
                    ? null
                    : () => _showBalanceAdjustmentDialog(isCredit: true),
              ),
              ShwakelButton(
                width: 180,
                height: 48,
                label: 'سحب رصيد',
                icon: Icons.remove_circle_outline_rounded,
                isDanger: true,
                onPressed: _busy
                    ? null
                    : () => _showBalanceAdjustmentDialog(isCredit: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final avatar = CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              (_customer['username']
                      ?.toString()
                      .substring(0, 1)
                      .toUpperCase() ??
                  'U'),
              style: AppTheme.h1.copyWith(color: Colors.white, fontSize: 32),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _customer['fullName'] ?? _customer['username'],
                style: AppTheme.h2.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                _customer['roleLabel'] ??
                    _t('screens_admin_customer_screen.022'),
                style: AppTheme.caption.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(height: 16),
                details,
                if (_customer['isVerified'] == true) ...[
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.verified_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 24),
              Expanded(child: details),
              if (_customer['isVerified'] == true)
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 30,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionsTab() {
    final paged = _transactions
        .skip((_txPage - 1) * _perPage)
        .take(_perPage)
        .toList();
    final lastPage = (_transactions.length / _perPage)
        .ceil()
        .clamp(1, 999)
        .toInt();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            AdminSectionHeader(
              title: _t('screens_admin_customer_screen.023'),
              subtitle: _t('screens_admin_customer_screen.076'),
              icon: Icons.history_rounded,
              trailing: _showTransactionFilters
                  ? DropdownButton<AdminTransactionAuditFilter>(
                      value: _auditFilter,
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _auditFilter = v);
                          _loadCustomer();
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: AdminTransactionAuditFilter.all,
                          child: Text(_t('screens_admin_customer_screen.024')),
                        ),
                        DropdownMenuItem(
                          value: AdminTransactionAuditFilter.nearBranch,
                          child: Text(_t('screens_admin_customer_screen.025')),
                        ),
                        DropdownMenuItem(
                          value: AdminTransactionAuditFilter.outsideBranches,
                          child: Text(_t('screens_admin_customer_screen.026')),
                        ),
                      ],
                    )
                  : null,
            ),
            if (!_showTransactionFilters) ...[
              const SizedBox(height: 8),
              ToolToggleHint(
                message: _t('screens_admin_customer_screen.077'),
                icon: Icons.filter_alt_rounded,
              ),
            ],
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_transactions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    _t('screens_admin_customer_screen.027'),
                    style: AppTheme.caption,
                  ),
                ),
              )
            else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: paged.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminTransactionAuditCard(transaction: paged[i]),
                ),
              ),
              const SizedBox(height: 24),
              AdminPaginationFooter(
                currentPage: _txPage,
                lastPage: lastPage,
                onPageChanged: (p) => setState(() => _txPage = p),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManagementTab() {
    if (_isMarketingManagerOnly && _isStaffAccount) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: ResponsiveScaffoldContainer(
          child: ShwakelCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('screens_admin_customer_screen.028'),
                  style: AppTheme.h3,
                ),
                const SizedBox(height: 12),
                Text(
                  _t('screens_admin_customer_screen.080'),
                  style: AppTheme.bodyAction,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final roleOptions = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'restricted',
        child: Text(_t('screens_admin_customer_screen.030')),
      ),
      DropdownMenuItem(
        value: 'basic',
        child: Text(_t('screens_admin_customer_screen.038')),
      ),
      DropdownMenuItem(value: 'driver', child: Text(_t('shared.role_driver'))),
      DropdownMenuItem(
        value: 'verified_member',
        child: Text(_t('screens_admin_customer_screen.031')),
      ),
      if (widget.canManageUsers)
        DropdownMenuItem(
          value: 'marketer',
          child: Text(_t('shared.role_marketer')),
        ),
      if (widget.canManageUsers)
        DropdownMenuItem(
          value: 'support',
          child: Text(_t('screens_admin_customer_screen.039')),
        ),
      if (widget.canManageUsers)
        DropdownMenuItem(
          value: 'admin',
          child: Text(_t('screens_admin_customer_screen.040')),
        ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('screens_admin_customer_screen.028'),
                    style: AppTheme.h3,
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('screens_admin_customer_screen.014')),
                    subtitle: Text(
                      _customer['isDisabled'] == true
                          ? _t('screens_admin_customer_screen.015')
                          : _t('screens_admin_customer_screen.016'),
                    ),
                    value: _customer['isDisabled'] != true,
                    onChanged: (value) =>
                        setState(() => _customer['isDisabled'] = !value),
                  ),
                  const SizedBox(height: 16),
                  if (widget.canManageUsers) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _verification,
                      decoration: InputDecoration(
                        labelText: _t('screens_admin_customer_screen.029'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'unverified',
                          child: Text(_t('screens_admin_customer_screen.033')),
                        ),
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text(_t('screens_admin_customer_screen.034')),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text(_t('screens_admin_customer_screen.035')),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text(_t('screens_admin_customer_screen.036')),
                        ),
                      ],
                      onChanged: (v) => setState(() => _verification = v!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_customer_screen.037'),
                    ),
                    items: roleOptions,
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _printingDebtLimitController,
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_customer_screen.041'),
                      suffixText: '₪',
                    ),
                  ),
                  if (_isMarketingManagerOnly) ...[
                    const SizedBox(height: 12),
                    Text(
                      _t('screens_admin_customer_screen.079'),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  if (widget.canManageUsers) ...[
                    const SizedBox(height: 32),
                    Text(
                      _t('screens_admin_customer_screen.042'),
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 16),
                    _feeGrid(),
                  ],
                  const SizedBox(height: 40),
                  ShwakelButton(
                    label: _t('screens_admin_customer_screen.043'),
                    icon: Icons.save_rounded,
                    onPressed: _updateAccount,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feeGrid() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _feeField(_t('screens_admin_customer_screen.044'), _topupFeeController),
        _feeField(
          _t('screens_admin_customer_screen.045'),
          _withdrawFeeController,
        ),
        _feeField(
          _t('screens_admin_customer_screen.046'),
          _transferFeeController,
        ),
        _feeField(
          _t('screens_admin_customer_screen.047'),
          _redeemFeeController,
        ),
        _feeField(
          _t('screens_admin_customer_screen.048'),
          _resellFeeController,
        ),
        _feeField(
          _t('screens_admin_customer_screen.049'),
          _cardPrintRequestFeeController,
        ),
      ],
    );
  }

  Widget _buildPermissionsTab() {
    final perms = Map<String, dynamic>.from(
      _customer['permissions'] as Map? ?? {},
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: ShwakelCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('screens_admin_customer_screen.050'), style: AppTheme.h3),
              const SizedBox(height: 16),
              _permItem(
                _t('screens_admin_customer_screen.051'),
                'canIssueCards',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.052'),
                'canRequestCardPrinting',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.053'),
                'canIssueSubShekelCards',
                perms,
              ),
              _permItem(
                'إنشاء تذاكر دخول لمرة واحدة',
                'canIssueSingleUseTickets',
                perms,
              ),
              _permItem(
                'إنشاء تذاكر مواعيد',
                'canIssueAppointmentTickets',
                perms,
              ),
              _permItem('إنشاء تذاكر طوابير', 'canIssueQueueTickets', perms),
              _permItem(
                _t('screens_admin_customer_screen.054'),
                'canIssueHighValueCards',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.055'),
                'canResellCards',
                perms,
              ),
              _permItem(
                'استخدام بطاقات الدفع المسبق',
                'canUsePrepaidMultipayCards',
                perms,
              ),
              _permItem(
                'قبول دفع البطاقات المسبقة',
                'canAcceptPrepaidMultipayPayments',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.056'),
                'canManageCardPrintRequests',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.072'),
                'canOfflineCardScan',
                perms,
              ),
              _permItem(
                _t('screens_admin_customer_screen.078'),
                'canManageDebtBook',
                perms,
              ),
              if (widget.canManageUsers)
                _permItem(
                  _t('screens_admin_customer_screen.059'),
                  'canManageUsers',
                  perms,
                ),
              if (widget.canManageUsers)
                _permItem(
                  'شحن أرصدة المستخدمين من حساب المالية',
                  'canFinanceTopup',
                  perms,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('screens_admin_customer_screen.060'),
                    style: AppTheme.h3,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _maxDevicesController,
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_customer_screen.061'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShwakelButton(
                    label: _t('screens_admin_customer_screen.062'),
                    icon: Icons.phonelink_lock_rounded,
                    isSecondary: true,
                    onPressed: _saveDevicePolicy,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AdminSectionHeader(
              title: _t('screens_admin_customer_screen.063'),
              icon: Icons.smartphone_rounded,
            ),
            if (_devices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    context.loc.tr('screens_admin_customer_screen.070'),
                  ),
                ),
              )
            else
              ..._devices.map(_buildDeviceTile),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationTab() {
    final request = _verificationRequest;
    final isPending = request?['status']?.toString() == 'pending';
    final requestId = request?['id']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSectionHeader(
              title: 'توثيق الحساب',
              subtitle: 'مراجعة مرفقات الهوية والسيلفي الخاصة بهذا المستخدم',
              icon: Icons.verified_user_rounded,
              trailing: IconButton(
                tooltip: 'تحديث',
                onPressed: _busy ? null : () => _loadCustomer(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 16),
            if (request == null)
              ShwakelCard(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'لا يوجد طلب توثيق مرسل لهذا الحساب.',
                  style: AppTheme.bodyText,
                ),
              )
            else ...[
              ShwakelCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _verificationChip(
                          'الحالة',
                          _verificationStatusLabel(
                            request['status']?.toString() ?? '',
                          ),
                          Icons.fact_check_rounded,
                        ),
                        _verificationChip(
                          'النوع المطلوب',
                          request['requestedRoleLabel']?.toString() ?? '-',
                          Icons.badge_rounded,
                        ),
                        _verificationChip(
                          'رقم الهوية',
                          request['nationalId']?.toString() ?? '-',
                          Icons.credit_card_rounded,
                        ),
                        _verificationChip(
                          'تاريخ الميلاد',
                          request['birthDate']?.toString() ?? '-',
                          Icons.cake_rounded,
                        ),
                      ],
                    ),
                    if ((request['notes']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('ملاحظات المستخدم', style: AppTheme.bodyBold),
                      const SizedBox(height: 6),
                      Text(
                        request['notes'].toString(),
                        style: AppTheme.bodyText,
                      ),
                    ],
                    if (isPending) ...[
                      const SizedBox(height: 24),
                      ShwakelButton(
                        label: 'اعتماد التوثيق كمستخدم',
                        icon: Icons.verified_rounded,
                        onPressed: _busy ? null : _approveVerificationRequest,
                        isLoading: _busy,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'بعد الاعتماد يصبح الحساب موثقًا ونوع الحساب مستخدم، ويصل للمستخدم إشعار بإمكانية الترقية إلى تاجر أو سائق عبر التواصل.',
                        style: AppTheme.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final imageWidth = constraints.maxWidth < 760
                      ? double.infinity
                      : (constraints.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: imageWidth,
                        child: _verificationImageCard(
                          title: 'صورة الهوية',
                          url: requestId.isEmpty
                              ? ''
                              : _api
                                    .adminVerificationFileUri(
                                      requestId: requestId,
                                      fileType: 'identity',
                                    )
                                    .toString(),
                          fileType: 'identity',
                          icon: Icons.badge_outlined,
                        ),
                      ),
                      SizedBox(
                        width: imageWidth,
                        child: _verificationImageCard(
                          title: 'صورة السيلفي',
                          url: requestId.isEmpty
                              ? ''
                              : _api
                                    .adminVerificationFileUri(
                                      requestId: requestId,
                                      fileType: 'selfie',
                                    )
                                    .toString(),
                          fileType: 'selfie',
                          icon: Icons.face_retouching_natural_rounded,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verificationChip(String label, String value, IconData icon) {
    return Container(
      width: AppTheme.isPhone(context) ? double.infinity : 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 2),
                Text(value, style: AppTheme.bodyBold),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationImageCard({
    required String title,
    required String url,
    required String fileType,
    required IconData icon,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title, style: AppTheme.bodyBold),
              const Spacer(),
              IconButton(
                tooltip: 'تحميل الملف',
                onPressed: url.isEmpty
                    ? null
                    : () => _downloadVerificationFile(fileType, title),
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: url.isEmpty
                  ? Container(
                      color: AppTheme.surfaceVariant,
                      alignment: Alignment.center,
                      child: Text('لا توجد صورة', style: AppTheme.caption),
                    )
                  : InkWell(
                      onTap: () => _openVerificationImage(title, url),
                      child: Image.network(
                        url,
                        headers: _verificationImageHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppTheme.surfaceVariant,
                          alignment: Alignment.center,
                          child: Text(
                            'تعذر تحميل الصورة',
                            style: AppTheme.caption,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _verificationStatusLabel(String status) {
    return switch (status) {
      'pending' => 'قيد المراجعة',
      'approved' => 'معتمد',
      'rejected' => 'مرفوض',
      'replaced' => 'مستبدل',
      _ => 'غير موثق',
    };
  }

  void _openVerificationImage(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: AppTheme.bodyBold)),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    headers: _verificationImageHeaders,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'تعذر تحميل الصورة',
                        style: AppTheme.bodyText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadVerificationFile(String fileType, String title) async {
    final requestId = _verificationRequest?['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      await _api.downloadAdminVerificationFile(
        requestId: requestId,
        fileType: fileType,
        fileName: fileType == 'selfie'
            ? 'verification_selfie_$requestId'
            : 'verification_identity_$requestId',
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message: 'تم تحميل ملف $title بنجاح.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _buildDeviceTile(Map<String, dynamic> d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d['deviceName'] ?? _t('screens_admin_customer_screen.064'),
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 4),
                Text(
                  context.loc.tr(
                    'screens_admin_customer_screen.071',
                    params: {'id': d['deviceId']?.toString() ?? '-'},
                  ),
                  style: AppTheme.caption,
                ),
              ],
            );
            final deleteButton = IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.error,
              ),
              onPressed: () => _releaseDevice(d),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.smartphone_rounded,
                        color: d['isActiveDevice'] == true
                            ? AppTheme.success
                            : AppTheme.textTertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: info),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: deleteButton),
                ],
              );
            }

            return Row(
              children: [
                Icon(
                  Icons.smartphone_rounded,
                  color: d['isActiveDevice'] == true
                      ? AppTheme.success
                      : AppTheme.textTertiary,
                ),
                const SizedBox(width: 16),
                Expanded(child: info),
                deleteButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String val,
    IconData icon,
    Color color,
  ) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: AppTheme.caption),
          Text(val, style: AppTheme.h3),
        ],
      ),
    );
  }

  Widget _infoRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l, style: AppTheme.bodyAction),
              const SizedBox(height: 6),
              Text(v, style: AppTheme.bodyBold),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(l, style: AppTheme.bodyAction)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                v,
                style: AppTheme.bodyBold,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _feeField(String l, TextEditingController c) => SizedBox(
    width: AppTheme.isPhone(context) ? double.infinity : 140,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: l, suffixText: '%'),
    ),
  );

  Widget _permItem(String l, String k, Map<String, dynamic> p) =>
      SwitchListTile(
        title: Text(l, style: AppTheme.bodyText),
        value: p[k] == true,
        onChanged: (v) async {
          p[k] = v;
          await _savePermissions(p);
        },
        activeThumbColor: AppTheme.primary,
        contentPadding: EdgeInsets.zero,
      );

  Future<void> _savePermissions(Map<String, dynamic> p) async {
    setState(() => _busy = true);
    try {
      final res = await _api.updateAdminUserCardPermissions(
        userId: _customer['id'].toString(),
        canIssueCards: p['canIssueCards'] == true,
        canIssueSubShekelCards: p['canIssueSubShekelCards'] == true,
        canIssueHighValueCards: p['canIssueHighValueCards'] == true,
        canIssuePrivateCards: p['canIssuePrivateCards'] == true,
        canIssueSingleUseTickets: p['canIssueSingleUseTickets'] == true,
        canIssueAppointmentTickets: p['canIssueAppointmentTickets'] == true,
        canIssueQueueTickets: p['canIssueQueueTickets'] == true,
        canResellCards: p['canResellCards'] == true,
        canRequestCardPrinting: p['canRequestCardPrinting'] == true,
        canManageCardPrintRequests: p['canManageCardPrintRequests'] == true,
        canOfflineCardScan: p['canOfflineCardScan'] == true,
        canManageDebtBook: p['canManageDebtBook'] == true,
        canManageUsers: p['canManageUsers'] == true,
        canFinanceTopup: p['canFinanceTopup'] == true,
        canUsePrepaidMultipayCards: p['canUsePrepaidMultipayCards'] == true,
        canAcceptPrepaidMultipayPayments:
            p['canAcceptPrepaidMultipayPayments'] == true,
      );
      setState(() {
        _customer = Map<String, dynamic>.from(res['user']);
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDevicePolicy() async {
    setState(() => _busy = true);
    try {
      final max = int.tryParse(_maxDevicesController.text) ?? 1;
      final res = await _api.updateAdminUserDevicePolicy(
        userId: _customer['id'].toString(),
        allowMultiDevice: max > 1,
        maxDevices: max,
      );
      setState(() {
        _customer = Map<String, dynamic>.from(res['user']);
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _releaseDevice(Map<String, dynamic> d) async {
    try {
      await _api.releaseAdminUserDevice(
        userId: _customer['id'].toString(),
        deviceRecordId: d['id'].toString(),
      );
      _loadCustomer();
    } catch (_) {}
  }

  Future<void> _approveVerificationRequest() async {
    final requestId = _verificationRequest?['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      final response = await _api.approvePendingVerificationRequest(
        requestId,
        notes: 'تم اعتماد التوثيق من صفحة المستخدم.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (response['user'] is Map) {
          _customer = Map<String, dynamic>.from(response['user'] as Map);
        }
        _busy = false;
        _syncFields();
      });
      await _loadCustomer();
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ?? 'تم اعتماد توثيق الحساب بنجاح.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }
}
