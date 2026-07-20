import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/transfer_security_service.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class ExternalCardStoreScreen extends StatefulWidget {
  const ExternalCardStoreScreen({super.key});

  @override
  State<ExternalCardStoreScreen> createState() =>
      _ExternalCardStoreScreenState();
}

class _ExternalCardStoreScreenState extends State<ExternalCardStoreScreen> {
  static const int _rootCategoryId = 2;

  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isLoading = true;
  bool _isLoadingCatalog = false;
  bool _isLoadingOrders = false;
  bool _isPurchasing = false;
  bool _isUpdatingSearchProgrammatically = false;
  int _activeTab = 0;
  int _categoryId = _rootCategoryId;
  int _ordersPage = 1;
  int _ordersLastPage = 1;
  int _ordersTotal = 0;
  final int _type = 2;
  List<Map<String, dynamic>> _rootCategories = const [];
  List<Map<String, dynamic>> _rootCards = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _categoryTrail = const [];
  Map<String, dynamic>? _selectedCategory;
  String _search = '';

  bool get _isCategoryScreen => _selectedCategory == null;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_isUpdatingSearchProgrammatically) {
        return;
      }
      setState(() => _search = _searchController.text.trim());
      _scheduleSearch();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _activeTab != 0 || _isLoading || _isLoadingCatalog) {
        return;
      }
      _loadCurrentCatalog();
    });
  }

  Future<void> _loadCurrentCatalog() async {
    final currentCategory = _isCategoryScreen
        ? <String, dynamic>{'id': _rootCategoryId, 'title': 'الأقسام'}
        : _selectedCategory ?? <String, dynamic>{'id': _categoryId};
    await _loadCategoryCatalog(
      _isCategoryScreen ? _rootCategoryId : _categoryId,
      category: currentCategory,
      trail: _isCategoryScreen ? const [] : _categoryTrail,
      preserveScreen: true,
    );
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        _api.getExternalCardStoreCatalog(
          categoryId: _isCategoryScreen ? _rootCategoryId : _categoryId,
          type: _type,
        ),
        _api.getExternalCardStoreOrdersPayload(page: _ordersPage),
      ]);
      final payload = Map<String, dynamic>.from(results[0] as Map);
      final ordersPayload = Map<String, dynamic>.from(results[1] as Map);
      final orders = List<Map<String, dynamic>>.from(
        ordersPayload['orders'] as List? ?? const [],
      );
      final ordersPagination = Map<String, dynamic>.from(
        ordersPayload['pagination'] as Map? ?? const {},
      );
      final categories = _mapList(payload['categories']);
      final cards = _mapList(payload['cards']);

      if (!mounted) return;
      setState(() {
        if (_isCategoryScreen) {
          _rootCategories = categories;
          _rootCards = cards;
          _categories = categories;
          _cards = cards;
        } else {
          _categories = categories;
          _cards = cards;
        }
        _orders = orders;
        _ordersPage = (ordersPagination['currentPage'] as num?)?.toInt() ?? 1;
        _ordersLastPage = (ordersPagination['lastPage'] as num?)?.toInt() ?? 1;
        _ordersTotal =
            (ordersPagination['total'] as num?)?.toInt() ?? orders.length;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _loadOrders({int? page}) async {
    if (_isLoadingOrders) return;
    setState(() => _isLoadingOrders = true);
    try {
      final payload = await _api.getExternalCardStoreOrdersPayload(
        page: page ?? _ordersPage,
      );
      if (!mounted) return;
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      setState(() {
        _orders = List<Map<String, dynamic>>.from(
          payload['orders'] as List? ?? const [],
        );
        _ordersPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
        _ordersLastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _ordersTotal = (pagination['total'] as num?)?.toInt() ?? _orders.length;
        _isLoadingOrders = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingOrders = false);
      await _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _openCategory(Map<String, dynamic> category) async {
    final id =
        int.tryParse(category['id']?.toString() ?? '') ?? _rootCategoryId;
    final nextTrail = [..._categoryTrail, category];
    await _loadCategoryCatalog(id, category: category, trail: nextTrail);
  }

  Future<void> _loadCategoryCatalog(
    int categoryId, {
    required Map<String, dynamic> category,
    required List<Map<String, dynamic>> trail,
    bool preserveScreen = false,
  }) async {
    setState(() {
      _isLoadingCatalog = true;
      _categoryId = categoryId;
      _selectedCategory = preserveScreen && trail.isEmpty ? null : category;
      _categoryTrail = trail;
      if (!preserveScreen) {
        _clearSearchForNavigation();
      }
    });

    try {
      final payload = await _api.getExternalCardStoreCatalog(
        categoryId: categoryId,
        type: _type,
        query: _search,
      );
      if (!mounted) return;
      setState(() {
        _categories = _mapList(payload['categories']);
        _cards = _mapList(payload['cards']);
        _isLoadingCatalog = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categories = const [];
        _cards = const [];
        _isLoadingCatalog = false;
      });
      await _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _goBackOneLevel() async {
    if (_categoryTrail.length <= 1) {
      setState(() {
        _selectedCategory = null;
        _categoryTrail = const [];
        _categoryId = _rootCategoryId;
        _categories = _rootCategories;
        _cards = _rootCards;
        _clearSearchForNavigation();
      });
      return;
    }

    final nextTrail = _categoryTrail.sublist(0, _categoryTrail.length - 1);
    final parent = nextTrail.last;
    final parentId =
        int.tryParse(parent['id']?.toString() ?? '') ?? _rootCategoryId;
    await _loadCategoryCatalog(parentId, category: parent, trail: nextTrail);
  }

  Future<void> _purchase(Map<String, dynamic> card) async {
    final ean = card['ean']?.toString() ?? '';
    if (ean.isEmpty || _isPurchasing) return;
    if (card['available'] == false) {
      await _showMessage(
        card['availabilityLabel']?.toString() ??
            'هذه البطاقة غير متوفرة حالياً لدى المزود، يرجى اختيار بطاقة أخرى.',
        isError: true,
      );
      return;
    }

    final title = card['title']?.toString() ?? 'بطاقة';
    final providerPriceUsd =
        (card['providerPriceUsd'] as num?)?.toDouble() ?? 0;
    final finalPrice =
        (card['finalPrice'] as num?)?.toDouble() ??
        (card['discountedPrice'] as num?)?.toDouble() ??
        (card['price'] as num?)?.toDouble() ??
        0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الشراء'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.bodyBold),
            const SizedBox(height: 12),
            _confirmPriceRow(
              'المبلغ المخصوم',
              CurrencyFormatter.ils(finalPrice),
              emphasized: true,
            ),
            const SizedBox(height: 10),
            Text(
              'سيطلب التطبيق تأكيد العملية بالبصمة أو PIN أو رمز التحقق حسب إعدادات حسابك.',
              style: AppTheme.caption.copyWith(height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.shopping_cart_checkout_rounded),
            label: const Text('شراء الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) return;

    setState(() => _isPurchasing = true);
    try {
      final payload = await _api.purchaseExternalCard(
        ean: ean,
        title: title,
        price: finalPrice,
        providerPriceUsd: providerPriceUsd,
        categoryId: _categoryId,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
        localAuthMethod: security.method,
      );
      if (!mounted) return;
      await _showMessage(
        payload['message']?.toString() ?? 'تم شراء البطاقة بنجاح.',
      );
      setState(() => _activeTab = 1);
      await _loadOrders(page: 1);
    } catch (error) {
      if (!mounted) return;
      await _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('Exception: ', '')),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
      ),
    );
    return Future.value();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _activeTab == 0
              ? (_isCategoryScreen ? 'أقسام المتجر' : 'بطاقات المتجر')
              : 'مشترياتي',
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _isLoading || _isLoadingCatalog ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ResponsiveScaffoldContainer(
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTabs(),
                      const SizedBox(height: 18),
                      if (_activeTab == 0) ...[
                        _buildSearch(),
                        const SizedBox(height: 16),
                        if (_isCategoryScreen)
                          _buildCategoryScreen()
                        else
                          _buildProductScreen(),
                      ] else
                        _buildOrders(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTabs() {
    return ShwakelCard(
      padding: const EdgeInsets.all(6),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          _tabButton(
            label: 'المتجر',
            icon: Icons.storefront_rounded,
            selected: _activeTab == 0,
            onTap: () => setState(() => _activeTab = 0),
          ),
          const SizedBox(width: 6),
          _tabButton(
            label: 'مشترياتي',
            icon: Icons.receipt_long_rounded,
            selected: _activeTab == 1,
            onTap: () {
              setState(() => _activeTab = 1);
              if (_orders.isEmpty) {
                _loadOrders();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.bodyBold.copyWith(
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrail() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ActionChip(
          avatar: const Icon(Icons.home_rounded, size: 16),
          label: const Text('الأقسام'),
          onPressed: _goBackToRoot,
        ),
        for (var index = 0; index < _categoryTrail.length; index++) ...[
          const Icon(Icons.chevron_left_rounded, size: 18),
          ActionChip(
            label: Text(_categoryTrail[index]['title']?.toString() ?? 'قسم'),
            onPressed: index == _categoryTrail.length - 1
                ? null
                : () => _openTrailIndex(index),
          ),
        ],
      ],
    );
  }

  void _goBackToRoot() {
    setState(() {
      _selectedCategory = null;
      _categoryTrail = const [];
      _categoryId = _rootCategoryId;
      _categories = _rootCategories;
      _cards = _rootCards;
      _clearSearchForNavigation();
    });
  }

  Future<void> _openTrailIndex(int index) async {
    final trail = _categoryTrail.sublist(0, index + 1);
    final category = trail.last;
    final id =
        int.tryParse(category['id']?.toString() ?? '') ?? _rootCategoryId;
    await _loadCategoryCatalog(id, category: category, trail: trail);
  }

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: _isCategoryScreen
            ? 'ابحث باسم القسم'
            : 'ابحث باسم القسم الفرعي أو البطاقة',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
      ),
    );
  }

  Widget _buildCategoryScreen() {
    final visibleCategories = _filterItems(_categories);
    final visibleCards = _filterItems(_cards);
    final hasAnyVisible =
        visibleCategories.isNotEmpty || visibleCards.isNotEmpty;

    if (!hasAnyVisible) {
      return ShwakelCard(
        padding: const EdgeInsets.all(28),
        borderRadius: BorderRadius.circular(22),
        child: Center(
          child: Text(
            _search.isEmpty
                ? 'لا توجد أقسام أو بطاقات متاحة حالياً.'
                : 'لا توجد نتيجة مطابقة للبحث.',
            style: AppTheme.h3,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visibleCategories.isNotEmpty) ...[
          _subcategoriesSection(visibleCategories),
          const SizedBox(height: 14),
        ],
        if (visibleCards.isNotEmpty) _cardsSection(visibleCards),
      ],
    );
  }

  Widget _buildProductScreen() {
    if (_isLoadingCatalog) {
      return const ShwakelCard(
        padding: EdgeInsets.all(28),
        borderRadius: BorderRadius.all(Radius.circular(22)),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final visibleCategories = _filterItems(_categories);
    final visibleCards = _filterItems(_cards);
    final hasAnyVisible =
        visibleCategories.isNotEmpty || visibleCards.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeaderCard(
          title: _selectedCategory?['title']?.toString() ?? 'القسم',
          subtitle:
              '${visibleCategories.length} قسم فرعي · ${visibleCards.length} بطاقة',
          onBack: _goBackOneLevel,
        ),
        const SizedBox(height: 14),
        if (!hasAnyVisible)
          ShwakelCard(
            padding: const EdgeInsets.all(28),
            borderRadius: BorderRadius.circular(22),
            child: Center(
              child: Text(
                _search.isEmpty
                    ? 'لا توجد أقسام فرعية أو بطاقات متاحة في هذا القسم حالياً.'
                    : 'لا توجد نتيجة مطابقة للبحث داخل هذا القسم.',
                style: AppTheme.h3,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          if (_categoryTrail.isNotEmpty) ...[
            _buildTrail(),
            const SizedBox(height: 12),
          ],
          if (visibleCategories.isNotEmpty) ...[
            _subcategoriesSection(visibleCategories),
            const SizedBox(height: 14),
          ],
          if (visibleCards.isNotEmpty) _cardsSection(visibleCards),
        ],
      ],
    );
  }

  Widget _sectionHeaderCard({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyBold),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTheme.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subcategoriesSection(List<Map<String, dynamic>> categories) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('الأقسام الفرعية', style: AppTheme.h3)),
              Text('${categories.length} قسم', style: AppTheme.caption),
            ],
          ),
          const SizedBox(height: 12),
          _categoryGrid(categories),
        ],
      ),
    );
  }

  Widget _cardsSection(List<Map<String, dynamic>> cards) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('البطاقات المتاحة', style: AppTheme.h3)),
              Text('${cards.length} بطاقة', style: AppTheme.caption),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width < 680) {
                return Column(
                  children: cards
                      .map(
                        (card) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _cardTile(card),
                        ),
                      )
                      .toList(),
                );
              }

              final columns = width >= 1040 ? 3 : 2;
              return GridView.builder(
                itemCount: cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 430,
                ),
                itemBuilder: (context, index) => _cardTile(cards[index]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _categoryGrid(List<Map<String, dynamic>> categories) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980 ? 4 : (width >= 680 ? 3 : 2);
        return GridView.builder(
          itemCount: categories.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 2 ? 0.92 : 0.98,
          ),
          itemBuilder: (context, index) => _categoryTile(categories[index]),
        );
      },
    );
  }

  Widget _categoryTile(Map<String, dynamic> category) {
    final title = category['title']?.toString() ?? 'قسم';
    final description = (category['description']?.toString() ?? '').trim();

    return InkWell(
      onTap: _isLoadingCatalog ? null : () => _openCategory(category),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _imageBox(
                category['imageUrl']?.toString(),
                icon: Icons.widgets_rounded,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description.isEmpty
                        ? 'اضغط لعرض المحتوى المناسب داخل هذا القسم.'
                        : description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTile(Map<String, dynamic> card) {
    final title = card['title']?.toString() ?? 'بطاقة';
    final finalPrice =
        (card['finalPrice'] as num?)?.toDouble() ??
        (card['price'] as num?)?.toDouble() ??
        0;
    final available = card['available'] != false;
    final availabilityLabel =
        card['availabilityLabel']?.toString() ??
        (available ? 'متوفرة للشراء' : 'غير متوفرة حالياً');
    final description = (card['description']?.toString() ?? '').trim();

    return ShwakelCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 126,
            width: double.infinity,
            child: _imageBox(
              card['imageUrl']?.toString(),
              icon: Icons.confirmation_number_rounded,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyBold.copyWith(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _availabilityBadge(available, availabilityLabel),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(height: 1.35),
                  ),
                ],
                const SizedBox(height: 14),
                _priceBreakdown(finalPrice: finalPrice),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isPurchasing || !available
                        ? null
                        : () => _purchase(card),
                    icon: _isPurchasing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            available
                                ? Icons.shopping_cart_checkout_rounded
                                : Icons.info_outline_rounded,
                          ),
                    label: Text(available ? 'شراء مباشر' : 'غير متوفرة'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrders() {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('مشترياتي', style: AppTheme.h3)),
              Text('$_ordersTotal عملية', style: AppTheme.caption),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'تحديث المشتريات',
                onPressed: _isLoadingOrders ? null : () => _loadOrders(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingOrders)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_orders.isEmpty)
            _emptyState('لا توجد بطاقات مشتراة حتى الآن.')
          else ...[
            Column(
              children: _orders
                  .map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _orderTile(order),
                    ),
                  )
                  .toList(),
            ),
            _ordersPaginationControls(),
          ],
        ],
      ),
    );
  }

  Widget _ordersPaginationControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _ordersPage <= 1 || _isLoadingOrders
                ? null
                : () => _loadOrders(page: _ordersPage - 1),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('السابق'),
          ),
          Expanded(
            child: Text(
              'صفحة $_ordersPage من $_ordersLastPage',
              textAlign: TextAlign.center,
              style: AppTheme.caption,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _ordersPage >= _ordersLastPage || _isLoadingOrders
                ? null
                : () => _loadOrders(page: _ordersPage + 1),
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('التالي'),
          ),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> order) {
    final rawDetails = order['cardDetails'];
    final details = rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : rawDetails is List && rawDetails.isNotEmpty && rawDetails.first is Map
        ? Map<String, dynamic>.from(rawDetails.first as Map)
        : <String, dynamic>{};
    final pending = order['cardPending'] == true;
    final status =
        order['statusLabel']?.toString() ??
        (pending ? 'البطاقة معلقة حالياً' : 'مكتملة');
    final amount = (order['chargedAmount'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (pending ? AppTheme.warning : AppTheme.success)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  pending
                      ? Icons.hourglass_top_rounded
                      : Icons.confirmation_number_rounded,
                  color: pending ? AppTheme.warning : AppTheme.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['title']?.toString() ?? 'بطاقة',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _miniChip(
                          status,
                          pending ? AppTheme.warning : AppTheme.success,
                        ),
                        _miniChip(
                          CurrencyFormatter.ils(amount),
                          AppTheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pending)
            Text(
              'بيانات البطاقة غير متوفرة من المزود حتى الآن، وسيتم عرضها هنا عند توفرها.',
              style: AppTheme.bodyAction.copyWith(color: AppTheme.warning),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _orderDetailsBox(details),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOrderDetails(order, details),
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('عرض بيانات البطاقة وطريقة الاستخدام'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            'المرجع: ${order['referenceId']?.toString() ?? '-'}',
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderDetails(
    Map<String, dynamic> order,
    Map<String, dynamic> details,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(order['title']?.toString() ?? 'بيانات البطاقة'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _orderDetailsBox(details),
                const SizedBox(height: 12),
                Text(
                  'المرجع: ${order['referenceId']?.toString() ?? '-'}',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _orderDetailsBox(Map<String, dynamic> details) {
    final hasDetails = [
      'code',
      'pin',
      'link',
      'expiresAt',
      'instructions',
    ].any((key) => (details[key]?.toString() ?? '').isNotEmpty);
    if (!hasDetails) {
      return Text('لا توجد بيانات إضافية للبطاقة.', style: AppTheme.caption);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((details['code']?.toString() ?? '').isNotEmpty)
            _detailRow('الكود', details['code'].toString()),
          if ((details['pin']?.toString() ?? '').isNotEmpty)
            _detailRow('PIN', details['pin'].toString()),
          if ((details['link']?.toString() ?? '').isNotEmpty)
            _detailRow('الرابط', details['link'].toString()),
          if ((details['expiresAt']?.toString() ?? '').isNotEmpty)
            _detailRow('الصلاحية', details['expiresAt'].toString()),
          if ((details['instructions']?.toString() ?? '').isNotEmpty)
            _detailRow('طريقة الاستخدام', details['instructions'].toString()),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: AppTheme.caption)),
          Expanded(child: SelectableText(value, style: AppTheme.bodyBold)),
        ],
      ),
    );
  }

  Widget _availabilityBadge(bool available, String label) {
    final color = available ? AppTheme.success : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            available ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
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

  Widget _priceBreakdown({required double finalPrice}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: _compactPriceRow(
        'السعر للشراء',
        CurrencyFormatter.ils(finalPrice),
        emphasized: true,
      ),
    );
  }

  Widget _compactPriceRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = emphasized ? AppTheme.bodyBold : AppTheme.caption;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: AppTheme.bodyAction,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _imageBox(String? imageUrl, {required IconData icon}) {
    final url = (imageUrl ?? '').trim();
    if (url.isEmpty) {
      return _imageFallback(icon);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _imageFallback(icon),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _imageFallback(icon, loading: true);
      },
    );
  }

  Widget _imageFallback(IconData icon, {bool loading = false}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppTheme.primary.withValues(alpha: 0.08),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: AppTheme.primary, size: 34),
      ),
    );
  }

  Widget _confirmPriceRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = emphasized ? AppTheme.bodyBold : AppTheme.bodyAction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterItems(List<Map<String, dynamic>> items) {
    final query = _normalizeForSearch(_search);
    if (query.isEmpty) {
      return items;
    }
    return items.where((item) => _matchesSearch(item, query)).toList();
  }

  bool _matchesSearch(Map<String, dynamic> item, String query) {
    final fields = [
      item['title'],
      item['description'],
      item['id'],
      item['ean'],
      item['categoryId'],
    ];
    return fields.any(
      (value) => _normalizeForSearch(value?.toString() ?? '').contains(query),
    );
  }

  String _normalizeForSearch(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    return List<Map<String, dynamic>>.from(
      (value as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  void _clearSearchForNavigation() {
    _isUpdatingSearchProgrammatically = true;
    _searchController.clear();
    _isUpdatingSearchProgrammatically = false;
    _search = '';
  }
}
