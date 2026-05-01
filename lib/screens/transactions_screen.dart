import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _transactions = const [];
  double _currentBalance = 0;
  double _totalCredits = 0;
  double _totalDebits = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  _TransactionAuditFilter _auditFilter = _TransactionAuditFilter.all;
  _TransactionDateFilter _dateFilter = _TransactionDateFilter.all;
  int _page = 1;
  static const int _perPage = 10;
  int _lastPage = 1;
  int _totalTransactions = 0;
  Timer? _searchDebounce;
  int _loadRequestId = 0;
  String _lastSubmittedQuery = '';
  bool _isAuthorized = true;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions({bool preserveContent = false}) async {
    final currentUser = await _authService.currentUser();
    if (!AppPermissions.fromUser(currentUser).canViewTransactions) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = false;
        _transactions = const [];
        _isLoading = false;
        _isRefreshing = false;
      });
      return;
    }

    final requestId = ++_loadRequestId;
    final shouldKeepVisible = preserveContent && _transactions.isNotEmpty;
    setState(() {
      if (shouldKeepVisible) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });
    final requestedPage = _page;
    try {
      final payload = await _apiService.getMyTransactions(
        locationFilter: _apiLocationFilterValue,
        query: _searchController.text.trim(),
        dateFilter: _apiDateFilterValue,
        printingDebtOnly: _auditFilter == _TransactionAuditFilter.printingDebt,
        page: requestedPage,
        perPage: _perPage,
      );
      final summary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      final transactions = List<Map<String, dynamic>>.from(
        (payload['transactions'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage);

      if (requestedPage > lastPage && lastPage > 0) {
        if (!mounted) {
          return;
        }
        setState(() => _page = lastPage);
        await _loadTransactions();
        return;
      }

      if (!mounted || requestId != _loadRequestId) {
        return;
      }

      setState(() {
        _isAuthorized = true;
        _transactions = transactions;
        _currentBalance = (summary['currentBalance'] as num?)?.toDouble() ?? 0;
        _totalCredits = (summary['totalCredits'] as num?)?.toDouble() ?? 0;
        _totalDebits = (summary['totalDebits'] as num?)?.toDouble() ?? 0;
        _page = normalizedPage;
        _lastPage = lastPage;
        _totalTransactions =
            (pagination['total'] as num?)?.toInt() ?? _transactions.length;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      await _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        title: _t('screens_transactions_screen.001'),
      );
    }
  }

  Future<void> _showMessage(
    String text, {
    bool isError = false,
    String? title,
  }) {
    return isError
        ? AppAlertService.showError(
            context,
            title: title ?? _t('screens_transactions_screen.002'),
            message: text,
          )
        : AppAlertService.showSuccess(
            context,
            title: title ?? _t('screens_transactions_screen.003'),
            message: text,
          );
  }

  Future<void> _exportTransactions() async {
    if (_transactions.isEmpty) {
      await _showMessage(_t('screens_transactions_screen.048'), isError: true);
      return;
    }
    try {
      await _apiService.exportMyTransactionsCsv(transactions: _transactions);
      if (!mounted) {
        return;
      }
      await _showMessage(_t('screens_transactions_screen.049'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        title: _t('screens_transactions_screen.004'),
      );
    }
  }

  String get _apiLocationFilterValue {
    return switch (_auditFilter) {
      _TransactionAuditFilter.nearBranch => 'near_branch',
      _TransactionAuditFilter.outsideBranches => 'outside_branches',
      _TransactionAuditFilter.printingDebt => 'all',
      _TransactionAuditFilter.all => 'all',
    };
  }

  String get _apiDateFilterValue {
    return switch (_dateFilter) {
      _TransactionDateFilter.today => 'today',
      _TransactionDateFilter.last7Days => 'last7days',
      _TransactionDateFilter.thisMonth => 'thismonth',
      _TransactionDateFilter.all => 'all',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && !_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_t('screens_transactions_screen.005')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: ResponsiveScaffoldContainer(
          child: Center(
            child: ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Text(
                _t('screens_transactions_screen.062'),
                style: AppTheme.bodyAction,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_t('screens_transactions_screen.005')),
        actions: [
          IconButton(
            tooltip: context.loc.tr('screens_transactions_screen.039'),
            onPressed: _showSummarySheet,
            icon: const Icon(Icons.dashboard_customize_rounded),
          ),
          IconButton(
            tooltip: context.loc.tr('screens_transactions_screen.037'),
            onPressed: _showFiltersSheet,
            icon: const Icon(Icons.filter_alt_rounded),
          ),
          IconButton(
            tooltip: _t('screens_transactions_screen.012'),
            onPressed: _exportTransactions,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: context.loc.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: ResponsiveScaffoldContainer(
          padding: AppTheme.pagePadding(context, top: 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 860;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildResultsHeading(isCompact: isCompact),
                  const SizedBox(height: 12),
                  if (_isRefreshing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_transactions.isEmpty)
                    _buildEmptyState()
                  else ...[
                    ..._transactions.map(
                      (tx) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AdminTransactionAuditCard(transaction: tx),
                      ),
                    ),
                    AdminPaginationFooter(
                      currentPage: _page,
                      lastPage: _lastPage,
                      totalItems: _totalTransactions,
                      itemsPerPage: _perPage,
                      onPageChanged: (page) {
                        setState(() => _page = page);
                        _loadTransactions();
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    await AppAlertService.showInfo(
      context,
      title: context.loc.tr('screens_transactions_screen.039'),
      message: context.loc.tr('screens_transactions_screen.040'),
    );
  }

  Future<void> _showSummarySheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(_t('screens_transactions_screen.039'), style: AppTheme.h2),
            const SizedBox(height: 8),
            Text(
              _t('screens_transactions_screen.050'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildHeaderCard(isCompact: true),
          ],
        ),
      ),
    );
  }

  Future<void> _showFiltersSheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(_t('screens_transactions_screen.037'), style: AppTheme.h2),
            const SizedBox(height: 8),
            Text(
              _t('screens_transactions_screen.053'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildSearchAndFilters(isCompact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard({required bool isCompact}) {
    final net = _totalCredits - _totalDebits;
    final summaryItems = [
      (
        label: _t('screens_transactions_screen.058'),
        value: CurrencyFormatter.ils(_currentBalance),
        icon: Icons.account_balance_wallet_rounded,
        color: AppTheme.primary,
      ),
      (
        label: _t('screens_transactions_screen.059'),
        value: CurrencyFormatter.ils(_totalCredits),
        icon: Icons.south_west_rounded,
        color: AppTheme.success,
      ),
      (
        label: _t('screens_transactions_screen.060'),
        value: CurrencyFormatter.ils(_totalDebits),
        icon: Icons.north_east_rounded,
        color: const Color(0xFFB45309),
      ),
      (
        label: _t('screens_transactions_screen.061'),
        value: CurrencyFormatter.ils(net),
        icon: Icons.analytics_rounded,
        color: const Color(0xFF7C3AED),
      ),
    ];

    return ShwakelCard(
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('screens_transactions_screen.005'),
            style: AppTheme.h2.copyWith(fontSize: isCompact ? 24 : 28),
          ),
          const SizedBox(height: 6),
          Text(
            _t('screens_transactions_screen.050'),
            style: AppTheme.bodyAction.copyWith(height: 1.35),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              context.loc.tr(
                'screens_transactions_screen.041',
                params: {
                  'balance': CurrencyFormatter.ils(_currentBalance),
                  'in': CurrencyFormatter.ils(_totalCredits),
                  'out': CurrencyFormatter.ils(_totalDebits),
                  'net': CurrencyFormatter.ils(net),
                },
              ),
              style: AppTheme.caption.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: summaryItems
                .map(
                  (item) => _buildStatChip(
                    label: item.label,
                    value: item.value,
                    icon: item.icon,
                    color: item.color,
                    compact: isCompact,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters({required bool isCompact}) {
    return ShwakelCard(
      padding: EdgeInsets.all(isCompact ? 14 : 18),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('screens_transactions_screen.054'),
            style: AppTheme.bodyBold.copyWith(
              color: AppTheme.primary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t('screens_transactions_screen.053'),
            style: AppTheme.caption.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 550), () {
                if (!mounted) return;
                _submitSearch();
              });
            },
            decoration: InputDecoration(
              labelText: _t('screens_transactions_screen.014'),
              hintText: _t('screens_transactions_screen.051'),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: isCompact ? double.infinity : 150,
                child: ShwakelButton(
                  label: _t('screens_transactions_screen.011'),
                  icon: Icons.refresh_rounded,
                  isSecondary: true,
                  onPressed: _loadTransactions,
                ),
              ),
              SizedBox(
                width: isCompact ? double.infinity : 150,
                child: ShwakelButton(
                  label: _t('screens_transactions_screen.012'),
                  icon: Icons.download_rounded,
                  isSecondary: true,
                  onPressed: _exportTransactions,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final filtersCompact = constraints.maxWidth < 860;
              if (filtersCompact) {
                return Column(
                  children: [
                    _buildFilterPanel(
                      title: _t('screens_transactions_screen.055'),
                      icon: Icons.calendar_month_rounded,
                      chips: [
                        _buildDateChip(
                          _t('screens_transactions_screen.016'),
                          _TransactionDateFilter.all,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.017'),
                          _TransactionDateFilter.today,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.018'),
                          _TransactionDateFilter.last7Days,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.019'),
                          _TransactionDateFilter.thisMonth,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFilterPanel(
                      title: _t('screens_transactions_screen.056'),
                      icon: Icons.filter_alt_rounded,
                      chips: [
                        _buildAuditChip(
                          _t('screens_transactions_screen.021'),
                          _TransactionAuditFilter.all,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.022'),
                          _TransactionAuditFilter.nearBranch,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.023'),
                          _TransactionAuditFilter.outsideBranches,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.024'),
                          _TransactionAuditFilter.printingDebt,
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildFilterPanel(
                      title: _t('screens_transactions_screen.055'),
                      icon: Icons.calendar_month_rounded,
                      chips: [
                        _buildDateChip(
                          _t('screens_transactions_screen.026'),
                          _TransactionDateFilter.all,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.027'),
                          _TransactionDateFilter.today,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.028'),
                          _TransactionDateFilter.last7Days,
                        ),
                        _buildDateChip(
                          _t('screens_transactions_screen.029'),
                          _TransactionDateFilter.thisMonth,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildFilterPanel(
                      title: _t('screens_transactions_screen.056'),
                      icon: Icons.filter_alt_rounded,
                      chips: [
                        _buildAuditChip(
                          _t('screens_transactions_screen.031'),
                          _TransactionAuditFilter.all,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.032'),
                          _TransactionAuditFilter.nearBranch,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.033'),
                          _TransactionAuditFilter.outsideBranches,
                        ),
                        _buildAuditChip(
                          _t('screens_transactions_screen.034'),
                          _TransactionAuditFilter.printingDebt,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query == _lastSubmittedQuery) {
      return;
    }
    _lastSubmittedQuery = query;
    setState(() => _page = 1);
    _loadTransactions(preserveContent: true);
  }

  Widget _buildFilterPanel({
    required String title,
    required IconData icon,
    required List<Widget> chips,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(20),
      color: AppTheme.surfaceVariant,
      shadowLevel: ShwakelShadowLevel.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.bodyBold.copyWith(
                  color: AppTheme.primary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, _TransactionDateFilter value) {
    return _buildChoiceChip<_TransactionDateFilter>(label, value, _dateFilter, (
      selected,
    ) {
      setState(() {
        _dateFilter = selected;
        _page = 1;
      });
      _loadTransactions(preserveContent: true);
    });
  }

  Widget _buildAuditChip(String label, _TransactionAuditFilter value) {
    return _buildChoiceChip<_TransactionAuditFilter>(
      label,
      value,
      _auditFilter,
      (selected) {
        setState(() {
          _auditFilter = selected;
          _page = 1;
        });
        _loadTransactions(preserveContent: true);
      },
    );
  }

  Widget _buildChoiceChip<T>(
    String label,
    T value,
    T current,
    ValueChanged<T> onSelected,
  ) {
    final isSelected = value == current;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (_) => onSelected(value),
      selectedColor: AppTheme.primary.withValues(alpha: 0.1),
      labelStyle: AppTheme.caption.copyWith(
        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      borderRadius: BorderRadius.circular(24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 42,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Text(_t('screens_transactions_screen.035'), style: AppTheme.h3),
            const SizedBox(height: 8),
            Text(
              _t('screens_transactions_screen.052'),
              style: AppTheme.bodyText,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: ShwakelButton(
                label: _t('screens_transactions_screen.011'),
                icon: Icons.refresh_rounded,
                isSecondary: true,
                onPressed: _loadTransactions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeading({required bool isCompact}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('screens_transactions_screen.005'),
                style: AppTheme.h2.copyWith(fontSize: isCompact ? 18 : 20),
              ),
              const SizedBox(height: 4),
              Text(
                _isLoading
                    ? context.loc.tr('screens_transactions_screen.046')
                    : context.loc.tr(
                        'screens_transactions_screen.047',
                        params: {'count': '$_totalTransactions'},
                      ),
                style: AppTheme.caption.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _showFiltersSheet,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: Text(_t('screens_transactions_screen.057')),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool compact,
  }) {
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 145 : 170),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTheme.bodyBold.copyWith(fontSize: 13, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _TransactionAuditFilter { all, nearBranch, outsideBranches, printingDebt }

enum _TransactionDateFilter { all, today, last7Days, thisMonth }
