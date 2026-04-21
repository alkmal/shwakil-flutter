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
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';
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
  _AdminDebtFilter _filter = _AdminDebtFilter.all;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  bool get _isOnline => ConnectivityService.instance.isOnline.value;

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
      return 'لا يوجد';
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
      final aBalance = (a['balance'] as num?)?.toDouble() ?? 0;
      final bBalance = (b['balance'] as num?)?.toDouble() ?? 0;
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
      final name = customer['fullName']?.toString().toLowerCase() ?? '';
      final phone = customer['phone']?.toString().toLowerCase() ?? '';
      final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
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
        .where((customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0)
        .toList();
    final buffer = StringBuffer();
    buffer.writeln('تقرير إداري - دفتر الديون');
    buffer.writeln(
      'عدد العملاء: ${(summary['customersCount'] as num?)?.toInt() ?? 0}',
    );
    buffer.writeln(
      'عدد المديونين: ${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
    );
    buffer.writeln(
      'إجمالي الديون: ${CurrencyFormatter.ils((summary['totalDebt'] as num?)?.toDouble() ?? 0)}',
    );
    buffer.writeln(
      'إجمالي السداد: ${CurrencyFormatter.ils((summary['totalPaid'] as num?)?.toDouble() ?? 0)}',
    );
    buffer.writeln('آخر مزامنة: ${_formatDateTime(_snapshot['syncedAt'])}');
    buffer.writeln('');
    buffer.writeln('العملاء المديونون:');
    if (debtors.isEmpty) {
      buffer.writeln('- لا توجد ديون مفتوحة حاليًا');
    } else {
      for (final customer in debtors) {
        final phone = customer['phone']?.toString().trim() ?? '';
        buffer.writeln(
          '- ${customer['fullName'] ?? '-'} | ${phone.isNotEmpty ? phone : 'بدون رقم'} | ${CurrencyFormatter.ils((customer['balance'] as num?)?.toDouble() ?? 0)}',
        );
      }
    }
    return buffer.toString();
  }

  Future<pw.Document> _buildReportPdf() async {
    await _ensurePdfFonts();
    final summary = Map<String, dynamic>.from(
      _snapshot['summary'] as Map? ?? const {},
    );
    final debtors = _customers
        .where((customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0)
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
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'أرشيف إداري - دفتر الديون',
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
                        'عدد العملاء: ${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                      ),
                      pw.Text(
                        'عدد المديونين: ${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                      ),
                      pw.Text(
                        'إجمالي الديون: ${CurrencyFormatter.ils((summary['totalDebt'] as num?)?.toDouble() ?? 0)}',
                      ),
                      pw.Text(
                        'إجمالي السداد: ${CurrencyFormatter.ils((summary['totalPaid'] as num?)?.toDouble() ?? 0)}',
                      ),
                      pw.Text(
                        'آخر مزامنة: ${_formatDateTime(_snapshot['syncedAt'])}',
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                if (debtors.isEmpty)
                  pw.Text('لا توجد ديون مفتوحة حاليًا.')
                else
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: _pdfBoldFont),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellAlignment: pw.Alignment.centerRight,
                    headers: const ['العميل', 'الجوال', 'المتبقي', 'آخر حركة'],
                    data: debtors.map((customer) {
                      final phone = customer['phone']?.toString().trim() ?? '';
                      return [
                        customer['fullName']?.toString() ?? '-',
                        phone.isNotEmpty ? phone : 'بدون رقم',
                        CurrencyFormatter.ils(
                          (customer['balance'] as num?)?.toDouble() ?? 0,
                        ),
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
      title: 'تم النسخ',
      message: 'تم نسخ تقرير دفتر الديون الإداري.',
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
        title: 'فشل الطباعة',
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
        title: 'فشل التصدير',
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppSidebar(),
      appBar: AppBar(
        title: const Text('أرشيف دفتر الديون'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading || _syncing ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'مزامنة',
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !permissions.canManageDebtBook
          ? const Center(child: Text('لا تملك صلاحية الوصول إلى أرشيف دفتر الديون.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: ResponsiveScaffoldContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShwakelCard(
                      padding: const EdgeInsets.all(22),
                      gradient: AppTheme.heroGradient,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أرشيف إداري كامل لدفتر الديون',
                            style: AppTheme.h2.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ابحث، صفِّ، واطبع كشفًا عامًا للعملاء المديونين من مكان واحد.',
                            style: AppTheme.bodyText.copyWith(
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _metricCard(
                          'عدد العملاء',
                          '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                          Icons.people_alt_rounded,
                          AppTheme.primary,
                        ),
                        _metricCard(
                          'المديونون',
                          '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                          Icons.warning_amber_rounded,
                          AppTheme.warning,
                        ),
                        _metricCard(
                          'إجمالي الديون',
                          CurrencyFormatter.ils(
                            (summary['totalDebt'] as num?)?.toDouble() ?? 0,
                          ),
                          Icons.arrow_upward_rounded,
                          AppTheme.error,
                        ),
                        _metricCard(
                          'إجمالي السداد',
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
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _statusPill(
                            icon: _isOnline
                                ? Icons.wifi_rounded
                                : Icons.wifi_off_rounded,
                            label: _isOnline ? 'أون لاين' : 'أوف لاين',
                            color: _isOnline
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                          _statusPill(
                            icon: Icons.schedule_rounded,
                            label: 'آخر مزامنة: ${_formatDateTime(_snapshot['syncedAt'])}',
                            color: AppTheme.primary,
                          ),
                          _actionPill(
                            icon: Icons.copy_all_rounded,
                            label: 'نسخ التقرير',
                            onTap: _copyReport,
                          ),
                          _actionPill(
                            icon: Icons.print_rounded,
                            label: 'طباعة',
                            onTap: _printReport,
                          ),
                          _actionPill(
                            icon: Icons.picture_as_pdf_rounded,
                            label: 'تصدير PDF',
                            onTap: _shareReportPdf,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
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
                        labelText: 'البحث بالاسم أو رقم الجوال',
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
                        _buildFilterChip('الكل', _AdminDebtFilter.all),
                        _buildFilterChip('مديونون فقط', _AdminDebtFilter.debtors),
                        _buildFilterChip(
                          'مسددون أو بدون دين',
                          _AdminDebtFilter.settled,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_customers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('لا توجد نتائج مطابقة.')),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _customers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final balance =
                              (customer['balance'] as num?)?.toDouble() ?? 0;
                          final phone = customer['phone']?.toString().trim() ?? '';
                          return ShwakelCard(
                            onTap: () => _openCustomer(customer),
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.warning
                                          .withValues(alpha: 0.14),
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
                                            : 'ع',
                                        style: AppTheme.bodyBold.copyWith(
                                          color: AppTheme.warning,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customer['fullName']?.toString() ?? '-',
                                            style: AppTheme.bodyBold,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            phone.isNotEmpty
                                                ? phone
                                                : 'بدون رقم جوال',
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
                                        color: (balance > 0
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
                                        'إجمالي الدين',
                                        CurrencyFormatter.ils(
                                          (customer['totalDebt'] as num?)
                                                  ?.toDouble() ??
                                              0,
                                        ),
                                        AppTheme.error,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _smallSummary(
                                        'إجمالي السداد',
                                        CurrencyFormatter.ils(
                                          (customer['totalPaid'] as num?)
                                                  ?.toDouble() ??
                                              0,
                                        ),
                                        AppTheme.success,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'آخر حركة: ${_formatDateTime(customer['lastEntryAt'])}',
                                  style: AppTheme.caption,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
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
