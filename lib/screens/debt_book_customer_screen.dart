import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
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

  String _buildCustomerReportText() {
    final customer = _customer;
    if (customer == null) {
      return '';
    }
    final buffer = StringBuffer();
    final totalDebt = (customer['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;

    buffer.writeln('كشف دفتر ديون');
    buffer.writeln('اسم العميل: ${customer['fullName'] ?? '-'}');
    buffer.writeln(
      'رقم الجوال: ${customer['phone']?.toString().trim().isNotEmpty == true ? customer['phone'] : 'بدون رقم'}',
    );
    buffer.writeln(
      'آخر حركة: ${_formatDateTime(customer['lastEntryAt'])}',
    );
    if ((customer['notes']?.toString().trim().isNotEmpty ?? false)) {
      buffer.writeln('ملاحظات: ${customer['notes']}');
    }
    buffer.writeln('');
    buffer.writeln('إجمالي الديون: ${CurrencyFormatter.ils(totalDebt)}');
    buffer.writeln('إجمالي السداد: ${CurrencyFormatter.ils(totalPaid)}');
    buffer.writeln('المتبقي: ${CurrencyFormatter.ils(balance)}');
    buffer.writeln('');
    buffer.writeln('سجل الحركات:');
    for (final entry in _entries) {
      final isDebt = entry['type'] == 'debt';
      buffer.writeln(
        '- ${isDebt ? 'دين' : 'سداد'} | ${CurrencyFormatter.ils((entry['amount'] as num?)?.toDouble() ?? 0)} | ${_formatDateTime(entry['occurredAt'])} | ${entry['note']?.toString().trim().isNotEmpty == true ? entry['note'] : 'بدون ملاحظات'}',
      );
    }
    return buffer.toString();
  }

  Future<pw.Document> _buildCustomerReportPdf() async {
    await _ensurePdfFonts();
    final customer = _customer!;
    final totalDebt = (customer['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
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
                  'كشف دفتر ديون العميل',
                  style: pw.TextStyle(
                    font: _pdfBoldFont,
                    fontSize: 18,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text('اسم العميل: ${customer['fullName'] ?? '-'}'),
                pw.Text(
                  'رقم الجوال: ${customer['phone']?.toString().trim().isNotEmpty == true ? customer['phone'] : 'بدون رقم'}',
                ),
                pw.Text('آخر حركة: ${_formatDateTime(customer['lastEntryAt'])}'),
                if ((customer['notes']?.toString().trim().isNotEmpty ?? false))
                  pw.Text('ملاحظات: ${customer['notes']}'),
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
                      pw.Text('إجمالي الديون: ${CurrencyFormatter.ils(totalDebt)}'),
                      pw.Text('إجمالي السداد: ${CurrencyFormatter.ils(totalPaid)}'),
                      pw.Text('المتبقي: ${CurrencyFormatter.ils(balance)}'),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'سجل الحركات',
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                if (_entries.isEmpty)
                  pw.Text('لا توجد حركات مسجلة لهذا العميل.')
                else
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: _pdfBoldFont),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellAlignment: pw.Alignment.centerRight,
                    headers: const ['النوع', 'المبلغ', 'التاريخ', 'البيان'],
                    data: _entries.map((entry) {
                      final isDebt = entry['type'] == 'debt';
                      return [
                        isDebt ? 'دين' : 'سداد',
                        CurrencyFormatter.ils(
                          (entry['amount'] as num?)?.toDouble() ?? 0,
                        ),
                        _formatDateTime(entry['occurredAt']),
                        entry['note']?.toString().trim().isNotEmpty == true
                            ? entry['note'].toString()
                            : 'بدون ملاحظات',
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
      title: 'تم النسخ',
      message: 'تم نسخ كشف العميل إلى الحافظة.',
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
            'debt_book_${_customer!['fullName']?.toString().trim().replaceAll(' ', '_') ?? 'customer'}',
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

  Future<void> _shareCustomerReportPdf() async {
    if (_customer == null) {
      return;
    }
    try {
      final pdf = await _buildCustomerReportPdf();
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'debt_book_${_customer!['fullName']?.toString().trim().replaceAll(' ', '_') ?? 'customer'}.pdf',
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

  bool _matchesCustomerRef(
    Map<String, dynamic>? customer,
    String customerRef,
  ) {
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
          ? ((entry?['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)
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
                ? (entryType == 'debt' ? 'إضافة دين' : 'إضافة سداد')
                : (entryType == 'debt' ? 'تعديل قيد دين' : 'تعديل قيد سداد'),
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
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'بيان العملية',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
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
          message: 'أدخل مبلغًا صحيحًا أكبر من صفر.',
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
          title: 'تم الحفظ محليًا',
          message: 'سيتم رفع العملية عند توفر الإنترنت.',
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
          title: const Text('تعديل بيانات العميل'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'اسم العميل'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الجوال'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
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
        title: const Text('حذف العميل'),
        content: Text(
          'سيتم حذف العميل "${customer['fullName'] ?? '-'}" مع جميع حركاته من دفتر الديون.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
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
        title: const Text('حذف القيد'),
        content: const Text('سيتم حذف هذا القيد من دفتر الديون.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
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
        title: 'تم الحذف محليًا',
        message: 'سيتم ترحيل حذف القيد عند توفر الإنترنت.',
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
    final totalDebt = (customer?['totalDebt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (customer?['totalPaid'] as num?)?.toDouble() ?? 0;
    final balance = (customer?['balance'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(customer?['fullName']?.toString() ?? 'تفاصيل العميل'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : () => _load(),
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
          : customer == null
          ? const Center(child: Text('تعذر العثور على بيانات هذا العميل.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: ResponsiveScaffoldContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShwakelCard(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer['fullName']?.toString() ?? '-',
                                      style: AppTheme.h3,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      customer['phone']?.toString().trim().isNotEmpty ==
                                              true
                                          ? customer['phone'].toString()
                                          : 'بدون رقم جوال',
                                      style: AppTheme.caption,
                                    ),
                                    if ((customer['notes']?.toString().trim().isNotEmpty ??
                                        false)) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        customer['notes'].toString(),
                                        style: AppTheme.bodyText,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              ShwakelButton(
                                label: 'تعديل',
                                icon: Icons.edit_rounded,
                                onPressed: _showEditCustomerDialog,
                              ),
                              const SizedBox(width: 8),
                              ShwakelButton(
                                label: 'حذف',
                                icon: Icons.delete_outline_rounded,
                                isDanger: true,
                                onPressed: _deleteCustomer,
                              ),
                            ],
                          ),
                          if (_customerHasPendingChanges(customer)) ...[
                            const SizedBox(height: 12),
                            _pendingBadge(),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            'آخر حركة مسجلة: ${_formatDateTime(customer['lastEntryAt'])}',
                            style: AppTheme.caption,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _summaryCard(
                                'إجمالي الديون',
                                CurrencyFormatter.ils(totalDebt),
                                AppTheme.error,
                              ),
                              _summaryCard(
                                'إجمالي السداد',
                                CurrencyFormatter.ils(totalPaid),
                                AppTheme.success,
                              ),
                              _summaryCard(
                                'المتبقي',
                                CurrencyFormatter.ils(balance),
                                balance > 0
                                    ? AppTheme.warning
                                    : AppTheme.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              ShwakelButton(
                                label: 'إضافة دين',
                                icon: Icons.add_circle_rounded,
                                color: AppTheme.error,
                                onPressed: () => _showEntryDialog('debt'),
                              ),
                              ShwakelButton(
                                label: 'إضافة سداد',
                                icon: Icons.payments_rounded,
                                color: AppTheme.success,
                                onPressed: () => _showEntryDialog('payment'),
                              ),
                              ShwakelButton(
                                label: 'نسخ الكشف',
                                icon: Icons.copy_all_rounded,
                                onPressed: _copyCustomerReport,
                              ),
                              ShwakelButton(
                                label: 'طباعة',
                                icon: Icons.print_rounded,
                                onPressed: _printCustomerReport,
                              ),
                              ShwakelButton(
                                label: 'تصدير PDF',
                                icon: Icons.picture_as_pdf_rounded,
                                onPressed: _shareCustomerReportPdf,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('سجل العميل', style: AppTheme.h3),
                    const SizedBox(height: 12),
                    if (_entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('لا توجد حركات مسجلة لهذا العميل.')),
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
                                    color: (isDebt
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isDebt ? 'قيد دين' : 'قيد سداد',
                                        style: AppTheme.bodyBold,
                                      ),
                                      const SizedBox(height: 6),
                                      if (_entryHasPendingChanges(entry)) ...[
                                        _pendingBadge(),
                                        const SizedBox(height: 6),
                                      ],
                                      Text(
                                        CurrencyFormatter.ils(
                                          (entry['amount'] as num?)?.toDouble() ??
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
                                        entry['note']?.toString().trim().isNotEmpty ==
                                                true
                                            ? entry['note'].toString()
                                            : 'بدون ملاحظات',
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
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showEntryDialog(
                                        entry['type']?.toString() ?? 'debt',
                                        entry: entry,
                                      );
                                    } else if (value == 'delete') {
                                      _deleteEntry(entry);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل القيد'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف القيد'),
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

  Widget _summaryCard(String title, String value, Color color) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.caption),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTheme.bodyBold.copyWith(color: color),
            ),
          ],
        ),
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
        'بانتظار المزامنة',
        style: AppTheme.caption.copyWith(
          color: AppTheme.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
