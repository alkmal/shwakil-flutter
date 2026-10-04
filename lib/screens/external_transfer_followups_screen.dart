import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class ExternalTransferFollowupsScreen extends StatefulWidget {
  const ExternalTransferFollowupsScreen({super.key});
  @override
  State<ExternalTransferFollowupsScreen> createState() =>
      _ExternalTransferFollowupsScreenState();
}

class _ExternalTransferFollowupsScreenState
    extends State<ExternalTransferFollowupsScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic> _totals = {};
  bool _loading = true;
  bool _canManage = false;
  bool _canCreate = false;
  bool _isSubUser = false;
  bool _canReview = false;
  String _status = 'all';
  String _reviewed = 'all';
  String _employeeId = 'all';
  DateTime? _from;
  DateTime? _to;
  Timer? _liveRefresh;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
    // تحديث شبه فوري للحالات والإضافات الجديدة للحسابات المرتبطة بالمحل.
    _liveRefresh = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _liveRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final previous = {
        for (final row in _rows)
          '${row['id']}': '${row['delivery_status']}:${row['reviewed']}',
      };
      final body = await _api.getExternalTransfers(
        filters: {
          if (_from != null) 'from': _date(_from!),
          if (_to != null) 'to': _date(_to!),
          if (_status != 'all') 'status': _status,
          if (_reviewed != 'all') 'reviewed': _reviewed,
          if (_employeeId != 'all') 'employeeId': _employeeId,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(
          (body['transfers'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        _totals = Map<String, dynamic>.from(body['totals'] as Map? ?? {});
        _employees = List<Map<String, dynamic>>.from(
          (body['employees'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        _canCreate = body['canCreate'] == true;
        _isSubUser = body['isSubUser'] == true;
        _canManage = body['canManage'] == true;
        _canReview = body['canReview'] == true;
        _loading = false;
      });
      if (silent && _loadedOnce) {
        final changed = _rows.any(
          (row) =>
              previous['${row['id']}'] !=
              '${row['delivery_status']}:${row['reviewed']}',
        );
        if (changed && mounted) {
          AppAlertService.showSnack(
            context,
            message: 'تم تحديث حالة إحدى التحويلات الخارجية.',
            type: AppAlertType.info,
          );
        }
      }
      _loadedOnce = true;
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (!silent)
          AppAlertService.showError(
            context,
            title: 'تعذر التحميل',
            message: ErrorMessageService.sanitize(e),
          );
      }
    }
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<void> _pickDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from
          ? (_from ?? DateTime.now())
          : (_to ?? _from ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  Future<void> _markDayReviewed() async {
    if (!_canReview) return;
    final pending = _rows
        .where((r) => !(r['reviewed'] == true || r['reviewed'] == 1))
        .toList();
    for (final row in pending) {
      await _api.updateExternalTransfer('${row['id']}', {
        'deliveryStatus': row['delivery_status'] ?? 'pending',
        'reviewed': true,
      });
    }
    await _load();
  }

  Future<void> _exportCsv() async {
    String cell(dynamic value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final lines = <String>[
      '\uFEFF${['المستفيد', 'الجوال', 'القيمة', 'الجهة', 'الحساب', 'الحالة', 'تمت المراجعة', 'بواسطة', 'التاريخ'].map(cell).join(',')}',
      ..._rows.map(
        (r) => [
          r['beneficiary_name'],
          r['beneficiary_mobile'],
          r['amount'],
          r['destination_name'],
          r['destination_account'],
          r['delivery_status'],
          r['reviewed'] == true || r['reviewed'] == 1 ? 'نعم' : 'لا',
          r['created_by_name'],
          r['created_at'],
        ].map(cell).join(','),
      ),
    ];
    await FileSaver.instance.saveFile(
      name:
          'external_transfers_${DateTime.now().toIso8601String().substring(0, 10)}',
      bytes: Uint8List.fromList(utf8.encode(lines.join('\n'))),
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ExternalTransferDialog(),
    );
    if (result == null) return;
    try {
      await _api.createExternalTransfer(result);
      await _load();
      if (mounted)
        AppAlertService.showSuccess(
          context,
          title: 'تمت الإضافة',
          message: 'تمت إضافة العملية للمتابعة.',
        );
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          title: 'تعذر الحفظ',
          message: ErrorMessageService.sanitize(e),
        );
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExternalTransferDialog(initial: row),
    );
    if (result == null) return;
    try {
      await _api.updateExternalTransfer('${row['id']}', result);
      await _load();
    } catch (e) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: 'تعذر التعديل',
          message: ErrorMessageService.sanitize(e),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العملية'),
        content: const Text('هل تريد حذف سجل التحويل الخارجي؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteExternalTransfer('${row['id']}');
      await _load();
    } catch (e) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: 'تعذر الحذف',
          message: ErrorMessageService.sanitize(e),
        );
      }
    }
  }

  Future<void> _setReview(
    Map<String, dynamic> row,
    String status,
    bool reviewed,
  ) async {
    try {
      await _api.updateExternalTransfer('${row['id']}', {
        'deliveryStatus': status,
        'reviewed': reviewed,
      });
      await _load();
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          title: 'تعذر التحديث',
          message: ErrorMessageService.sanitize(e),
        );
    }
  }

  Future<void> _showReport(String period) async {
    try {
      final body = await _api.getExternalTransfersReport(
        filters: {
          'period': period,
          if (_from != null) 'from': _date(_from!),
          if (_to != null) 'to': _date(_to!),
          if (_employeeId != 'all') 'employeeId': _employeeId,
        },
      );
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(
        (body['rows'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تقرير التحويلات الخارجية'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows
                    .map(
                      (r) => Text(
                        '${r['period']} • ${r['employeeName']} • ${r['transfers']} عملية • ${r['totalAmount']} القيمة • ${r['arrived']} وصلت • ${r['notArrived']} لم تصل',
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          title: 'تعذر التقرير',
          message: ErrorMessageService.sanitize(e),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('متابعة التحويلات الخارجية'),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: ListView(
                  children: [
                    ShwakelCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'التحويلات الخارجية',
                                  style: AppTheme.h3,
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.bar_chart_rounded),
                                tooltip: 'التقرير',
                                onSelected: _showReport,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'day',
                                    child: Text('تقرير يومي'),
                                  ),
                                  PopupMenuItem(
                                    value: 'week',
                                    child: Text('تقرير أسبوعي'),
                                  ),
                                  PopupMenuItem(
                                    value: 'month',
                                    child: Text('تقرير شهري'),
                                  ),
                                ],
                              ),
                              if (_canCreate)
                                FilledButton.icon(
                                  onPressed: _add,
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة عملية'),
                                ),
                              if (_canReview)
                                OutlinedButton.icon(
                                  onPressed: _markDayReviewed,
                                  icon: const Icon(Icons.done_all),
                                  label: const Text('اعتماد مراجعة الفترة'),
                                ),
                              OutlinedButton.icon(
                                onPressed: _rows.isEmpty ? null : _exportCsv,
                                icon: const Icon(Icons.file_download_outlined),
                                label: const Text('تصدير Excel'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _pickDate(true),
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                  _from == null ? 'من تاريخ' : _date(_from!),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _pickDate(false),
                                icon: const Icon(Icons.event),
                                label: Text(
                                  _to == null ? 'إلى تاريخ' : _date(_to!),
                                ),
                              ),
                              if (_from != null || _to != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _from = null;
                                      _to = null;
                                    });
                                    _load();
                                  },
                                  child: const Text('مسح التاريخ'),
                                ),
                              _metric('العدد', '${_totals['count'] ?? 0}'),
                              _metric('القيمة', '${_totals['amount'] ?? 0}'),
                              _metric(
                                'غير مراجعة',
                                '${_totals['unreviewed'] ?? 0}',
                              ),
                              _metric(
                                'لم تصل',
                                '${_totals['notArrived'] ?? 0}',
                              ),
                              DropdownButton<String>(
                                value: _status,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('كل الحالات'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pending',
                                    child: Text('قيد المتابعة'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'arrived',
                                    child: Text('وصلت'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'not_arrived',
                                    child: Text('لم تصل'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _status = v);
                                    _load();
                                  }
                                },
                              ),
                              DropdownButton<String>(
                                value: _reviewed,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('كل المراجعات'),
                                  ),
                                  DropdownMenuItem(
                                    value: '0',
                                    child: Text('غير مراجعة'),
                                  ),
                                  DropdownMenuItem(
                                    value: '1',
                                    child: Text('تمت المراجعة'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _reviewed = v);
                                    _load();
                                  }
                                },
                              ),
                              if (!_isSubUser && _employees.length > 1)
                                DropdownButton<String>(
                                  value: _employeeId,
                                  hint: const Text('التابع / المنفذ'),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'all',
                                      child: Text('كل التابعين'),
                                    ),
                                    ..._employees.map(
                                      (employee) => DropdownMenuItem(
                                        value: '${employee['id']}',
                                        child: Text(
                                          employee['name']?.toString() ??
                                              'مستخدم',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _employeeId = v);
                                      _load();
                                    }
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_rows.isEmpty)
                      ShwakelCard(
                        padding: const EdgeInsets.all(24),
                        child: const Center(
                          child: Text('لا توجد تحويلات خارجية مسجلة.'),
                        ),
                      ),
                    ..._rows.map(_row),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _metric(String label, String value) =>
      Chip(label: Text('$label: $value'));

  Widget _row(Map<String, dynamic> row) {
    final status = row['delivery_status']?.toString() ?? 'pending';
    final reviewed = row['reviewed'] == true || row['reviewed'] == 1;
    final statusText = switch (status) {
      'arrived' => 'وصلت',
      'not_arrived' => 'لم تصل',
      _ => 'معلقة',
    };
    final statusColor = switch (status) {
      'arrived' => Colors.green,
      'not_arrived' => Colors.red,
      _ => Colors.blue,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShwakelCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${row['beneficiary_name'] ?? ''} — ${row['beneficiary_mobile'] ?? ''}',
                    style: AppTheme.bodyBold,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${row['amount'] ?? 0}',
                      style: AppTheme.bodyBold.copyWith(
                        fontSize: 18,
                        color: AppTheme.primary,
                      ),
                    ),
                    const Text(
                      'القيمة',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Chip(
                      avatar: Icon(
                        status == 'arrived'
                            ? Icons.check_circle
                            : status == 'not_arrived'
                            ? Icons.cancel
                            : Icons.schedule,
                        size: 16,
                        color: statusColor,
                      ),
                      label: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: statusColor.withValues(alpha: 0.35),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (_canManage) ...[
                  IconButton(
                    onPressed: () => _edit(row),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'تعديل',
                  ),
                  IconButton(
                    onPressed: () => _delete(row),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'حذف',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${row['destination_name'] ?? ''} • ${row['destination_account'] ?? ''}',
            ),
            Text(
              'بواسطة: ${row['created_by_name'] ?? ''} • ${row['notes'] ?? ''}',
              style: AppTheme.caption,
            ),
            if (_canReview)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('قيد المتابعة'),
                    selected: status == 'pending',
                    onSelected: (_) => _setReview(row, 'pending', reviewed),
                  ),
                  ChoiceChip(
                    label: const Text('وصلت'),
                    selected: status == 'arrived',
                    onSelected: (_) => _setReview(row, 'arrived', true),
                  ),
                  ChoiceChip(
                    label: const Text('لم تصل'),
                    selected: status == 'not_arrived',
                    onSelected: (_) => _setReview(row, 'not_arrived', true),
                  ),
                  FilterChip(
                    label: const Text('تمت المراجعة'),
                    selected: reviewed,
                    onSelected: (v) => _setReview(row, status, v),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ExternalTransferDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _ExternalTransferDialog({this.initial});
  @override
  State<_ExternalTransferDialog> createState() =>
      _ExternalTransferDialogState();
}

class _ExternalTransferDialogState extends State<_ExternalTransferDialog> {
  final name = TextEditingController();
  final mobile = TextEditingController();
  final amount = TextEditingController();
  final destination = TextEditingController();
  final account = TextEditingController();
  final notes = TextEditingController();
  String type = 'bank';

  @override
  void initState() {
    super.initState();
    final row = widget.initial;
    if (row != null) {
      name.text = '${row['beneficiary_name'] ?? ''}';
      mobile.text = '${row['beneficiary_mobile'] ?? ''}';
      amount.text = '${row['amount'] ?? ''}';
      destination.text = '${row['destination_name'] ?? ''}';
      account.text = '${row['destination_account'] ?? ''}';
      notes.text = '${row['notes'] ?? ''}';
      type = '${row['destination_type'] ?? 'bank'}';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      mobile,
      amount,
      destination,
      account,
      notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    Widget field(Widget child) => wide ? Expanded(child: child) : child;
    Widget gap() => SizedBox(width: wide ? 12 : 0, height: wide ? 0 : 8);
    Widget row(List<Widget> children) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : Column(children: children);

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'إضافة تحويل خارجي' : 'تعديل تحويل خارجي',
      ),
      content: SizedBox(
        width: wide ? 720 : null,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row([
                field(
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستفيد *',
                    ),
                  ),
                ),
                gap(),
                field(
                  TextField(
                    controller: mobile,
                    decoration: const InputDecoration(
                      labelText: 'رقم الجوال *',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              row([
                field(
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'القيمة *'),
                  ),
                ),
                gap(),
                field(
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'الجهة *'),
                    items: const [
                      DropdownMenuItem(value: 'bank', child: Text('بنك')),
                      DropdownMenuItem(value: 'wallet', child: Text('محفظة')),
                      DropdownMenuItem(
                        value: 'jawwal_pay',
                        child: Text('جوال باي'),
                      ),
                      DropdownMenuItem(value: 'palpay', child: Text('بال باي')),
                      DropdownMenuItem(value: 'cash', child: Text('كاش')),
                      DropdownMenuItem(value: 'other', child: Text('أخرى')),
                    ],
                    onChanged: (value) =>
                        setState(() => type = value ?? 'bank'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              row([
                field(
                  TextField(
                    controller: destination,
                    decoration: const InputDecoration(
                      labelText: 'اسم البنك أو المحفظة (اختياري)',
                    ),
                  ),
                ),
                gap(),
                field(
                  TextField(
                    controller: account,
                    decoration: const InputDecoration(
                      labelText: 'رقم الحساب / المحفظة (اختياري)',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final parsedAmount = double.tryParse(amount.text);
            if (name.text.trim().isEmpty ||
                mobile.text.trim().isEmpty ||
                parsedAmount == null)
              return;
            Navigator.pop(context, {
              'beneficiaryName': name.text.trim(),
              'beneficiaryMobile': mobile.text.trim(),
              'amount': parsedAmount,
              'destinationType': type,
              'destinationName': destination.text.trim(),
              'destinationAccount': account.text.trim(),
              'notes': notes.text.trim(),
              'profitMode': 'rate',
              'profitRate': 0,
              'profitFlat': 0,
            });
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
