import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class PublicStoresScreen extends StatefulWidget {
  const PublicStoresScreen({super.key});

  @override
  State<PublicStoresScreen> createState() => _PublicStoresScreenState();
}

class _PublicStoresScreenState extends State<PublicStoresScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _stores = const [];
  Map<String, dynamic>? _selectedStore;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _buyerOrders = const [];
  final Map<String, double> _cart = {};
  bool _isLoading = true;
  bool _isLoadingStore = false;
  bool _isSubmitting = false;
  String _search = '';
  String? _error;

  AppPermissions get _permissions => AppPermissions.fromUser(_user);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _search) {
      return;
    }
    setState(() => _search = next);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadStores);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await _auth.currentUser();
      if (!mounted) {
        return;
      }
      _user = user;
      if (!_permissions.canViewPublicStores) {
        setState(() {
          _stores = const [];
          _isLoading = false;
          _error = 'لا تملك صلاحية عرض المتاجر العامة.';
        });
        return;
      }
      await Future.wait([_loadStores(showLoading: false), _loadBuyerOrders()]);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  Future<void> _loadStores({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final response = await _api.getPublicStores(query: _search);
      final stores = List<Map<String, dynamic>>.from(
        (response['stores'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _stores = stores;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  Future<void> _loadBuyerOrders() async {
    if (!_permissions.canBuyPublicStoreProducts) {
      return;
    }
    final response = await _api.getBuyerPublicStoreOrders();
    if (!mounted) {
      return;
    }
    setState(() {
      _buyerOrders = List<Map<String, dynamic>>.from(
        (response['orders'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
    });
  }

  Future<void> _openStore(Map<String, dynamic> store) async {
    setState(() {
      _selectedStore = store;
      _products = const [];
      _cart.clear();
      _isLoadingStore = true;
      _error = null;
    });
    try {
      final id = store['id']?.toString() ?? '';
      final response = await _api.getPublicStore(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedStore = Map<String, dynamic>.from(
          response['store'] as Map? ?? store,
        );
        _products = List<Map<String, dynamic>>.from(
          (response['products'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _isLoadingStore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingStore = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  void _backToStores() {
    setState(() {
      _selectedStore = null;
      _products = const [];
      _cart.clear();
      _error = null;
    });
  }

  void _setQuantity(Map<String, dynamic> product, double quantity) {
    final id = product['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    final max = _maxQuantity(product);
    final normalized = quantity.clamp(0, max).toDouble();
    setState(() {
      if (normalized <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = normalized;
      }
    });
  }

  double _number(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _maxQuantity(Map<String, dynamic> product) {
    final available = _number(product['stockQuantity']);
    final publicMax = _number(product['publicMaxQuantity']);
    if (publicMax > 0 && publicMax < available) {
      return publicMax;
    }
    return available;
  }

  double get _cartTotal {
    var total = 0.0;
    for (final product in _products) {
      final id = product['id']?.toString() ?? '';
      final quantity = _cart[id] ?? 0;
      total += quantity * _number(product['salePrice']);
    }
    return total;
  }

  int get _cartItemsCount => _cart.values.where((value) => value > 0).length;

  Future<void> _submitOrder() async {
    final store = _selectedStore;
    if (store == null || _cart.isEmpty || _isSubmitting) {
      return;
    }
    if (!_permissions.canBuyPublicStoreProducts) {
      _showSnack('لا تملك صلاحية الشراء من المتاجر العامة.');
      return;
    }
    final minTotal = _number(store['publicMinOrderTotal']);
    if (minTotal > 0 && _cartTotal < minTotal) {
      _showSnack(
        'الحد الأدنى للطلب ${CurrencyFormatter.formatAmount(minTotal)}.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final items = _cart.entries
          .where((entry) => entry.value > 0)
          .map((entry) => {'productId': entry.key, 'quantity': entry.value})
          .toList();
      final response = await _api.createPublicStoreOrder(
        workspaceId: store['id']?.toString() ?? '',
        items: items,
      );
      if (!mounted) {
        return;
      }
      _showSnack(
        response['message']?.toString() ??
            'تم إرسال الطلب للتاجر بانتظار التأكيد.',
      );
      await _openStore(store);
      await _loadBuyerOrders();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _receiveOrder(String orderId) async {
    try {
      await _api.updatePublicStoreOrder(orderId: orderId, action: 'receive');
      await _loadBuyerOrders();
      _showSnack('تم تأكيد استلام الطلب.');
    } catch (error) {
      _showSnack(ErrorMessageService.sanitize(error));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final content = ResponsiveScaffoldContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 18),
          if (_error != null) _errorBanner(_error!),
          if (_selectedStore == null) _storesView() else _storeProductsView(),
        ],
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المتاجر'),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const Drawer(
          child: AppSidebar(currentRouteName: '/public-stores'),
        ),
        body: RefreshIndicator(
          onRefresh: _selectedStore == null
              ? _loadStores
              : () => _openStore(_selectedStore!),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final store = _selectedStore;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              store == null
                  ? Icons.store_mall_directory_rounded
                  : Icons.storefront_rounded,
              color: AppTheme.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store == null
                      ? 'متاجر التجار والمحلات'
                      : (store['name']?.toString() ?? 'المتجر'),
                  style: AppTheme.h2,
                ),
                const SizedBox(height: 6),
                Text(
                  store == null
                      ? 'اعرض المتاجر المسموح ظهورها واشترِ حسب الكمية المتاحة.'
                      : (store['description']?.toString().trim().isNotEmpty ==
                                true
                            ? store['description'].toString()
                            : 'منتجات متاحة للبيع من هذا المتجر.'),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          if (store != null)
            TextButton.icon(
              onPressed: _backToStores,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('رجوع'),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner(String error) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.error.withValues(alpha: .18)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(error, style: AppTheme.bodyText)),
          ],
        ),
      ),
    );
  }

  Widget _storesView() {
    if (!_permissions.canViewPublicStores) {
      return _emptyState('هذه الشاشة غير متاحة حسب صلاحيات حسابك.');
    }
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'ابحث باسم المتجر أو الوصف',
          ),
        ),
        const SizedBox(height: 16),
        if (_buyerOrders.isNotEmpty) ...[
          _buyerOrdersPanel(),
          const SizedBox(height: 16),
        ],
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_stores.isEmpty)
          _emptyState('لا توجد متاجر ظاهرة للعامة حاليًا.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100
                  ? 3
                  : width >= 720
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _stores.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 2.55 : 1.65,
                ),
                itemBuilder: (context, index) => _storeCard(_stores[index]),
              );
            },
          ),
      ],
    );
  }

  Widget _buyerOrdersPanel() {
    final activeCount = _buyerOrders
        .where(
          (order) =>
              !['received', 'cancelled'].contains(order['status']?.toString()),
        )
        .length;
    return ShwakelCard(
      child: ExpansionTile(
        initiallyExpanded: activeCount > 0,
        leading: const Icon(
          Icons.receipt_long_rounded,
          color: AppTheme.primary,
        ),
        title: Text('طلباتي ($activeCount نشطة)'),
        subtitle: const Text('تابع حالة الطلبات وأكد الاستلام عند وصولها.'),
        children: _buyerOrders.map(_buyerOrderTile).toList(),
      ),
    );
  }

  Widget _buyerOrderTile(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? 'pending';
    return ListTile(
      title: Text('${order['orderNumber'] ?? ''} • ${_statusLabel(status)}'),
      subtitle: Text(
        'الإجمالي: ${CurrencyFormatter.formatAmount(_number(order['total']))}',
      ),
      trailing: status == 'shipped'
          ? TextButton(
              onPressed: () => unawaited(_receiveOrder(order['id'].toString())),
              child: const Text('تأكيد الاستلام'),
            )
          : null,
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'accepted' => 'مؤكد',
      'shipped' => 'مرسل',
      'received' => 'مستلم',
      'cancelled' => 'ملغي',
      _ => 'بانتظار التأكيد',
    };
  }

  Widget _storeCard(Map<String, dynamic> store) {
    final productsCount = store['productsCount']?.toString() ?? '0';
    return InkWell(
      onTap: () => _openStore(store),
      borderRadius: BorderRadius.circular(24),
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store['name']?.toString() ?? 'متجر',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                store['description']?.toString().trim().isNotEmpty == true
                    ? store['description'].toString()
                    : 'منتجات متاحة للشراء من خلال التطبيق.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Chip(
                  avatar: const Icon(Icons.inventory_2_rounded, size: 16),
                  label: Text('$productsCount صنف'),
                ),
                const Spacer(),
                const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _storeProductsView() {
    if (_isLoadingStore) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_products.isEmpty) {
      return _emptyState('لا توجد منتجات متاحة للبيع في هذا المتجر.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1180
                ? 4
                : width >= 900
                ? 3
                : width >= 620
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _products.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: columns == 1 ? 2.2 : 1.35,
              ),
              itemBuilder: (context, index) => _productCard(_products[index]),
            );
          },
        ),
        const SizedBox(height: 18),
        _cartSummary(),
      ],
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final id = product['id']?.toString() ?? '';
    final quantity = _cart[id] ?? 0;
    final max = _maxQuantity(product);
    final unit = product['unitName']?.toString() ?? 'وحدة';
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']?.toString() ?? 'صنف',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h3,
                ),
                const SizedBox(height: 8),
                Text(
                  'السعر: ${CurrencyFormatter.formatAmount(_number(product['salePrice']))}',
                  style: AppTheme.bodyText.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'المتاح: ${max.toStringAsFixed(max.truncateToDouble() == max ? 0 : 2)} $unit',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: quantity <= 0
                    ? null
                    : () => _setQuantity(product, quantity - 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    quantity.toStringAsFixed(
                      quantity.truncateToDouble() == quantity ? 0 : 2,
                    ),
                    style: AppTheme.h3,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: max <= 0 || quantity >= max
                    ? null
                    : () => _setQuantity(product, quantity + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cartSummary() {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_checkout_rounded),
              const SizedBox(width: 10),
              Text('$_cartItemsCount أصناف', style: AppTheme.h3),
              const SizedBox(width: 12),
              Text(
                CurrencyFormatter.formatAmount(_cartTotal),
                style: AppTheme.h3,
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _cart.isEmpty || _isSubmitting
                ? null
                : () => unawaited(_submitOrder()),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطلب للتاجر',
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            color: AppTheme.textSecondary.withValues(alpha: .55),
            size: 54,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: AppTheme.bodyText),
        ],
      ),
    );
  }
}
