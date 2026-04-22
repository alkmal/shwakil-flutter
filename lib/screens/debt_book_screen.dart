import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';
import 'debt_book_customer_screen.dart';

class DebtBookScreen extends StatefulWidget {
  const DebtBookScreen({super.key});

  @override
  State<DebtBookScreen> createState() => _DebtBookScreenState();
}

class _DebtBookScreenState extends State<DebtBookScreen> {
  final _auth = AuthService();
  final _api = ApiService();
  final _debtBook = DebtBookService();
  final _searchController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic> _snapshot = const {};
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _pendingOperations = const [];
  bool _loading = true;
  bool _syncing = false;
  _DebtCustomerFilter _activeFilter = _DebtCustomerFilter.all;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return _t('screens_debt_book_screen.001');
    }
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) {
      return raw;
    }
    return DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(parsed);
  }

  List<Map<String, dynamic>> _topDebtors() {
    final customers = List<Map<String, dynamic>>.from(_customers);
    customers.sort((a, b) {
      final aBalance = _remainingAmount(a);
      final bBalance = _remainingAmount(b);
      return bBalance.compareTo(aBalance);
    });
    return customers
        .where((customer) => _remainingAmount(customer) > 0)
        .take(3)
        .toList();
  }

  bool get _isOnline => ConnectivityService.instance.isOnline.value;

  double _remainingAmount(Map<String, dynamic>? customer) {
    if (customer == null) {
      return 0;
    }
    return (customer['remainingAmount'] as num?)?.toDouble() ??
        (customer['balance'] as num?)?.toDouble() ??
        0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool syncIfPossible = true}) async {
    final user = await _auth.currentUser();
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _loading = true;
    });

    if (user == null || user['id'] == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _snapshot = const {};
        _customers = const [];
      });
      return;
    }

    final userId = user['id'].toString();
    final localSnapshot = await _debtBook.getSnapshot(userId);
    final pendingOperations = await _debtBook.getPendingOperations(userId);
    if (!mounted) return;
    setState(() {
      _snapshot = localSnapshot;
      _pendingOperations = pendingOperations;
      _customers = _filterCustomers(
        localSnapshot,
        _searchController.text,
        _activeFilter,
      );
      _loading = false;
    });

    if (syncIfPossible && _isOnline) {
      await _syncAndRefresh(showErrors: false);
    }
  }

  Future<void> _syncAndRefresh({bool showErrors = true}) async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    if (!AppPermissions.fromUser(user).canManageDebtBook) {
      return;
    }
    if (!_isOnline) {
      if (showErrors && mounted) {
        await AppAlertService.showInfo(
          context,
          title: _t('screens_debt_book_screen.002'),
          message: _t('screens_debt_book_screen.003'),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _syncing = true);
    }
    try {
      final snapshot = await _debtBook.syncPending(
        userId: user['id'].toString(),
        api: _api,
      );
      final pendingOperations = await _debtBook.getPendingOperations(
        user['id'].toString(),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _pendingOperations = pendingOperations;
        _customers = _filterCustomers(
          snapshot,
          _searchController.text,
          _activeFilter,
        );
        _syncing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      if (showErrors) {
        await AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(e),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterCustomers(
    Map<String, dynamic> snapshot,
    String query,
    _DebtCustomerFilter filter,
  ) {
    final normalized = query.trim().toLowerCase();
    final customers = List<Map<String, dynamic>>.from(
      (snapshot['customers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return customers.where((customer) {
      final name = customer['fullName']?.toString().toLowerCase() ?? '';
      final phone = customer['phone']?.toString().toLowerCase() ?? '';
      final balance = _remainingAmount(customer);
      final matchesQuery =
          normalized.isEmpty ||
          name.contains(normalized) ||
          phone.contains(normalized);
      final matchesFilter = switch (filter) {
        _DebtCustomerFilter.all => true,
        _DebtCustomerFilter.debtors => balance > 0,
        _DebtCustomerFilter.settled => balance <= 0,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _openCustomer(Map<String, dynamic> customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DebtBookCustomerScreen(
          customerRef:
              customer['id']?.toString() ??
              customer['clientRef']?.toString() ??
              '',
        ),
      ),
    );
    await _load(syncIfPossible: false);
  }

  Future<void> _showCustomerDialog({Map<String, dynamic>? customer}) async {
    final nameController = TextEditingController(
      text: customer?['fullName']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: customer?['phone']?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: customer?['notes']?.toString() ?? '',
    );

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            customer == null
                ? _t('screens_debt_book_screen.004')
                : _t('screens_debt_book_screen.005'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_screen.006'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_screen.007'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_screen.008'),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('screens_debt_book_screen.009')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('screens_debt_book_screen.010')),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
      if (nameController.text.trim().isEmpty) {
        if (!mounted) return;
        await AppAlertService.showError(
          context,
          message: _t('screens_debt_book_screen.011'),
        );
        return;
      }

      final user = _user ?? await _auth.currentUser();
      if (user == null || user['id'] == null) {
        return;
      }

      await _debtBook.upsertCustomerLocally(
        userId: user['id'].toString(),
        customerRef:
            customer?['id']?.toString() ?? customer?['clientRef']?.toString(),
        fullName: nameController.text,
        phone: phoneController.text,
        notes: notesController.text,
      );
      await _load(syncIfPossible: false);
      if (_isOnline) {
        await _syncAndRefresh(showErrors: true);
      } else if (mounted) {
        await AppAlertService.showInfo(
          context,
          title: _t('screens_debt_book_screen.012'),
          message: _t('screens_debt_book_screen.013'),
        );
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _deleteCustomer(Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_debt_book_screen.014')),
        content: Text(
          _t(
            'screens_debt_book_screen.015',
            params: {'name': customer['fullName']?.toString() ?? '-'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('screens_debt_book_screen.009')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('screens_debt_book_screen.016')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }

    await _debtBook.deleteCustomerLocally(
      userId: user['id'].toString(),
      customerRef:
          customer['id']?.toString() ?? customer['clientRef']?.toString() ?? '',
    );
    await _load(syncIfPossible: false);
    if (_isOnline) {
      await _syncAndRefresh(showErrors: true);
    } else if (mounted) {
      await AppAlertService.showInfo(
        context,
        title: _t('screens_debt_book_screen.017'),
        message: _t('screens_debt_book_screen.018'),
      );
    }
  }

  bool _customerHasPendingChanges(Map<String, dynamic> customer) {
    final customerId = customer['id']?.toString() ?? '';
    final clientRef = customer['clientRef']?.toString() ?? '';
    for (final operation in _pendingOperations) {
      final entity = operation['entity']?.toString() ?? '';
      if (entity == 'customer') {
        final opServerId = operation['serverId']?.toString() ?? '';
        final opClientRef = operation['clientRef']?.toString() ?? '';
        if ((customerId.isNotEmpty && opServerId == customerId) ||
            (clientRef.isNotEmpty && opClientRef == clientRef) ||
            customerId.startsWith('local:')) {
          return true;
        }
      }
      if (entity == 'entry') {
        final opCustomerId = operation['customerId']?.toString() ?? '';
        final opCustomerClientRef =
            operation['customerClientRef']?.toString() ?? '';
        if ((customerId.isNotEmpty && opCustomerId == customerId) ||
            (clientRef.isNotEmpty && opCustomerClientRef == clientRef)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final permissions = AppPermissions.fromUser(_user);
    final summary = Map<String, dynamic>.from(
      _snapshot['summary'] as Map? ?? const {},
    );
    final lastSyncedAt = _formatDateTime(_snapshot['syncedAt']);
    final topDebtors = _topDebtors();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        drawer: const AppSidebar(),
        appBar: AppBar(
          title: Text(_t('screens_debt_book_screen.023')),
          actions: [
            IconButton(
              tooltip: _t('screens_debt_book_screen.019'),
              onPressed: _loading || _syncing ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: _t('screens_debt_book_screen.020'),
              onPressed: _syncing ? null : () => _syncAndRefresh(),
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isOnline
                          ? Icons.cloud_sync_rounded
                          : Icons.cloud_off_rounded,
                    ),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(76),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  tabs: [
                    Tab(
                      text: l.tr('screens_debt_book_screen.047'),
                      icon: const Icon(Icons.people_alt_rounded),
                    ),
                    Tab(
                      text: l.tr('screens_debt_book_screen.048'),
                      icon: const Icon(Icons.analytics_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: permissions.canManageDebtBook
            ? FloatingActionButton.extended(
                onPressed: () => _showCustomerDialog(),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_t('screens_debt_book_screen.021')),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : !permissions.canManageDebtBook
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_t('screens_debt_book_screen.022')),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => _load(),
                child: ResponsiveScaffoldContainer(
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  child: TabBarView(
                    children: [
                      _buildCustomersTab(lastSyncedAt),
                      _buildSummaryTab(summary, topDebtors, lastSyncedAt),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildOverviewStrip({
    required String lastSyncedAt,
    String? description,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      color: AppTheme.surface,
      withBorder: true,
      borderColor: AppTheme.borderLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description, style: AppTheme.bodyAction),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statusPill(
                icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                label: _isOnline
                    ? _t('screens_debt_book_screen.031')
                    : _t('screens_debt_book_screen.032'),
                color: _isOnline ? AppTheme.success : AppTheme.warning,
              ),
              _statusPill(
                icon: Icons.schedule_rounded,
                label: _t(
                  'screens_debt_book_screen.033',
                  params: {'date': lastSyncedAt},
                ),
                color: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersTab(String lastSyncedAt) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewStrip(
            lastSyncedAt: lastSyncedAt,
            description: _isOnline
                ? _t('screens_debt_book_screen.024')
                : _t('screens_debt_book_screen.025'),
          ),
          const SizedBox(height: 16),
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.surface,
            withBorder: true,
            borderColor: AppTheme.borderLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _customers = _filterCustomers(
                        _snapshot,
                        value,
                        _activeFilter,
                      );
                    });
                  },
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_screen.036'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _customers = _filterCustomers(
                                  _snapshot,
                                  '',
                                  _activeFilter,
                                );
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildFilterChip(
                      title: _t('screens_debt_book_screen.037'),
                      filter: _DebtCustomerFilter.all,
                    ),
                    _buildFilterChip(
                      title: _t('screens_debt_book_screen.038'),
                      filter: _DebtCustomerFilter.debtors,
                    ),
                    _buildFilterChip(
                      title: _t('screens_debt_book_screen.039'),
                      filter: _DebtCustomerFilter.settled,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_customers.isEmpty)
            ShwakelCard(
              padding: const EdgeInsets.all(28),
              color: AppTheme.surface,
              withBorder: true,
              borderColor: AppTheme.borderLight,
              child: Center(child: Text(_t('screens_debt_book_screen.040'))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _customers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final customer = _customers[index];
                final balance = _remainingAmount(customer);
                return ShwakelCard(
                  onTap: () => _openCustomer(customer),
                  padding: const EdgeInsets.all(18),
                  color: AppTheme.surface,
                  withBorder: true,
                  borderColor: AppTheme.borderLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            child: Text(
                              (customer['fullName']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ??
                                      false)
                                  ? customer['fullName']
                                        .toString()
                                        .trim()
                                        .characters
                                        .first
                                  : _t('screens_debt_book_screen.041'),
                              style: AppTheme.bodyBold.copyWith(
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer['fullName']?.toString() ?? '-',
                                  style: AppTheme.bodyBold,
                                ),
                                const SizedBox(height: 4),
                                if (_customerHasPendingChanges(customer)) ...[
                                  _pendingBadge(),
                                  const SizedBox(height: 4),
                                ],
                                Text(
                                  customer['phone']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? customer['phone'].toString()
                                      : _t('screens_debt_book_screen.035'),
                                  style: AppTheme.caption,
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(_t('screens_debt_book_screen.042')),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(_t('screens_debt_book_screen.014')),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showCustomerDialog(customer: customer);
                              } else if (value == 'delete') {
                                _deleteCustomer(customer);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _smallSummary(
                              _t('screens_debt_book_screen.043'),
                              CurrencyFormatter.ils(
                                (customer['totalDebt'] as num?)?.toDouble() ??
                                    0,
                              ),
                              AppTheme.error,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _smallSummary(
                              _t('screens_debt_book_screen.029'),
                              CurrencyFormatter.ils(
                                (customer['totalPaid'] as num?)?.toDouble() ??
                                    0,
                              ),
                              AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _smallSummary(
                              _t('screens_debt_book_screen.044'),
                              CurrencyFormatter.ils(balance),
                              balance > 0 ? AppTheme.warning : AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          'screens_debt_book_screen.045',
                          params: {
                            'date': _formatDateTime(customer['lastEntryAt']),
                          },
                        ),
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> topDebtors,
    String lastSyncedAt,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewStrip(
            lastSyncedAt: lastSyncedAt,
            description: 'ملخص سريع ومباشر لدفتر الديون بدون تعقيد في العرض.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _metricCard(
                _t('screens_debt_book_screen.026'),
                '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                Icons.people_alt_rounded,
                AppTheme.primary,
              ),
              _metricCard(
                _t('screens_debt_book_screen.027'),
                '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                Icons.warning_amber_rounded,
                AppTheme.warning,
              ),
              _metricCard(
                _t('screens_debt_book_screen.028'),
                CurrencyFormatter.ils(
                  (summary['totalDebt'] as num?)?.toDouble() ?? 0,
                ),
                Icons.arrow_upward_rounded,
                AppTheme.error,
              ),
              _metricCard(
                _t('screens_debt_book_screen.029'),
                CurrencyFormatter.ils(
                  (summary['totalPaid'] as num?)?.toDouble() ?? 0,
                ),
                Icons.arrow_downward_rounded,
                AppTheme.success,
              ),
              _metricCard(
                _t('screens_debt_book_screen.030'),
                '${_pendingOperations.length}',
                Icons.sync_problem_rounded,
                _pendingOperations.isEmpty
                    ? AppTheme.primary
                    : AppTheme.warning,
              ),
            ],
          ),
          if (topDebtors.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(_t('screens_debt_book_screen.034'), style: AppTheme.h3),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: topDebtors.map((customer) {
                final balance = _remainingAmount(customer);
                return SizedBox(
                  width: 260,
                  child: ShwakelCard(
                    onTap: () => _openCustomer(customer),
                    padding: const EdgeInsets.all(16),
                    color: AppTheme.surface,
                    withBorder: true,
                    borderColor: AppTheme.borderLight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer['fullName']?.toString() ?? '-',
                          style: AppTheme.bodyBold,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          customer['phone']?.toString().trim().isNotEmpty ==
                                  true
                              ? customer['phone'].toString()
                              : _t('screens_debt_book_screen.035'),
                          style: AppTheme.caption,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          CurrencyFormatter.ils(balance),
                          style: AppTheme.bodyBold.copyWith(
                            color: AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        color: AppTheme.surface,
        withBorder: true,
        borderColor: AppTheme.borderLight,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.caption),
                  const SizedBox(height: 4),
                  Text(value, style: AppTheme.bodyBold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallSummary(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.caption),
          const SizedBox(height: 6),
          Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String title,
    required _DebtCustomerFilter filter,
  }) {
    return ChoiceChip(
      label: Text(title),
      selected: _activeFilter == filter,
      onSelected: (_) {
        setState(() {
          _activeFilter = filter;
          _customers = _filterCustomers(
            _snapshot,
            _searchController.text,
            _activeFilter,
          );
        });
      },
    );
  }

  Widget _pendingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _t('screens_debt_book_screen.046'),
        style: AppTheme.caption.copyWith(
          color: AppTheme.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statusPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DebtCustomerFilter { all, debtors, settled }
