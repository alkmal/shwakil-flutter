import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';
import 'debt_book_customer_screen.dart';

class AdminDebtBookScreen extends StatefulWidget {
  const AdminDebtBookScreen({super.key});

  @override
  State<AdminDebtBookScreen> createState() => _AdminDebtBookScreenState();
}

class _AdminDebtBookScreenState extends State<AdminDebtBookScreen> {
  final _authService = AuthService();
  final _apiService = ApiService();
  final _debtBookService = DebtBookService();
  final _searchController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic> _snapshot = const {};
  List<Map<String, dynamic>> _customers = const [];
  bool _loading = true;
  bool _syncing = false;
  bool _showFilters = false;
  _AdminDebtFilter _filter = _AdminDebtFilter.all;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

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

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return _t('screens_admin_debt_book_screen.001');
    }
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) {
      return raw;
    }
    return DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(parsed);
  }

  Future<void> _ensurePdfFonts() async {
    _pdfRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _pdfBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
  }

  List<Map<String, dynamic>> _sortedCustomers() {
    final customers = List<Map<String, dynamic>>.from(
      (_snapshot['customers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    customers.sort((a, b) {
      final aBalance = _remainingAmount(a);
      final bBalance = _remainingAmount(b);
      return bBalance.compareTo(aBalance);
    });
    return customers;
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> customers,
    String query,
    _AdminDebtFilter filter,
  ) {
    final normalized = query.trim().toLowerCase();
    return customers.where((customer) {
      final name = UserDisplayName.fromMap(customer).toLowerCase();
      final phone = customer['phone']?.toString().toLowerCase() ?? '';
      final balance = _remainingAmount(customer);
      final matchesQuery =
          normalized.isEmpty ||
          name.contains(normalized) ||
          phone.contains(normalized);
      final matchesFilter = switch (filter) {
        _AdminDebtFilter.all => true,
        _AdminDebtFilter.debtors => balance > 0,
        _AdminDebtFilter.settled => balance <= 0,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _load({bool syncIfPossible = true}) async {
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _loading = true;
    });

    if (user == null || user['id'] == null) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      return;
    }

    final userId = user['id'].toString();
    final localSnapshot = await _debtBookService.getSnapshot(userId);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = localSnapshot;
      _customers = _applyFilters(
        _sortedCustomers(),
        _searchController.text,
        _filter,
      );
      _loading = false;
    });

    if (syncIfPossible && _isOnline) {
      await _syncAndRefresh(showErrors: false);
    }
  }

  Future<void> _syncAndRefresh({bool showErrors = true}) async {
    final user = _user ?? await _authService.currentUser();
    if (user == null || user['id'] == null || !_isOnline) {
      return;
    }
    if (mounted) {
      setState(() => _syncing = true);
    }
    try {
      final snapshot = await _debtBookService.syncPending(
        userId: user['id'].toString(),
        api: _apiService,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _customers = _applyFilters(
          _sortedCustomers(),
          _searchController.text,
          _filter,
        );
        _syncing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _syncing = false);
      if (showErrors) {
        await AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    }
  }

  String _buildReportText() {
    final summary = Map<String, dynamic>.from(
      _snapshot['summary'] as Map? ?? const {},
    );
    final debtors = _customers
        .where((customer) => _remainingAmount(customer) > 0)
        .toList();
    final buffer = StringBuffer();
    buffer.writeln(_t('screens_admin_debt_book_screen.002'));
    buffer.writeln(
      _t(
        'screens_admin_debt_book_screen.003',
        params: {
          'count': '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
        },
      ),
    );
    buffer.writeln(
      _t(
        'screens_admin_debt_book_screen.004',
        params: {
          'count': '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
        },
      ),
    );
    buffer.writeln(
      _t(
        'screens_admin_debt_book_screen.005',
        params: {
          'amount': CurrencyFormatter.ils(
            (summary['totalDebt'] as num?)?.toDouble() ?? 0,
          ),
        },
      ),
    );
    buffer.writeln(
      _t(
        'screens_admin_debt_book_screen.006',
        params: {
          'amount': CurrencyFormatter.ils(
            (summary['totalPaid'] as num?)?.toDouble() ?? 0,
          ),
        },
      ),
    );
    buffer.writeln(
      _t(
        'screens_admin_debt_book_screen.007',
        params: {'date': _formatDateTime(_snapshot['syncedAt'])},
      ),
    );
    buffer.writeln('');
    buffer.writeln(_t('screens_admin_debt_book_screen.008'));
    if (debtors.isEmpty) {
      buffer.writeln(_t('screens_admin_debt_book_screen.009'));
    } else {
      for (final customer in debtors) {
        final phone = customer['phone']?.toString().trim() ?? '';
        buffer.writeln(
          _t(
            'screens_admin_debt_book_screen.010',
            params: {
              'name': UserDisplayName.fromMap(customer, fallback: '-'),
              'phone': phone.isNotEmpty
                  ? phone
                  : _t('screens_admin_debt_book_screen.016'),
              'amount': CurrencyFormatter.ils(_remainingAmount(customer)),
            },
          ),
        );
      }
    }
    return buffer.toString();
  }

  Future<pw.Document> _buildReportPdf() async {
    await _ensurePdfFonts();
    if (!mounted) {
      return pw.Document();
    }
    final l = context.loc;
    final summary = Map<String, dynamic>.from(
      _snapshot['summary'] as Map? ?? const {},
    );
    final debtors = _customers
        .where((customer) => _remainingAmount(customer) > 0)
        .toList();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(
            base: _pdfRegularFont!,
            bold: _pdfBoldFont!,
          ),
        ),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  l.tr('screens_admin_debt_book_screen.011'),
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        l.tr(
                          'screens_admin_debt_book_screen.003',
                          params: {
                            'count':
                                '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_debt_book_screen.004',
                          params: {
                            'count':
                                '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_debt_book_screen.005',
                          params: {
                            'amount': CurrencyFormatter.ils(
                              (summary['totalDebt'] as num?)?.toDouble() ?? 0,
                            ),
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_debt_book_screen.006',
                          params: {
                            'amount': CurrencyFormatter.ils(
                              (summary['totalPaid'] as num?)?.toDouble() ?? 0,
                            ),
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_debt_book_screen.007',
                          params: {
                            'date': _formatDateTime(_snapshot['syncedAt']),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                if (debtors.isEmpty)
                  pw.Text(l.tr('screens_admin_debt_book_screen.009'))
                else
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: _pdfBoldFont),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellAlignment: pw.Alignment.centerRight,
                    headers: [
                      l.tr('screens_admin_debt_book_screen.012'),
                      l.tr('screens_admin_debt_book_screen.013'),
                      l.tr('screens_admin_debt_book_screen.014'),
                      l.tr('screens_admin_debt_book_screen.015'),
                    ],
                    data: debtors.map((customer) {
                      final phone = customer['phone']?.toString().trim() ?? '';
                      return [
                        UserDisplayName.fromMap(customer, fallback: '-'),
                        phone.isNotEmpty
                            ? phone
                            : l.tr('screens_admin_debt_book_screen.016'),
                        CurrencyFormatter.ils(_remainingAmount(customer)),
                        _formatDateTime(customer['lastEntryAt']),
                      ];
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf;
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReportText()));
    if (!mounted) {
      return;
    }
    await AppAlertService.showSuccess(
      context,
      title: _t('screens_admin_debt_book_screen.017'),
      message: _t('screens_admin_debt_book_screen.018'),
    );
  }

  Future<void> _printReport() async {
    try {
      final pdf = await _buildReportPdf();
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'admin_debt_book_archive',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_debt_book_screen.019'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _shareReportPdf() async {
    try {
      final pdf = await _buildReportPdf();
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'admin_debt_book_archive.pdf',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_debt_book_screen.020'),
        message: ErrorMessageService.sanitize(error),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final permissions = AppPermissions.fromUser(_user);
    final summary = Map<String, dynamic>.from(
      _snapshot['summary'] as Map? ?? const {},
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        drawer: const AppSidebar(),
        appBar: AppBar(
          title: Text(_t('screens_admin_debt_book_screen.022')),
          actions: [
            IconButton(
              tooltip: _showFilters
                  ? _t('screens_topup_requests_screen.032')
                  : _t('screens_topup_requests_screen.033'),
              onPressed: () => setState(() => _showFilters = !_showFilters),
              icon: Icon(
                _showFilters
                    ? Icons.filter_alt_off_rounded
                    : Icons.filter_alt_rounded,
              ),
            ),
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
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.all(6),
                  labelPadding: EdgeInsets.symmetric(horizontal: 8),
                  tabs: [
                    Tab(
                      text: _t('screens_admin_debt_book_screen.042'),
                      icon: Icon(Icons.people_alt_rounded),
                    ),
                    Tab(
                      text: _t('screens_admin_debt_book_screen.043'),
                      icon: Icon(Icons.analytics_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : !permissions.canManageDebtBook
            ? Center(child: Text(_t('screens_admin_debt_book_screen.021')))
            : ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: TabBarView(
                  children: [_buildCustomersTab(), _buildSummaryTab(summary)],
                ),
              ),
      ),
    );
  }

  Widget _buildCustomersTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            withBorder: true,
            borderColor: AppTheme.borderLight,
            child: Text(
              _t('screens_admin_debt_book_screen.023'),
              style: AppTheme.bodyAction,
            ),
          ),
          const SizedBox(height: 16),
          if (_showFilters)
            ShwakelCard(
              padding: const EdgeInsets.all(18),
              withBorder: true,
              borderColor: AppTheme.borderLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _customers = _applyFilters(
                          _sortedCustomers(),
                          value,
                          _filter,
                        );
                      });
                    },
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_debt_book_screen.033'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _customers = _applyFilters(
                                    _sortedCustomers(),
                                    '',
                                    _filter,
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
                        _t('screens_admin_debt_book_screen.034'),
                        _AdminDebtFilter.all,
                      ),
                      _buildFilterChip(
                        _t('screens_admin_debt_book_screen.035'),
                        _AdminDebtFilter.debtors,
                      ),
                      _buildFilterChip(
                        _t('screens_admin_debt_book_screen.036'),
                        _AdminDebtFilter.settled,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ToolToggleHint(
              message: _t('screens_admin_debt_book_screen.044'),
              icon: Icons.filter_alt_rounded,
            ),
          const SizedBox(height: 16),
          if (_customers.isEmpty)
            ShwakelCard(
              padding: const EdgeInsets.all(28),
              withBorder: true,
              borderColor: AppTheme.borderLight,
              child: Center(
                child: Text(_t('screens_admin_debt_book_screen.037')),
              ),
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
                final phone = customer['phone']?.toString().trim() ?? '';
                return ShwakelCard(
                  onTap: () => _openCustomer(customer),
                  padding: const EdgeInsets.all(18),
                  withBorder: true,
                  borderColor: AppTheme.borderLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.warning.withValues(
                              alpha: 0.14,
                            ),
                            child: Text(
                              UserDisplayName.initialFromMap(
                                customer,
                                fallback: _t(
                                  'screens_admin_debt_book_screen.038',
                                ),
                              ),
                              style: AppTheme.bodyBold.copyWith(
                                color: AppTheme.warning,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  UserDisplayName.fromMap(
                                    customer,
                                    fallback: '-',
                                  ),
                                  style: AppTheme.bodyBold,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  phone.isNotEmpty
                                      ? phone
                                      : _t(
                                          'screens_admin_debt_book_screen.039',
                                        ),
                                  style: AppTheme.caption,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (balance > 0
                                          ? AppTheme.warning
                                          : AppTheme.success)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              CurrencyFormatter.ils(balance),
                              style: AppTheme.caption.copyWith(
                                color: balance > 0
                                    ? AppTheme.warning
                                    : AppTheme.success,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _smallSummary(
                              _t('screens_admin_debt_book_screen.040'),
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
                              _t('screens_admin_debt_book_screen.041'),
                              CurrencyFormatter.ils(
                                (customer['totalPaid'] as num?)?.toDouble() ??
                                    0,
                              ),
                              AppTheme.success,
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

  Widget _buildSummaryTab(Map<String, dynamic> summary) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricCard(
                _t('screens_admin_debt_book_screen.024'),
                '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                Icons.people_alt_rounded,
                AppTheme.primary,
              ),
              _metricCard(
                _t('screens_admin_debt_book_screen.025'),
                '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                Icons.warning_amber_rounded,
                AppTheme.warning,
              ),
              _metricCard(
                _t('screens_admin_debt_book_screen.026'),
                CurrencyFormatter.ils(
                  (summary['totalDebt'] as num?)?.toDouble() ?? 0,
                ),
                Icons.arrow_upward_rounded,
                AppTheme.error,
              ),
              _metricCard(
                _t('screens_admin_debt_book_screen.027'),
                CurrencyFormatter.ils(
                  (summary['totalPaid'] as num?)?.toDouble() ?? 0,
                ),
                Icons.arrow_downward_rounded,
                AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 18),
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            withBorder: true,
            borderColor: AppTheme.borderLight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statusPill(
                  icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  label: _isOnline
                      ? _t('screens_admin_debt_book_screen.028')
                      : _t('screens_admin_debt_book_screen.029'),
                  color: _isOnline ? AppTheme.success : AppTheme.warning,
                ),
                _statusPill(
                  icon: Icons.schedule_rounded,
                  label: _t(
                    'screens_admin_debt_book_screen.007',
                    params: {'date': _formatDateTime(_snapshot['syncedAt'])},
                  ),
                  color: AppTheme.primary,
                ),
                _actionPill(
                  icon: Icons.copy_all_rounded,
                  label: _t('screens_admin_debt_book_screen.030'),
                  onTap: _copyReport,
                ),
                _actionPill(
                  icon: Icons.print_rounded,
                  label: _t('screens_admin_debt_book_screen.031'),
                  onTap: _printReport,
                ),
                _actionPill(
                  icon: Icons.picture_as_pdf_rounded,
                  label: _t('screens_admin_debt_book_screen.032'),
                  onTap: _shareReportPdf,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
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

  Widget _actionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String title, _AdminDebtFilter filter) {
    return ChoiceChip(
      label: Text(title),
      selected: _filter == filter,
      onSelected: (_) {
        setState(() {
          _filter = filter;
          _customers = _applyFilters(
            _sortedCustomers(),
            _searchController.text,
            _filter,
          );
        });
      },
    );
  }
}

enum _AdminDebtFilter { all, debtors, settled }
