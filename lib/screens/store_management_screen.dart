import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key});

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _auth = AuthService();
  final _store = StoreManagementService();
  late final TabController _tabs = TabController(length: 5, vsync: this)
    ..addListener(() => setState(() {}));
  Map<String, dynamic>? _user;
  Map<String, dynamic> _snapshot = const {};
  List<Map<String, dynamic>> _pending = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  AppPermissions get _permissions => AppPermissions.fromUser(_user);
  String get _userId => _user?['id']?.toString() ?? '';
  List<Map<String, dynamic>> get _products => _list(_snapshot['products']);
  List<Map<String, dynamic>> get _parties => _list(_snapshot['parties']);
  List<Map<String, dynamic>> get _invoices => _list(_snapshot['invoices']);
  List<Map<String, dynamic>> get _debtBookAccounts =>
      _list(_snapshot['debtBookAccounts']);
  Map<String, dynamic> get _summary => _snapshot['summary'] is Map
      ? Map<String, dynamic>.from(_snapshot['summary'] as Map)
      : const {};
  String get _syncedAt => _snapshot['syncedAt']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = await _auth.currentUser();
      final permissions = AppPermissions.fromUser(user);
      if (!permissions.canAccessStoreManagement) {
        if (!mounted) return;
        setState(() {
          _user = user;
          _loading = false;
          _error = 'لا تملك صلاحية الدخول إلى إدارة المحل.';
        });
        return;
      }
      final userId = user?['id']?.toString() ?? '';
      final local = await _store.getSnapshot(userId);
      final pending = await _store.getPendingOperations(userId);
      if (mounted) {
        setState(() {
          _user = user;
          _snapshot = local;
          _pending = pending;
          _loading = local.isEmpty;
        });
      }
      await _sync();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  Future<void> _sync() async {
    if (_userId.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final snapshot = await _store.syncPending(userId: _userId, api: _api);
      final pending = await _store.getPendingOperations(_userId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _pending = pending;
        _loading = false;
        _syncing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _syncing = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  Future<void> _showLocalThenSync() async {
    final local = await _store.getSnapshot(_userId);
    final pending = await _store.getPendingOperations(_userId);
    if (mounted) {
      setState(() {
        _snapshot = local;
        _pending = pending;
        _loading = false;
      });
    }
    await _sync();
  }

  Future<void> _addProduct() async {
    final name = TextEditingController();
    final barcode = TextEditingController();
    final factor = TextEditingController(text: '24');
    final salePrice = TextEditingController(text: '0');
    String baseUnit = 'piece';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة صنف جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'اسم الصنف'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: baseUnit,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة الأساسية',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'piece', child: Text('حبة')),
                    DropdownMenuItem(value: 'kg', child: Text('كيلو')),
                    DropdownMenuItem(value: 'liter', child: Text('لتر')),
                    DropdownMenuItem(value: 'box', child: Text('صندوق')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => baseUnit = value ?? 'piece'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: factor,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد الوحدات في الكرتونة',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: barcode,
                  decoration: const InputDecoration(
                    labelText: 'باركود الكرتونة',
                    suffixIcon: Icon(Icons.qr_code_scanner_rounded),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      final value = await _scanBarcode(
                        title: 'قراءة باركود الصنف',
                        description:
                            'وجه الكاميرا إلى باركود الكرتونة أو الوحدة.',
                      );
                      if (value != null) {
                        barcode.text = value;
                      }
                    },
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('قراءة من الكاميرا'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: salePrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'سعر بيع الوحدة الأساسية',
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
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      final packageFactor = double.tryParse(factor.text) ?? 1;
      final price = double.tryParse(salePrice.text) ?? 0;
      await _store.queueProduct(
        userId: _userId,
        name: name.text,
        baseUnit: baseUnit,
        minimumStock: 0,
        salePrice: price,
        units: [
          {
            'name': _unitName(baseUnit),
            'code': baseUnit,
            'factorToBase': 1,
            'isBase': true,
            'salePrice': price,
          },
          if (packageFactor > 1)
            {
              'name': 'كرتونة',
              'code': 'carton',
              'factorToBase': packageFactor,
              'barcode': barcode.text.trim(),
              'salePrice': price * packageFactor,
            },
        ],
      );
      await _showLocalThenSync();
    }
    name.dispose();
    barcode.dispose();
    factor.dispose();
    salePrice.dispose();
  }

  Future<void> _addParty() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    String type = 'customer';
    String? selectedDebtBookAccountId;
    String debtSearch = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = debtSearch.trim().toLowerCase();
          final debtAccounts = _debtBookAccounts
              .where((account) {
                if (query.isEmpty) return true;
                final haystack =
                    '${account['fullName'] ?? ''} ${account['phone'] ?? ''}'
                        .toLowerCase();
                return haystack.contains(query);
              })
              .take(30)
              .toList();

          void applyDebtAccount(String? id) {
            selectedDebtBookAccountId = id;
            if (id == null) return;
            final account = _debtBookAccounts.firstWhere(
              (item) => item['id']?.toString() == id,
              orElse: () => const {},
            );
            if (account.isEmpty) return;
            name.text = (account['fullName'] ?? '').toString();
            phone.text = (account['phone'] ?? '').toString();
          }

          return AlertDialog(
            title: const Text('إضافة زبون أو تاجر'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'نوع الحساب',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'customer',
                          child: Text('زبون'),
                        ),
                        DropdownMenuItem(
                          value: 'supplier',
                          child: Text('تاجر'),
                        ),
                        DropdownMenuItem(
                          value: 'both',
                          child: Text('زبون وتاجر'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => type = value ?? 'customer'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث في دفتر الديون',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => debtSearch = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedDebtBookAccountId,
                      decoration: const InputDecoration(
                        labelText: 'اعتماد حساب من دفتر الديون',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('حساب جديد غير مربوط'),
                        ),
                        ...debtAccounts.map(
                          (account) => DropdownMenuItem<String?>(
                            value: account['id']?.toString(),
                            child: Text(
                              '${account['fullName'] ?? ''} • ${account['phone'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => applyDebtAccount(value)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'الاسم'),
                    ),
                    TextField(
                      controller: phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      await _store.queueParty(
        userId: _userId,
        type: type,
        name: name.text,
        phone: phone.text,
        debtBookCustomerId: selectedDebtBookAccountId,
      );
      await _showLocalThenSync();
    }
    name.dispose();
    phone.dispose();
  }

  Future<String?> _scanBarcode({
    required String title,
    required String description,
  }) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => BarcodeScannerDialog(
        title: title,
        description: description,
        showFrame: true,
      ),
    );
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> _createInvoice() async {
    if (_products.isEmpty) return;
    String invoiceType = _permissions.canCreateStoreSales ? 'sale' : 'purchase';
    String? partyId;
    String? manualProductId = _products.first['id']?.toString();
    String paymentStatus = 'paid';
    final paid = TextEditingController(text: '0');
    final discount = TextEditingController(text: '0');
    final lines = <Map<String, dynamic>>[];

    Map<String, dynamic> productById(String? id) => _products.firstWhere(
      (item) => item['id']?.toString() == id,
      orElse: () => _products.first,
    );

    Map<String, dynamic>? firstUnit(Map<String, dynamic> product) {
      final units = _list(product['units']);
      return units.isEmpty ? null : units.first;
    }

    double defaultPrice(
      Map<String, dynamic> product,
      Map<String, dynamic>? unit,
    ) {
      final factor = (unit?['factorToBase'] as num?)?.toDouble() ?? 1;
      if (invoiceType == 'sale') {
        return (unit?['salePrice'] as num?)?.toDouble() ??
            (product['defaultSalePrice'] as num?)?.toDouble() ??
            0;
      }
      return (unit?['purchasePrice'] as num?)?.toDouble() ??
          ((product['averagePurchaseCost'] as num?)?.toDouble() ?? 0) * factor;
    }

    double defaultSalePrice(
      Map<String, dynamic> product,
      Map<String, dynamic>? unit,
    ) {
      final factor = (unit?['factorToBase'] as num?)?.toDouble() ?? 1;
      return (unit?['salePrice'] as num?)?.toDouble() ??
          ((product['defaultSalePrice'] as num?)?.toDouble() ?? 0) * factor;
    }

    void addLine(Map<String, dynamic> product, Map<String, dynamic>? unit) {
      final existingIndex = lines.indexWhere(
        (line) =>
            line['productId']?.toString() == product['id']?.toString() &&
            line['unitId']?.toString() == unit?['id']?.toString(),
      );
      if (existingIndex >= 0) {
        lines[existingIndex]['quantity'] =
            ((lines[existingIndex]['quantity'] as num?)?.toDouble() ?? 0) + 1;
        return;
      }
      lines.add({
        'productId': product['id']?.toString(),
        'productClientRef': product['clientRef']?.toString(),
        'unitId': unit?['id']?.toString(),
        'unitClientRef': unit?['clientRef']?.toString(),
        'name': product['name']?.toString() ?? '',
        'unitName':
            unit?['name']?.toString() ??
            _unitName(product['baseUnit']?.toString() ?? ''),
        'quantity': 1.0,
        'unitPrice': defaultPrice(product, unit),
        'salePrice': defaultSalePrice(product, unit),
      });
    }

    Map<String, dynamic>? findByBarcode(String barcode) {
      final normalized = barcode.trim();
      if (normalized.isEmpty) return null;
      for (final product in _products) {
        for (final unit in _list(product['units'])) {
          if ((unit['barcode']?.toString().trim() ?? '') == normalized) {
            return {'product': product, 'unit': unit};
          }
        }
      }
      return null;
    }

    addLine(
      productById(manualProductId),
      firstUnit(productById(manualProductId)),
    );

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allowedParties = _parties.where((party) {
            final type = party['type']?.toString();
            return invoiceType == 'sale'
                ? type == 'customer' || type == 'both'
                : type == 'supplier' || type == 'both';
          }).toList();
          final subtotal = lines.fold<double>(
            0,
            (sum, line) =>
                sum +
                (((line['quantity'] as num?)?.toDouble() ?? 0) *
                    ((line['unitPrice'] as num?)?.toDouble() ?? 0)),
          );
          final discountValue = double.tryParse(discount.text) ?? 0;
          final invoiceTotal = (subtotal - discountValue)
              .clamp(0, subtotal)
              .toDouble();

          Future<void> scanIntoInvoice() async {
            final barcode = await _scanBarcode(
              title: 'قراءة باركود الصنف',
              description: 'امسح باركود المنتج ليتم إضافته للفاتورة مباشرة.',
            );
            if (barcode == null) return;
            final match = findByBarcode(barcode);
            if (match == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('لا يوجد صنف بهذا الباركود: $barcode'),
                  ),
                );
              }
              return;
            }
            setDialogState(
              () => addLine(
                Map<String, dynamic>.from(match['product'] as Map),
                match['unit'] is Map
                    ? Map<String, dynamic>.from(match['unit'] as Map)
                    : null,
              ),
            );
          }

          void refreshPricesForType() {
            for (final line in lines) {
              final product = productById(line['productId']?.toString());
              final unit = _list(product['units']).firstWhere(
                (item) => item['id']?.toString() == line['unitId']?.toString(),
                orElse: () => firstUnit(product) ?? const <String, dynamic>{},
              );
              line['unitPrice'] = defaultPrice(product, unit);
              line['salePrice'] = defaultSalePrice(product, unit);
            }
          }

          return AlertDialog(
            title: Text(
              invoiceType == 'sale'
                  ? 'نقطة بيع POS - فاتورة بيع'
                  : 'نقطة شراء - فاتورة مشتريات',
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: [
                        if (_permissions.canCreateStoreSales)
                          const ButtonSegment(
                            value: 'sale',
                            label: Text('بيع'),
                          ),
                        if (_permissions.canCreateStorePurchases)
                          const ButtonSegment(
                            value: 'purchase',
                            label: Text('شراء'),
                          ),
                      ],
                      selected: {invoiceType},
                      onSelectionChanged: (selection) {
                        setDialogState(() {
                          invoiceType = selection.first;
                          partyId = null;
                          refreshPricesForType();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: partyId,
                      decoration: InputDecoration(
                        labelText: invoiceType == 'sale'
                            ? 'الزبون'
                            : 'التاجر المطلوب',
                      ),
                      items: [
                        if (invoiceType == 'sale')
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('زبون نقدي'),
                          ),
                        ...allowedParties.map(
                          (party) => DropdownMenuItem<String?>(
                            value: party['id']?.toString(),
                            child: Text(party['name']?.toString() ?? ''),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => partyId = value),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: manualProductId,
                            decoration: const InputDecoration(
                              labelText: 'إضافة صنف يدويًا',
                            ),
                            items: _products
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item['id']?.toString(),
                                    child: Text(item['name']?.toString() ?? ''),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setDialogState(() => manualProductId = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => setDialogState(() {
                            final product = productById(manualProductId);
                            addLine(product, firstUnit(product));
                          }),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('إضافة'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: scanIntoInvoice,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('باركود'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (lines.isEmpty)
                      const Text('أضف صنفًا واحدًا على الأقل للفاتورة.')
                    else
                      ...lines.asMap().entries.map((entry) {
                        final index = entry.key;
                        final line = entry.value;
                        final lineTotal =
                            ((line['quantity'] as num?)?.toDouble() ?? 0) *
                            ((line['unitPrice'] as num?)?.toDouble() ?? 0);
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${line['name']} • ${line['unitName']}',
                                        style: AppTheme.bodyBold,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setDialogState(
                                        () => lines.removeAt(index),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                          'qty-$index-${line['quantity']}',
                                        ),
                                        initialValue:
                                            ((line['quantity'] as num?)
                                                        ?.toDouble() ??
                                                    1)
                                                .toString(),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          labelText: 'الكمية',
                                        ),
                                        onChanged: (value) => setDialogState(
                                          () => line['quantity'] =
                                              double.tryParse(value) ?? 0,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey(
                                          'price-$index-${line['unitPrice']}',
                                        ),
                                        initialValue:
                                            ((line['unitPrice'] as num?)
                                                        ?.toDouble() ??
                                                    0)
                                                .toStringAsFixed(2),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: invoiceType == 'sale'
                                              ? 'سعر البيع'
                                              : 'سعر الشراء',
                                        ),
                                        onChanged: (value) => setDialogState(
                                          () => line['unitPrice'] =
                                              double.tryParse(value) ?? 0,
                                        ),
                                      ),
                                    ),
                                    if (invoiceType == 'purchase' &&
                                        _permissions.canEditStorePrices) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          key: ValueKey(
                                            'sale-$index-${line['salePrice']}',
                                          ),
                                          initialValue:
                                              ((line['salePrice'] as num?)
                                                          ?.toDouble() ??
                                                      0)
                                                  .toStringAsFixed(2),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'سعر البيع لاحقًا',
                                          ),
                                          onChanged: (value) => setDialogState(
                                            () => line['salePrice'] =
                                                double.tryParse(value) ?? 0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('المجموع: ${_money(lineTotal)}'),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 10),
                    TextField(
                      controller: discount,
                      onChanged: (_) => setDialogState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'خصم'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: paymentStatus,
                      decoration: const InputDecoration(
                        labelText: 'حالة الفاتورة',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text('مدفوعة بالكامل'),
                        ),
                        DropdownMenuItem(
                          value: 'partial',
                          child: Text('مدفوعة جزئيًا'),
                        ),
                        DropdownMenuItem(
                          value: 'debt',
                          child: Text('دين بالكامل'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => paymentStatus = value ?? 'paid'),
                    ),
                    if (paymentStatus == 'partial') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: paid,
                        onChanged: (_) => setDialogState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المدفوع',
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'الإجمالي: ${_money(invoiceTotal)}',
                        style: AppTheme.h3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed:
                    lines.isEmpty ||
                        (invoiceType == 'purchase' && partyId == null)
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ الفاتورة'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted == true) {
      final subtotal = lines.fold<double>(
        0,
        (sum, line) =>
            sum +
            (((line['quantity'] as num?)?.toDouble() ?? 0) *
                ((line['unitPrice'] as num?)?.toDouble() ?? 0)),
      );
      final discountValue = double.tryParse(discount.text) ?? 0;
      final invoiceTotal = (subtotal - discountValue)
          .clamp(0, subtotal)
          .toDouble();
      final paidAmount = paymentStatus == 'paid'
          ? invoiceTotal
          : paymentStatus == 'partial'
          ? double.tryParse(paid.text) ?? 0
          : 0.0;
      final selectedParty = _parties.firstWhere(
        (party) => party['id']?.toString() == partyId,
        orElse: () => const <String, dynamic>{},
      );
      await _store.queueInvoice(
        userId: _userId,
        invoiceType: invoiceType,
        partyId: partyId,
        partyClientRef: selectedParty['clientRef']?.toString(),
        paidAmount: paidAmount,
        paymentMethod: 'cash',
        discount: discountValue,
        items: lines
            .map(
              (line) => {
                'productId': line['productId'],
                'productClientRef': line['productClientRef'],
                'productUnitId': line['unitId'],
                'unitClientRef': line['unitClientRef'],
                'quantity': (line['quantity'] as num?)?.toDouble() ?? 0,
                'unitPrice': (line['unitPrice'] as num?)?.toDouble() ?? 0,
                if (invoiceType == 'purchase')
                  'salePrice': (line['salePrice'] as num?)?.toDouble() ?? 0,
              },
            )
            .toList(),
      );
      await _showLocalThenSync();
    }
    paid.dispose();
    discount.dispose();
  }

  Future<void> _recordInvoicePayment(Map<String, dynamic> invoice) async {
    final due = (invoice['dueAmount'] as num?)?.toDouble() ?? 0;
    if (due <= 0 || !_permissions.canManageStoreDebts) return;
    final amount = TextEditingController(text: due.toStringAsFixed(2));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تسجيل دفعة ${invoice['invoiceNumber']}'),
        content: TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'المبلغ المدفوع',
            helperText: 'المتبقي ${_money(due)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
    final value = double.tryParse(amount.text) ?? 0;
    amount.dispose();
    if (accepted == true && value > 0) {
      await _store.queuePayment(
        userId: _userId,
        invoiceId: invoice['id']?.toString(),
        invoiceClientRef: invoice['clientRef']?.toString(),
        partyId: invoice['partyId']?.toString(),
        partyClientRef: _parties
            .firstWhere(
              (party) =>
                  party['id']?.toString() == invoice['partyId']?.toString(),
              orElse: () => const <String, dynamic>{},
            )['clientRef']
            ?.toString(),
        direction: invoice['type'] == 'purchase' ? 'out' : 'in',
        amount: value,
      );
      await _showLocalThenSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _snapshot['workspace'] is Map
        ? Map<String, dynamic>.from(_snapshot['workspace'] as Map)
        : const <String, dynamic>{};
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(workspace['name']?.toString() ?? 'إدارة المحل'),
        actions: [
          IconButton(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          const QuickLogoutAction(),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'الرئيسية', icon: Icon(Icons.dashboard_rounded)),
            Tab(text: 'المخزون', icon: Icon(Icons.inventory_2_rounded)),
            Tab(text: 'الفواتير', icon: Icon(Icons.receipt_long_rounded)),
            Tab(text: 'الحسابات', icon: Icon(Icons.people_alt_rounded)),
            Tab(text: 'التقارير', icon: Icon(Icons.insights_rounded)),
          ],
        ),
      ),
      drawer: const AppSidebar(),
      floatingActionButton:
          _tabs.index == 1 && _permissions.canManageStoreInventory
          ? FloatingActionButton.extended(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('صنف جديد'),
            )
          : _tabs.index == 3 && _permissions.canManageStoreDebts
          ? FloatingActionButton.extended(
              onPressed: _addParty,
              icon: const Icon(Icons.person_add),
              label: const Text('حساب جديد'),
            )
          : _tabs.index == 2 &&
                (_permissions.canCreateStoreSales ||
                    _permissions.canCreateStorePurchases)
          ? FloatingActionButton.extended(
              onPressed: _createInvoice,
              icon: const Icon(Icons.receipt_long),
              label: const Text('فاتورة جديدة'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  if (_pending.isNotEmpty)
                    ShwakelCard(
                      color: AppTheme.warning.withValues(alpha: 0.08),
                      borderColor: AppTheme.warning.withValues(alpha: 0.24),
                      child: ListTile(
                        leading: const Icon(
                          Icons.cloud_upload_rounded,
                          color: AppTheme.warning,
                        ),
                        title: Text(
                          '${_pending.length} عمليات محفوظة محليًا بانتظار المزامنة',
                        ),
                        subtitle: const Text(
                          'ستظهر البيانات محليًا وتُرسل للسيرفر فور توفر الاتصال بدون حذف قائمة الانتظار إلا بعد نجاح المزامنة.',
                        ),
                        trailing: TextButton.icon(
                          onPressed: _syncing ? null : _sync,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('مزامنة الآن'),
                        ),
                      ),
                    )
                  else if (_syncedAt.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        avatar: const Icon(Icons.verified_rounded, size: 18),
                        label: Text('آخر مزامنة: $_syncedAt'),
                        backgroundColor: AppTheme.success.withValues(
                          alpha: 0.10,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _dashboard(),
                        _productsView(),
                        _invoicesView(),
                        _partiesView(),
                        _reportsView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dashboard() {
    final cards = [
      ('مبيعات اليوم', _money(_summary['salesToday']), Icons.point_of_sale),
      if (_permissions.canViewStoreProfits)
        ('أرباح اليوم', _money(_summary['profitToday']), Icons.trending_up),
      ('قيمة المخزون', _money(_summary['inventoryValue']), Icons.warehouse),
      ('ديون الزبائن', _money(_summary['customerDebts']), Icons.person),
      ('ديون التجار', _money(_summary['supplierDebts']), Icons.local_shipping),
    ];
    return ListView(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (card) => SizedBox(
                  width: 220,
                  child: ShwakelCard(
                    child: ListTile(
                      leading: Icon(card.$3, color: AppTheme.primary),
                      title: Text(card.$1),
                      subtitle: Text(card.$2, style: AppTheme.h3),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        Text('الفاتورة هي مصدر المخزون والدين والربح', style: AppTheme.h3),
        const SizedBox(height: 6),
        const Text(
          'الشراء يزيد المخزون ويحدث متوسط التكلفة ودين التاجر، والبيع يخصم المخزون ويحسب الربح ودين الزبون تلقائيًا.',
        ),
      ],
    );
  }

  Widget _productsView() => _products.isEmpty
      ? _empty('لا توجد أصناف بعد')
      : ListView.builder(
          itemCount: _products.length,
          itemBuilder: (context, index) {
            final item = _products[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
              title: Text(item['name']?.toString() ?? ''),
              subtitle: Text(
                'المتوفر: ${item['stockQuantity'] ?? 0} ${_unitName(item['baseUnit']?.toString() ?? '')}',
              ),
              trailing: Text(_money(item['defaultSalePrice'])),
              isThreeLine: _isLocalRecord(item),
              dense: false,
            );
          },
        );

  Widget _invoicesView() => _invoices.isEmpty
      ? _empty('لا توجد فواتير بعد')
      : ListView.builder(
          itemCount: _invoices.length,
          itemBuilder: (context, index) {
            final item = _invoices[index];
            return ListTile(
              leading: Icon(
                item['type'] == 'sale'
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
              ),
              title: Text('${item['invoiceNumber']} • ${item['partyName']}'),
              subtitle: Text(
                'المتبقي: ${_money(item['dueAmount'])} • ${_syncLabel(item)}',
              ),
              trailing: Text(_money(item['total'])),
              onTap: () => _recordInvoicePayment(item),
            );
          },
        );

  Widget _partiesView() => _parties.isEmpty
      ? _empty('لا توجد حسابات زبائن أو تجار')
      : ListView.builder(
          itemCount: _parties.length,
          itemBuilder: (context, index) {
            final item = _parties[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(item['name']?.toString() ?? ''),
              subtitle: Text(
                'عليه: ${_money(item['receivableBalance'])} • له: ${_money(item['payableBalance'])} • ${_syncLabel(item)}',
              ),
              trailing: Text(item['phone']?.toString() ?? ''),
            );
          },
        );

  Widget _reportsView() {
    final now = DateTime.now();
    final sales = _invoices.where((item) => item['type'] == 'sale').toList();
    double salesIn(Duration duration) => sales
        .where((item) {
          final date = DateTime.tryParse(item['occurredAt']?.toString() ?? '');
          return date != null && now.difference(date) <= duration;
        })
        .fold(
          0,
          (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0),
        );
    final yearSales = sales
        .where((item) {
          final date = DateTime.tryParse(item['occurredAt']?.toString() ?? '');
          return date != null && date.year == now.year;
        })
        .fold(
          0.0,
          (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0),
        );
    final profit = sales.fold(
      0.0,
      (sum, item) => sum + ((item['profitTotal'] as num?)?.toDouble() ?? 0),
    );
    final soldByProduct = <String, double>{};
    final soldNames = <String, String>{};
    for (final invoice in sales) {
      for (final item in _list(invoice['items'])) {
        final id = item['productId']?.toString() ?? '';
        if (id.isEmpty) continue;
        soldByProduct[id] =
            (soldByProduct[id] ?? 0) +
            ((item['baseQuantity'] as num?)?.toDouble() ?? 0);
        soldNames[id] = item['productName']?.toString() ?? id;
      }
    }
    final bestSellers = soldByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final stagnant = _products
        .where(
          (product) => !soldByProduct.containsKey(product['id']?.toString()),
        )
        .take(8)
        .toList();
    final lowStock = _products.where((product) {
      final min = (product['minimumStock'] as num?)?.toDouble() ?? 0;
      final stock = (product['stockQuantity'] as num?)?.toDouble() ?? 0;
      return min > 0 && stock <= min;
    }).toList();

    return ListView(
      children: [
        _reportTile('مبيعات اليوم', _money(salesIn(const Duration(days: 1)))),
        _reportTile('مبيعات الأسبوع', _money(salesIn(const Duration(days: 7)))),
        _reportTile('مبيعات الشهر', _money(salesIn(const Duration(days: 31)))),
        _reportTile('مبيعات السنة', _money(yearSales)),
        if (_permissions.canViewStoreProfits)
          _reportTile('إجمالي الأرباح الظاهرة', _money(profit)),
        _reportTile('قيمة المخزون', _money(_summary['inventoryValue'])),
        _reportTile('ديون الزبائن', _money(_summary['customerDebts'])),
        _reportTile('ديون التجار', _money(_summary['supplierDebts'])),
        const Divider(),
        ListTile(
          title: const Text('أكثر الأصناف مبيعًا'),
          subtitle: Text(
            bestSellers.take(5).isEmpty
                ? 'لا توجد مبيعات بعد'
                : bestSellers
                      .take(5)
                      .map(
                        (entry) => '${soldNames[entry.key]} (${entry.value})',
                      )
                      .join('، '),
          ),
        ),
        ListTile(
          title: const Text('الأصناف الراكدة'),
          subtitle: Text(
            stagnant.isEmpty
                ? 'لا توجد أصناف راكدة'
                : stagnant.map((item) => item['name']).join('، '),
          ),
        ),
        ListTile(
          title: const Text('المخزون المنخفض'),
          subtitle: Text(
            lowStock.isEmpty
                ? 'كل الأصناف أعلى من حد التنبيه'
                : lowStock.map((item) => item['name']).join('، '),
          ),
        ),
        const ListTile(
          title: Text('حركة المستخدمين'),
          subtitle: Text(
            'تُحفظ كل عمليات الإضافة والفواتير والدفعات في سجل النشاط على السيرفر.',
          ),
        ),
      ],
    );
  }

  Widget _reportTile(String title, String value) => ListTile(
    title: Text(title),
    trailing: Text(value, style: AppTheme.bodyBold),
  );

  Widget _empty(String title) => Center(
    child: Text(title, style: AppTheme.h3, textAlign: TextAlign.center),
  );

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _money(dynamic value) =>
      '${((value as num?)?.toDouble() ?? 0).toStringAsFixed(2)} ₪';

  static bool _isLocalRecord(Map<String, dynamic> item) =>
      (item['id']?.toString().startsWith('local:') ?? false) ||
      (item['syncStatus']?.toString() == 'pending');

  static String _syncLabel(Map<String, dynamic> item) =>
      _isLocalRecord(item) ? 'محلي بانتظار المزامنة' : 'مزامن';

  static String _unitName(String code) => switch (code) {
    'piece' => 'حبة',
    'carton' => 'كرتونة',
    'pallet' => 'مشطاح',
    'kg' => 'كيلو',
    'liter' => 'لتر',
    'box' => 'صندوق',
    _ => code,
  };
}
