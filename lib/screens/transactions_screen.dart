import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _transactions = const [];
  double _currentBalance = 0;
  double _totalCredits = 0;
  double _totalDebits = 0;
  bool _isLoading = true;
  _TransactionAuditFilter _auditFilter = _TransactionAuditFilter.all;
  _TransactionDateFilter _dateFilter = _TransactionDateFilter.all;
  int _page = 1;
  static const int _perPage = 10;
  int _lastPage = 1;
  int _totalTransactions = 0;
  Timer? _searchDebounce;
  bool _showSearchAndFilters = false;

  String _t(String key) => context.loc.tr(key);

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

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _apiService.getMyTransactions(
        locationFilter: _apiLocationFilterValue,
        query: _searchController.text,
        dateFilter: _apiDateFilterValue,
        printingDebtOnly: _auditFilter == _TransactionAuditFilter.printingDebt,
        page: _page,
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

      if (!mounted) {
        return;
      }

      setState(() {
        _transactions = transactions;
        _currentBalance = (summary['currentBalance'] as num?)?.toDouble() ?? 0;
        _totalCredits = (summary['totalCredits'] as num?)?.toDouble() ?? 0;
        _totalDebits = (summary['totalDebits'] as num?)?.toDouble() ?? 0;
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _totalTransactions =
            (pagination['total'] as num?)?.toInt() ?? _transactions.length;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await _showMessage(
        '${_t('screens_transactions_screen.001')}: ${ErrorMessageService.sanitize(error)}',
        isError: true,
      );
    }
  }

  Future<void> _showMessage(String text, {bool isError = false}) {
    return isError
        ? AppAlertService.showError(
            context,
            title: _t('screens_transactions_screen.002'),
            message: text,
          )
        : AppAlertService.showSuccess(
            context,
            title: _t('screens_transactions_screen.003'),
            message: text,
          );
  }

  Future<void> _exportTransactions() async {
    if (_transactions.isEmpty) {
      await _showMessage(
        _t(
          'لا توجد حركات متاحة للتصدير حاليًا.',
          'There are no transactions available for export right now.',
        ),
        isError: true,
      );
      return;
    }
    try {
      await _apiService.exportMyTransactionsCsv(transactions: _transactions);
      if (!mounted) {
        return;
      }
      await _showMessage(
        _t(
          'تم تصدير سجل الحركات بنجاح.',
          'Transaction history exported successfully.',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showMessage(
        '${_t('screens_transactions_screen.004')}: ${ErrorMessageService.sanitize(error)}',
        isError: true,
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_t('screens_transactions_screen.005')),
        actions: [
          IconButton(
            tooltip: _showSearchAndFilters
                ? context.loc.tr('screens_transactions_screen.036')
                : context.loc.tr('screens_transactions_screen.037'),
            onPressed: () =>
                setState(() => _showSearchAndFilters = !_showSearchAndFilters),
            icon: Icon(
              _showSearchAndFilters
                  ? Icons.filter_alt_off_rounded
                  : Icons.filter_alt_rounded,
            ),
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
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: AppTheme.pagePadding(context, top: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 860;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showSearchAndFilters) ...[
                      _buildSearchAndFilters(isCompact: isCompact),
                      const SizedBox(height: 16),
                    ] else ...[
                      ToolToggleHint(
                        message: context.loc.tr(
                          'screens_transactions_screen.038',
                        ),
                        icon: Icons.filter_alt_rounded,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildCompactSummary(),
                    const SizedBox(height: 20),
                    _buildResultsHeading(),
                    const SizedBox(height: 14),
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

  Widget _buildCompactSummary() {
    final net = _totalCredits - _totalDebits;
    return Text(
      context.loc.tr(
        'screens_transactions_screen.041',
        params: {
          'balance': CurrencyFormatter.ils(_currentBalance),
          'in': CurrencyFormatter.ils(_totalCredits),
          'out': CurrencyFormatter.ils(_totalDebits),
          'net': CurrencyFormatter.ils(net),
        },
      ),
      style: AppTheme.caption,
    );
  }

  Widget _buildSearchAndFilters({required bool isCompact}) {
    return ShwakelCard(
      padding: EdgeInsets.all(isCompact ? 18 : 24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.tune_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('screens_transactions_screen.013'),
                      style: AppTheme.h3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        'نظّم حركاتك باستخدام البحث والنطاق الزمني وفلاتر الموقع.',
                        'Organize your transactions using search, date range, and location filters.',
                      ),
                      style: AppTheme.bodyAction.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterHintPill(
                icon: Icons.manage_search_rounded,
                label: context.loc.tr('screens_transactions_screen.042'),
              ),
              _filterHintPill(
                icon: Icons.calendar_today_rounded,
                label: context.loc.tr('screens_transactions_screen.043'),
              ),
              _filterHintPill(
                icon: Icons.verified_user_outlined,
                label: context.loc.tr('screens_transactions_screen.044'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: isCompact ? double.infinity : 180,
                child: ShwakelButton(
                  label: _t('screens_transactions_screen.011'),
                  icon: Icons.refresh_rounded,
                  isSecondary: true,
                  onPressed: _loadTransactions,
                ),
              ),
              SizedBox(
                width: isCompact ? double.infinity : 180,
                child: ShwakelButton(
                  label: _t('screens_transactions_screen.012'),
                  icon: Icons.download_rounded,
                  isSecondary: true,
                  onPressed: _exportTransactions,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                if (!mounted) return;
                setState(() => _page = 1);
                _loadTransactions();
              });
            },
            decoration: InputDecoration(
              labelText: _t('screens_transactions_screen.014'),
              hintText: _t(
                'ابحث بالوصف أو البطاقة أو نوع الحركة',
                'Search by description, card, or transaction type',
              ),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final filtersCompact = constraints.maxWidth < 860;
              if (filtersCompact) {
                return Column(
                  children: [
                    _buildFilterPanel(
                      title: _t('screens_transactions_screen.015'),
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
                    const SizedBox(height: 14),
                    _buildFilterPanel(
                      title: _t('screens_transactions_screen.020'),
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
                      title: _t('screens_transactions_screen.025'),
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
                      title: _t('screens_transactions_screen.030'),
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

  Widget _buildFilterPanel({
    required String title,
    required IconData icon,
    required List<Widget> chips,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
      _loadTransactions();
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
        _loadTransactions();
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
      padding: const EdgeInsets.all(36),
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
              _t(
                'جرّب تغيير نص البحث أو الفلاتر المحددة.',
                'Try changing the search text or selected filters.',
              ),
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

  Widget _buildResultsHeading() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.loc.tr('screens_transactions_screen.045'),
                style: AppTheme.h2.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 4),
              Text(
                _isLoading
                    ? context.loc.tr('screens_transactions_screen.046')
                    : context.loc.tr(
                        'screens_transactions_screen.047',
                        params: {'count': '$_totalTransactions'},
                      ),
                style: AppTheme.caption.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
        if (!_isLoading && _transactions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_transactions.length} في هذه الصفحة',
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _filterHintPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TransactionAuditFilter { all, nearBranch, outsideBranches, printingDebt }

enum _TransactionDateFilter { all, today, last7Days, thisMonth }
