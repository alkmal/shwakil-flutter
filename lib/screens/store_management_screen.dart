import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
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
  Map<String, dynamic> get _summary => _snapshot['summary'] is Map
      ? Map<String, dynamic>.from(_snapshot['summary'] as Map)
      : const {};

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
      await _sync();
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة زبون أو تاجر'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('زبون')),
                  DropdownMenuItem(value: 'supplier', child: Text('تاجر')),
                  DropdownMenuItem(value: 'both', child: Text('زبون وتاجر')),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? 'customer'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
            ],
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
      await _store.queueParty(
        userId: _userId,
        type: type,
        name: name.text,
        phone: phone.text,
      );
      await _sync();
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _createInvoice() async {
    if (_products.isEmpty) return;
    String invoiceType = _permissions.canCreateStoreSales ? 'sale' : 'purchase';
    String? productId = _products.first['id']?.toString();
    String? partyId;
    String paymentStatus = 'paid';
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController();
    final salePrice = TextEditingController();
    final paid = TextEditingController(text: '0');

    Map<String, dynamic> product() => _products.firstWhere(
      (item) => item['id']?.toString() == productId,
      orElse: () => _products.first,
    );

    Map<String, dynamic>? unit() {
      final units = _list(product()['units']);
      return units.isEmpty ? null : units.first;
    }

    void applyDefaultPrice() {
      final selectedProduct = product();
      final selectedUnit = unit();
      final value = invoiceType == 'sale'
          ? (selectedUnit?['salePrice'] as num?)?.toDouble() ??
                (selectedProduct['defaultSalePrice'] as num?)?.toDouble() ??
                0
          : (selectedUnit?['purchasePrice'] as num?)?.toDouble() ??
                (selectedProduct['averagePurchaseCost'] as num?)?.toDouble() ??
                0;
      price.text = value.toStringAsFixed(2);
      salePrice.text =
          ((selectedUnit?['salePrice'] as num?)?.toDouble() ??
                  (selectedProduct['defaultSalePrice'] as num?)?.toDouble() ??
                  0)
              .toStringAsFixed(2);
    }

    applyDefaultPrice();
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
          final invoiceTotal =
              (double.tryParse(quantity.text) ?? 0) *
              (double.tryParse(price.text) ?? 0);
          return AlertDialog(
            title: Text(
              invoiceType == 'sale' ? 'فاتورة بيع جديدة' : 'فاتورة شراء جديدة',
            ),
            content: SizedBox(
              width: 540,
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
                          applyDefaultPrice();
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
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(labelText: 'الصنف'),
                      items: _products
                          .map(
                            (item) => DropdownMenuItem(
                              value: item['id']?.toString(),
                              child: Text(item['name']?.toString() ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          productId = value;
                          applyDefaultPrice();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quantity,
                            onChanged: (_) => setDialogState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'الكمية',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: price,
                            onChanged: (_) => setDialogState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: invoiceType == 'sale'
                                  ? 'سعر البيع'
                                  : 'سعر الشراء',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (invoiceType == 'purchase' &&
                        _permissions.canEditStorePrices) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: salePrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سعر البيع الذي سيظهر تلقائيًا لاحقًا',
                        ),
                      ),
                    ],
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
                onPressed: invoiceType == 'purchase' && partyId == null
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
      final selectedProduct = product();
      final selectedUnit = unit();
      final invoiceTotal =
          (double.tryParse(quantity.text) ?? 0) *
          (double.tryParse(price.text) ?? 0);
      final paidAmount = paymentStatus == 'paid'
          ? invoiceTotal
          : paymentStatus == 'partial'
          ? double.tryParse(paid.text) ?? 0
          : 0.0;
      await _store.queueInvoice(
        userId: _userId,
        invoiceType: invoiceType,
        partyId: partyId,
        paidAmount: paidAmount,
        paymentMethod: 'cash',
        items: [
          {
            'productId': selectedProduct['id'],
            'productUnitId': selectedUnit?['id'],
            'quantity': double.tryParse(quantity.text) ?? 0,
            'unitPrice': double.tryParse(price.text) ?? 0,
            if (invoiceType == 'purchase')
              'salePrice': double.tryParse(salePrice.text) ?? 0,
          },
        ],
      );
      await _sync();
    }
    quantity.dispose();
    price.dispose();
    salePrice.dispose();
    paid.dispose();
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
        partyId: invoice['partyId']?.toString(),
        direction: invoice['type'] == 'purchase' ? 'out' : 'in',
        amount: value,
      );
      await _sync();
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
                    Text(
                      '${_pending.length} عمليات محفوظة بانتظار المزامنة',
                      style: const TextStyle(color: AppTheme.warning),
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
              subtitle: Text('المتبقي: ${_money(item['dueAmount'])}'),
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
                'عليه: ${_money(item['receivableBalance'])} • له: ${_money(item['payableBalance'])}',
              ),
              trailing: Text(item['phone']?.toString() ?? ''),
            );
          },
        );

  Widget _reportsView() => ListView(
    children: const [
      ListTile(title: Text('المبيعات اليومية والأسبوعية والشهرية')),
      ListTile(title: Text('الأرباح وتكلفة البضاعة المباعة')),
      ListTile(title: Text('الأصناف الأكثر مبيعًا والراكدة')),
      ListTile(title: Text('المخزون المنخفض وقيمة المخزون')),
      ListTile(title: Text('ديون الزبائن والتجار')),
      ListTile(title: Text('حركة المستخدمين والموظفين')),
    ],
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
