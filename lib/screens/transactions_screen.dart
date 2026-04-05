import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/app_sidebar.dart';
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

      if (!mounted) return;

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
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _showMessage(
        'تعذر تحميل سجل الحركات: ${ErrorMessageService.sanitize(error)}',
        isError: true,
      );
    }
  }

  Future<void> _showMessage(String text, {bool isError = false}) {
    return isError
        ? AppAlertService.showError(context, title: 'خطأ', message: text)
        : AppAlertService.showSuccess(context, title: 'نجاح', message: text);
  }

  Future<void> _exportTransactions() async {
    if (_transactions.isEmpty) {
      await _showMessage('لا توجد حركات متاحة للتصدير حاليًا.', isError: true);
      return;
    }
    try {
      await _apiService.exportMyTransactionsCsv(transactions: _transactions);
      if (!mounted) return;
      await _showMessage('تم تصدير سجل الحركات بنجاح.');
    } catch (error) {
      if (!mounted) return;
      await _showMessage(
        'تعذر تصدير الحركات: ${ErrorMessageService.sanitize(error)}',
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
      appBar: AppBar(title: const Text('سجل الحركات')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadTransactions,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ResponsiveScaffoldContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroCard(),
                const SizedBox(height: 24),
                _buildSummaryRow(),
                const SizedBox(height: 24),
                _buildQuickActions(),
                const SizedBox(height: 24),
                _buildSearchAndFilters(),
                const SizedBox(height: 32),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 42),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كشف الحساب',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'راجع الحركات وابحث فيها بسرعة.',
                  style: AppTheme.bodyAction.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final net = _totalCredits - _totalDebits;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('الرصيد الحالي', _currentBalance, AppTheme.primary),
        _buildSummaryCard('إجمالي الإضافات', _totalCredits, AppTheme.success),
        _buildSummaryCard('إجمالي الخصومات', _totalDebits, AppTheme.error),
        _buildSummaryCard(
          'صافي الفترة',
          net,
          net >= 0 ? AppTheme.primary : AppTheme.error,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return SizedBox(
      width: 240,
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        shadowLevel: ShwakelShadowLevel.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.ils(amount),
              style: AppTheme.h3.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ShwakelButton(
          label: 'تحديث السجل',
          icon: Icons.refresh_rounded,
          isSecondary: true,
          width: 180,
          onPressed: _loadTransactions,
        ),
        ShwakelButton(
          label: 'تصدير CSV',
          icon: Icons.download_rounded,
          isSecondary: true,
          width: 180,
          onPressed: _exportTransactions,
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
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
                    Text('البحث والفلاتر', style: AppTheme.h3),
                    const SizedBox(height: 4),
                    Text(
                      'رتب الحركات كما تريد عبر البحث والفترة والموقع.',
                      style: AppTheme.bodyAction.copyWith(height: 1.45),
                    ),
                  ],
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
            decoration: const InputDecoration(
              labelText: 'البحث في الحركات',
              hintText: 'ابحث بالوصف أو البطاقة أو نوع الحركة',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 860;
              if (isCompact) {
                return Column(
                  children: [
                    _buildFilterPanel(
                      title: 'الفترة الزمنية',
                      icon: Icons.calendar_month_rounded,
                      chips: [
                        _buildDateChip('الكل', _TransactionDateFilter.all),
                        _buildDateChip('اليوم', _TransactionDateFilter.today),
                        _buildDateChip(
                          'آخر 7 أيام',
                          _TransactionDateFilter.last7Days,
                        ),
                        _buildDateChip(
                          'هذا الشهر',
                          _TransactionDateFilter.thisMonth,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildFilterPanel(
                      title: 'الموقع والنوع',
                      icon: Icons.filter_alt_rounded,
                      chips: [
                        _buildAuditChip('الكل', _TransactionAuditFilter.all),
                        _buildAuditChip(
                          'قرب فرع',
                          _TransactionAuditFilter.nearBranch,
                        ),
                        _buildAuditChip(
                          'خارج الفروع',
                          _TransactionAuditFilter.outsideBranches,
                        ),
                        _buildAuditChip(
                          'دين الطباعة',
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
                      title: 'الفترة الزمنية',
                      icon: Icons.calendar_month_rounded,
                      chips: [
                        _buildDateChip('الكل', _TransactionDateFilter.all),
                        _buildDateChip('اليوم', _TransactionDateFilter.today),
                        _buildDateChip(
                          'آخر 7 أيام',
                          _TransactionDateFilter.last7Days,
                        ),
                        _buildDateChip(
                          'هذا الشهر',
                          _TransactionDateFilter.thisMonth,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildFilterPanel(
                      title: 'الموقع والنوع',
                      icon: Icons.filter_alt_rounded,
                      chips: [
                        _buildAuditChip('الكل', _TransactionAuditFilter.all),
                        _buildAuditChip(
                          'قرب فرع',
                          _TransactionAuditFilter.nearBranch,
                        ),
                        _buildAuditChip(
                          'خارج الفروع',
                          _TransactionAuditFilter.outsideBranches,
                        ),
                        _buildAuditChip(
                          'دين الطباعة',
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
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 64,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 24),
            Text('لا توجد حركات متاحة', style: AppTheme.h3),
            const SizedBox(height: 8),
            Text(
              'جرّب تغيير البحث أو الفلاتر المختارة.',
              style: AppTheme.bodyText,
            ),
          ],
        ),
      ),
    );
  }
}

enum _TransactionAuditFilter { all, nearBranch, outsideBranches, printingDebt }

enum _TransactionDateFilter { all, today, last7Days, thisMonth }
