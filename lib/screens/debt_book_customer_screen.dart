import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class DebtBookCustomerScreen extends StatefulWidget {
  const DebtBookCustomerScreen({super.key, required this.customerRef});

  final String customerRef;

  @override
  State<DebtBookCustomerScreen> createState() => _DebtBookCustomerScreenState();
}

class _DebtBookCustomerScreenState extends State<DebtBookCustomerScreen> {
  final _auth = AuthService();
  final _api = ApiService();
  final _debtBook = DebtBookService();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _entries = const [];
  List<Map<String, dynamic>> _pendingOperations = const [];
  bool _loading = true;
  bool _syncing = false;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  double _remainingAmount(Map<String, dynamic>? customer) {
    if (customer == null) {
      return 0;
    }
    return (customer['remainingAmount'] as num?)?.toDouble() ??
        (customer['balance'] as num?)?.toDouble() ??
        0;
  }

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return _t('screens_debt_book_customer_screen.001');
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

  String _buildCustomerReportText() {
    final customer = _customer;
    if (customer == null) {
      return '';
    }
    final buffer = StringBuffer();
    final totalDebt = (customer['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = _remainingAmount(customer);

    buffer.writeln(_t('screens_debt_book_customer_screen.002'));
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.003',
        params: {'name': UserDisplayName.fromMap(customer, fallback: '-')},
      ),
    );
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.004',
        params: {
          'phone': customer['phone']?.toString().trim().isNotEmpty == true
              ? customer['phone'].toString()
              : _t('screens_debt_book_customer_screen.005'),
        },
      ),
    );
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.006',
        params: {'date': _formatDateTime(customer['lastEntryAt'])},
      ),
    );
    if ((customer['notes']?.toString().trim().isNotEmpty ?? false)) {
      buffer.writeln(
        _t(
          'screens_debt_book_customer_screen.007',
          params: {'notes': customer['notes'].toString()},
        ),
      );
    }
    buffer.writeln('');
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.008',
        params: {'amount': CurrencyFormatter.ils(totalDebt)},
      ),
    );
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.009',
        params: {'amount': CurrencyFormatter.ils(totalPaid)},
      ),
    );
    buffer.writeln(
      _t(
        'screens_debt_book_customer_screen.010',
        params: {'amount': CurrencyFormatter.ils(balance)},
      ),
    );
    buffer.writeln('');
    buffer.writeln(_t('screens_debt_book_customer_screen.011'));
    for (final entry in _entries) {
      final isDebt = entry['type'] == 'debt';
      buffer.writeln(
        _t(
          'screens_debt_book_customer_screen.012',
          params: {
            'type': isDebt
                ? _t('screens_debt_book_customer_screen.013')
                : _t('screens_debt_book_customer_screen.014'),
            'amount': CurrencyFormatter.ils(
              (entry['amount'] as num?)?.toDouble() ?? 0,
            ),
            'date': _formatDateTime(entry['occurredAt']),
            'note': entry['note']?.toString().trim().isNotEmpty == true
                ? entry['note'].toString()
                : _t('screens_debt_book_customer_screen.015'),
          },
        ),
      );
    }
    return buffer.toString();
  }

  Future<pw.Document> _buildCustomerReportPdf() async {
    await _ensurePdfFonts();
    if (!mounted) {
      return pw.Document();
    }
    final l = context.loc;
    final customer = _customer!;
    final totalDebt = (customer['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = _remainingAmount(customer);
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
                  l.tr('screens_debt_book_customer_screen.016'),
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  l.tr(
                    'screens_debt_book_customer_screen.003',
                    params: {
                      'name': UserDisplayName.fromMap(customer, fallback: '-'),
                    },
                  ),
                ),
                pw.Text(
                  l.tr(
                    'screens_debt_book_customer_screen.004',
                    params: {
                      'phone':
                          customer['phone']?.toString().trim().isNotEmpty ==
                              true
                          ? customer['phone'].toString()
                          : l.tr('screens_debt_book_customer_screen.005'),
                    },
                  ),
                ),
                pw.Text(
                  l.tr(
                    'screens_debt_book_customer_screen.006',
                    params: {'date': _formatDateTime(customer['lastEntryAt'])},
                  ),
                ),
                if ((customer['notes']?.toString().trim().isNotEmpty ?? false))
                  pw.Text(
                    l.tr(
                      'screens_debt_book_customer_screen.007',
                      params: {'notes': customer['notes'].toString()},
                    ),
                  ),
                pw.SizedBox(height: 16),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        l.tr(
                          'screens_debt_book_customer_screen.008',
                          params: {'amount': CurrencyFormatter.ils(totalDebt)},
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_debt_book_customer_screen.009',
                          params: {'amount': CurrencyFormatter.ils(totalPaid)},
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_debt_book_customer_screen.010',
                          params: {'amount': CurrencyFormatter.ils(balance)},
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  l.tr('screens_debt_book_customer_screen.017'),
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                if (_entries.isEmpty)
                  pw.Text(l.tr('screens_debt_book_customer_screen.018'))
                else
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: _pdfBoldFont),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellAlignment: pw.Alignment.centerRight,
                    headers: [
                      l.tr('screens_debt_book_customer_screen.019'),
                      l.tr('screens_debt_book_customer_screen.020'),
                      l.tr('screens_debt_book_customer_screen.021'),
                      l.tr('screens_debt_book_customer_screen.022'),
                    ],
                    data: _entries.map((entry) {
                      final isDebt = entry['type'] == 'debt';
                      return [
                        isDebt
                            ? l.tr('screens_debt_book_customer_screen.013')
                            : l.tr('screens_debt_book_customer_screen.014'),
                        CurrencyFormatter.ils(
                          (entry['amount'] as num?)?.toDouble() ?? 0,
                        ),
                        _formatDateTime(entry['occurredAt']),
                        entry['note']?.toString().trim().isNotEmpty == true
                            ? entry['note'].toString()
                            : l.tr('screens_debt_book_customer_screen.015'),
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

  Future<void> _copyCustomerReport() async {
    final report = _buildCustomerReportText();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    await AppAlertService.showSuccess(
      context,
      title: _t('screens_debt_book_customer_screen.023'),
      message: _t('screens_debt_book_customer_screen.024'),
    );
  }

  Future<void> _printCustomerReport() async {
    if (_customer == null) {
      return;
    }
    try {
      final pdf = await _buildCustomerReportPdf();
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name:
            'debt_book_${UserDisplayName.fromMap(_customer, fallback: 'customer').replaceAll(' ', '_')}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_debt_book_customer_screen.025'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _shareCustomerReportPdf() async {
    if (_customer == null) {
      return;
    }
    try {
      final pdf = await _buildCustomerReportPdf();
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'debt_book_${UserDisplayName.fromMap(_customer, fallback: 'customer').replaceAll(' ', '_')}.pdf',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_debt_book_customer_screen.026'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  bool get _isOnline => ConnectivityService.instance.isOnline.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool syncIfPossible = true}) async {
    final user = await _auth.currentUser();
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = true;
    });
    if (user == null || user['id'] == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final snapshot = await _debtBook.getSnapshot(user['id'].toString());
    final pendingOperations = await _debtBook.getPendingOperations(
      user['id'].toString(),
    );
    _applySnapshot(snapshot);
    if (!mounted) return;
    setState(() {
      _pendingOperations = pendingOperations;
      _loading = false;
    });

    if (syncIfPossible && _isOnline) {
      await _syncAndRefresh(showErrors: false);
    }
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    final customers = List<Map<String, dynamic>>.from(
      (snapshot['customers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final entries = List<Map<String, dynamic>>.from(
      (snapshot['entries'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );

    final customer = customers.cast<Map<String, dynamic>?>().firstWhere(
      (item) => _matchesCustomerRef(item, widget.customerRef),
      orElse: () => null,
    );
    final filteredEntries = customer == null
        ? <Map<String, dynamic>>[]
        : entries.where((entry) {
            final customerId = customer['id']?.toString() ?? '';
            final customerClientRef = customer['clientRef']?.toString() ?? '';
            final entryCustomerId = entry['customerId']?.toString() ?? '';
            return entryCustomerId == customerId ||
                entryCustomerId == 'local:$customerClientRef';
          }).toList();

    if (!mounted) {
      _customer = customer;
      _entries = filteredEntries;
      return;
    }

    setState(() {
      _customer = customer;
      _entries = filteredEntries;
    });
  }

  bool _matchesCustomerRef(Map<String, dynamic>? customer, String customerRef) {
    if (customer == null) {
      return false;
    }
    final id = customer['id']?.toString() ?? '';
    final clientRef = customer['clientRef']?.toString() ?? '';
    return id == customerRef ||
        clientRef == customerRef ||
        'local:$clientRef' == customerRef;
  }

  Future<void> _syncAndRefresh({bool showErrors = true}) async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null || !_isOnline) {
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
      _applySnapshot(snapshot);
      if (!mounted) return;
      setState(() {
        _pendingOperations = pendingOperations;
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

  Future<void> _showEntryDialog(
    String entryType, {
    Map<String, dynamic>? entry,
  }) async {
    final amountController = TextEditingController(
      text: ((entry?['amount'] as num?)?.toDouble() ?? 0) > 0
          ? CurrencyFormatter.formatAmount(
              (entry?['amount'] as num?)?.toDouble() ?? 0,
            )
          : '',
    );
    final noteController = TextEditingController(
      text: entry?['note']?.toString() ?? '',
    );

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            entry == null
                ? (entryType == 'debt'
                      ? _t('screens_debt_book_customer_screen.027')
                      : _t('screens_debt_book_customer_screen.028'))
                : (entryType == 'debt'
                      ? _t('screens_debt_book_customer_screen.029')
                      : _t('screens_debt_book_customer_screen.030')),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_customer_screen.031'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_customer_screen.032'),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('screens_debt_book_customer_screen.033')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('screens_debt_book_customer_screen.034')),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
      final amount = double.tryParse(amountController.text.trim()) ?? 0;
      if (amount <= 0) {
        if (!mounted) return;
        await AppAlertService.showError(
          context,
          message: _t('screens_debt_book_customer_screen.035'),
        );
        return;
      }

      final user = _user ?? await _auth.currentUser();
      final customer = _customer;
      if (user == null || user['id'] == null || customer == null) {
        return;
      }

      if (entry == null) {
        await _debtBook.addEntryLocally(
          userId: user['id'].toString(),
          customerRef:
              customer['id']?.toString() ??
              customer['clientRef']?.toString() ??
              widget.customerRef,
          entryType: entryType,
          amount: amount,
          note: noteController.text,
        );
      } else {
        await _debtBook.updateEntryLocally(
          userId: user['id'].toString(),
          entryRef:
              entry['id']?.toString() ?? entry['clientRef']?.toString() ?? '',
          entryType: entryType,
          amount: amount,
          note: noteController.text,
        );
      }
      await _load(syncIfPossible: false);
      if (_isOnline) {
        await _syncAndRefresh(showErrors: true);
      } else if (mounted) {
        await AppAlertService.showInfo(
          context,
          title: _t('screens_debt_book_customer_screen.036'),
          message: _t('screens_debt_book_customer_screen.037'),
        );
      }
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _showEditCustomerDialog() async {
    final customer = _customer;
    if (customer == null) {
      return;
    }
    final nameController = TextEditingController(
      text: customer['fullName']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: customer['phone']?.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: customer['notes']?.toString() ?? '',
    );

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('screens_debt_book_customer_screen.038')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_customer_screen.039'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_customer_screen.040'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('screens_debt_book_customer_screen.041'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('screens_debt_book_customer_screen.033')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('screens_debt_book_customer_screen.034')),
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
      await _debtBook.upsertCustomerLocally(
        userId: user['id'].toString(),
        customerRef:
            customer['id']?.toString() ?? customer['clientRef']?.toString(),
        fullName: nameController.text,
        phone: phoneController.text,
        notes: notesController.text,
      );
      await _load(syncIfPossible: false);
      if (_isOnline) {
        await _syncAndRefresh(showErrors: true);
      }
    } finally {
      nameController.dispose();
      phoneController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _deleteCustomer() async {
    final customer = _customer;
    final user = _user ?? await _auth.currentUser();
    if (customer == null || user == null || user['id'] == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_debt_book_customer_screen.042')),
        content: Text(
          _t(
            'screens_debt_book_customer_screen.043',
            params: {'name': UserDisplayName.fromMap(customer, fallback: '-')},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('screens_debt_book_customer_screen.033')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('screens_debt_book_customer_screen.044')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _debtBook.deleteCustomerLocally(
      userId: user['id'].toString(),
      customerRef:
          customer['id']?.toString() ?? customer['clientRef']?.toString() ?? '',
    );

    if (_isOnline) {
      await _syncAndRefresh(showErrors: true);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_debt_book_customer_screen.045')),
        content: Text(_t('screens_debt_book_customer_screen.046')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('screens_debt_book_customer_screen.033')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('screens_debt_book_customer_screen.044')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await _debtBook.deleteEntryLocally(
      userId: user['id'].toString(),
      entryRef: entry['id']?.toString() ?? entry['clientRef']?.toString() ?? '',
    );
    await _load(syncIfPossible: false);
    if (_isOnline) {
      await _syncAndRefresh(showErrors: true);
    } else if (mounted) {
      await AppAlertService.showInfo(
        context,
        title: _t('screens_debt_book_customer_screen.047'),
        message: _t('screens_debt_book_customer_screen.048'),
      );
    }
  }

  Future<void> _showSummaryDialog() async {
    final customer = _customer;
    if (customer == null || !mounted) {
      return;
    }

    final totalDebt = (customer['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = _remainingAmount(customer);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_debt_book_customer_screen.067')),
        content: SizedBox(
          width: 460,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 420;
              final cards = [
                _summaryCard(
                  _t('screens_debt_book_customer_screen.056'),
                  CurrencyFormatter.ils(totalDebt),
                  AppTheme.error,
                ),
                _summaryCard(
                  _t('screens_debt_book_customer_screen.057'),
                  CurrencyFormatter.ils(totalPaid),
                  AppTheme.success,
                ),
                _summaryCard(
                  _t('screens_debt_book_customer_screen.058'),
                  CurrencyFormatter.ils(balance),
                  balance > 0 ? AppTheme.warning : AppTheme.primary,
                ),
              ];

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards
                    .map(
                      (card) => SizedBox(
                        width: isCompact ? double.infinity : 132,
                        child: card,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('screens_debt_book_customer_screen.068')),
          ),
        ],
      ),
    );
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

  bool _entryHasPendingChanges(Map<String, dynamic> entry) {
    final entryId = entry['id']?.toString() ?? '';
    final clientRef = entry['clientRef']?.toString() ?? '';
    if (entryId.startsWith('local:')) {
      return true;
    }
    for (final operation in _pendingOperations) {
      if ((operation['entity']?.toString() ?? '') != 'entry') {
        continue;
      }
      final opServerId = operation['serverId']?.toString() ?? '';
      final opClientRef = operation['clientRef']?.toString() ?? '';
      if ((entryId.isNotEmpty && opServerId == entryId) ||
          (clientRef.isNotEmpty && opClientRef == clientRef)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          UserDisplayName.fromMap(
            customer,
            fallback: _t('screens_debt_book_customer_screen.062'),
          ),
        ),
        actions: [
          if (customer != null) ...[
            IconButton(
              tooltip: _t('screens_debt_book_customer_screen.053'),
              onPressed: _showEditCustomerDialog,
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              tooltip: _t('screens_debt_book_customer_screen.054'),
              onPressed: _deleteCustomer,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
          IconButton(
            tooltip: _t('screens_debt_book_customer_screen.049'),
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: _t('screens_debt_book_customer_screen.050'),
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
          : customer == null
          ? Center(child: Text(_t('screens_debt_book_customer_screen.051')))
          : ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShwakelCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompact = constraints.maxWidth < 720;
                              return Flex(
                                direction: isCompact
                                    ? Axis.vertical
                                    : Axis.horizontal,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: isCompact ? 0 : 1,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          UserDisplayName.fromMap(
                                            customer,
                                            fallback: '-',
                                          ),
                                          style: AppTheme.h3,
                                        ),
                                        const SizedBox(height: 10),
                                        _customerInfoPill(
                                          icon: Icons.phone_rounded,
                                          text:
                                              customer['phone']
                                                      ?.toString()
                                                      .trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? customer['phone'].toString()
                                              : _t(
                                                  'screens_debt_book_customer_screen.052',
                                                ),
                                        ),
                                        if ((customer['notes']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ??
                                            false)) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              customer['notes'].toString(),
                                              style: AppTheme.bodyText,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: isCompact ? 0 : 12,
                                    height: isCompact ? 14 : 0,
                                  ),
                                  const SizedBox.shrink(),
                                ],
                              );
                            },
                          ),
                          if (_customerHasPendingChanges(customer)) ...[
                            const SizedBox(height: 12),
                            _pendingBadge(),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            _t(
                              'screens_debt_book_customer_screen.055',
                              params: {
                                'date': _formatDateTime(
                                  customer['lastEntryAt'],
                                ),
                              },
                            ),
                            style: AppTheme.caption,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.067',
                                ),
                                icon: Icons.summarize_rounded,
                                onPressed: _showSummaryDialog,
                              ),
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.027',
                                ),
                                icon: Icons.add_circle_rounded,
                                color: AppTheme.error,
                                onPressed: () => _showEntryDialog('debt'),
                              ),
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.028',
                                ),
                                icon: Icons.payments_rounded,
                                color: AppTheme.success,
                                onPressed: () => _showEntryDialog('payment'),
                              ),
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.059',
                                ),
                                icon: Icons.copy_all_rounded,
                                onPressed: _copyCustomerReport,
                              ),
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.060',
                                ),
                                icon: Icons.print_rounded,
                                onPressed: _printCustomerReport,
                              ),
                              ShwakelButton(
                                label: _t(
                                  'screens_debt_book_customer_screen.061',
                                ),
                                icon: Icons.picture_as_pdf_rounded,
                                onPressed: _shareCustomerReportPdf,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _t('screens_debt_book_customer_screen.062'),
                      style: AppTheme.h3,
                    ),
                    const SizedBox(height: 12),
                    if (_entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            _t('screens_debt_book_customer_screen.018'),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isDebt = entry['type'] == 'debt';
                          return ShwakelCard(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color:
                                        (isDebt
                                                ? AppTheme.error
                                                : AppTheme.success)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isDebt
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    color: isDebt
                                        ? AppTheme.error
                                        : AppTheme.success,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isDebt
                                            ? _t(
                                                'screens_debt_book_customer_screen.063',
                                              )
                                            : _t(
                                                'screens_debt_book_customer_screen.064',
                                              ),
                                        style: AppTheme.bodyBold,
                                      ),
                                      const SizedBox(height: 6),
                                      if (_entryHasPendingChanges(entry)) ...[
                                        _pendingBadge(),
                                        const SizedBox(height: 6),
                                      ],
                                      Text(
                                        CurrencyFormatter.ils(
                                          (entry['amount'] as num?)
                                                  ?.toDouble() ??
                                              0,
                                        ),
                                        style: AppTheme.bodyBold.copyWith(
                                          color: isDebt
                                              ? AppTheme.error
                                              : AppTheme.success,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        entry['note']
                                                    ?.toString()
                                                    .trim()
                                                    .isNotEmpty ==
                                                true
                                            ? entry['note'].toString()
                                            : _t(
                                                'screens_debt_book_customer_screen.015',
                                              ),
                                        style: AppTheme.bodyText,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatDateTime(entry['occurredAt']),
                                        style: AppTheme.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _smallActionIconButton(
                                      tooltip: _t(
                                        'screens_debt_book_customer_screen.065',
                                      ),
                                      icon: Icons.edit_rounded,
                                      onPressed: () => _showEntryDialog(
                                        entry['type']?.toString() ?? 'debt',
                                        entry: entry,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _smallActionIconButton(
                                      tooltip: _t(
                                        'screens_debt_book_customer_screen.045',
                                      ),
                                      icon: Icons.delete_outline_rounded,
                                      isDanger: true,
                                      onPressed: () => _deleteEntry(entry),
                                    ),
                                  ],
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

  Widget _smallActionIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool isDanger = false,
  }) {
    final color = isDanger ? AppTheme.error : AppTheme.primary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: AppTheme.caption),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppTheme.bodyBold.copyWith(color: color),
          ),
        ],
      ),
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
        _t('screens_debt_book_customer_screen.066'),
        style: AppTheme.caption.copyWith(
          color: AppTheme.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _customerInfoPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: AppTheme.caption)),
        ],
      ),
    );
  }
}
