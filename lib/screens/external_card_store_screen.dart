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
  final ApiService _api = ApiService();
  final TextEditingController _categorySearchController =
      TextEditingController();

  bool _isLoading = true;
  bool _isLoadingCards = false;
  bool _isPurchasing = false;
  int _categoryId = 2;
  final int _type = 2;
  double _usdToIlsRate = 3.5;
  double _profitPercent = 3;
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _orders = const [];
  Map<String, dynamic>? _selectedCategory;
  String _categorySearch = '';

  @override
  void initState() {
    super.initState();
    _categorySearchController.addListener(() {
      setState(() => _categorySearch = _categorySearchController.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _categorySearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        _api.getExternalCardStoreCatalog(categoryId: 2, type: _type),
        _api.getExternalCardStoreOrders(),
      ]);
      final payload = Map<String, dynamic>.from(results[0] as Map);
      final orders = List<Map<String, dynamic>>.from(results[1] as List);
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(
          (payload['categories'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        if (_selectedCategory == null) {
          _cards = const [];
        }
        _orders = orders;
        _usdToIlsRate = (payload['cards'] as List? ?? const []).isNotEmpty
            ? ((payload['cards'] as List).first as Map)['usdToIlsRate'] is num
                  ? (((payload['cards'] as List).first as Map)['usdToIlsRate']
                            as num)
                        .toDouble()
                  : 3.5
            : 3.5;
        _profitPercent = (payload['cards'] as List? ?? const []).isNotEmpty
            ? ((payload['cards'] as List).first as Map)['profitPercent'] is num
                  ? (((payload['cards'] as List).first as Map)['profitPercent']
                            as num)
                        .toDouble()
                  : 3
            : 3;
        _isLoading = false;
      });
      if (_selectedCategory != null) {
        await _loadCardsForCategory(
          int.tryParse(_selectedCategory!['id']?.toString() ?? '') ??
              _categoryId,
          category: _selectedCategory,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      await _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _loadCardsForCategory(
    int categoryId, {
    Map<String, dynamic>? category,
  }) async {
    setState(() {
      _isLoadingCards = true;
      _categoryId = categoryId;
      if (category != null) {
        _selectedCategory = category;
      }
    });

    try {
      final cards = await _api.getExternalCardStoreCards(
        categoryId: categoryId,
        type: _type,
      );
      if (!mounted) return;
      setState(() {
        _cards = cards;
        if (cards.isNotEmpty) {
          _usdToIlsRate =
              (cards.first['usdToIlsRate'] as num?)?.toDouble() ??
              _usdToIlsRate;
          _profitPercent =
              (cards.first['profitPercent'] as num?)?.toDouble() ??
              _profitPercent;
        }
        _isLoadingCards = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cards = const [];
        _isLoadingCards = false;
      });
      await _showMessage(error.toString(), isError: true);
    }
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
    final convertedPrice = (card['convertedPrice'] as num?)?.toDouble() ?? 0;
    final profitAmount = (card['profitAmount'] as num?)?.toDouble() ?? 0;
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
              'سعر المزود',
              '\$ ${providerPriceUsd.toStringAsFixed(2)}',
            ),
            _confirmPriceRow(
              'بعد التحويل',
              CurrencyFormatter.ils(convertedPrice),
            ),
            _confirmPriceRow(
              'ربح ${_profitPercent.toStringAsFixed(2)}%',
              CurrencyFormatter.ils(profitAmount),
            ),
            const Divider(height: 22),
            _confirmPriceRow(
              'المبلغ المخصوم',
              CurrencyFormatter.ils(finalPrice),
              emphasized: true,
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
        localAuthMethod: security.method,
      );
      if (!mounted) return;
      await _showMessage(
        payload['message']?.toString() ?? 'تم شراء البطاقة بنجاح.',
      );
      await _load();
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
        title: const Text('متجر البطاقات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _isLoading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
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
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildCategorySearch(),
                      const SizedBox(height: 14),
                      _buildCategories(),
                      const SizedBox(height: 18),
                      _buildCards(),
                      const SizedBox(height: 18),
                      _buildOrders(),
                    ],
                  ),
                ),
              ),
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
              Expanded(child: Text('بطاقاتي المشتراة', style: AppTheme.h3)),
              IconButton(
                tooltip: 'تحديث المشتريات',
                onPressed: _isLoading ? null : () => _load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_orders.isEmpty)
            Text('لا توجد بطاقات مشتراة حتى الآن.', style: AppTheme.bodyAction)
          else
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
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> order) {
    final details = Map<String, dynamic>.from(
      order['cardDetails'] as Map? ?? const {},
    );
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
              Icon(
                pending
                    ? Icons.hourglass_top_rounded
                    : Icons.confirmation_number_rounded,
                color: pending ? AppTheme.warning : AppTheme.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order['title']?.toString() ?? 'بطاقة',
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$status · ${CurrencyFormatter.ils(amount)}',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pending)
            Text(
              'بيانات البطاقة غير متوفرة من المزود حتى الآن، وسيتم عرضها هنا عند توفرها.',
              style: AppTheme.bodyAction.copyWith(color: AppTheme.warning),
            )
          else ...[
            if ((details['code']?.toString() ?? '').isNotEmpty)
              _detailRow('الكود', details['code'].toString()),
            if ((details['pin']?.toString() ?? '').isNotEmpty)
              _detailRow('PIN', details['pin'].toString()),
            if ((details['link']?.toString() ?? '').isNotEmpty)
              _detailRow('الرابط', details['link'].toString()),
            if ((details['expiresAt']?.toString() ?? '').isNotEmpty)
              _detailRow('الصلاحية', details['expiresAt'].toString()),
          ],
          const SizedBox(height: 8),
          Text(
            'المرجع: ${order['referenceId']?.toString() ?? '-'}',
            style: AppTheme.caption,
          ),
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

  Widget _buildHeader() {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('بطاقات خارجية فورية', style: AppTheme.h3),
                const SizedBox(height: 4),
                Text(
                  'اختر القسم ثم البطاقة، وسيتم الخصم من رصيدك وتسجيل الحركة المالية والإشعار مباشرة.',
                  style: AppTheme.bodyAction.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text('الدولار ${_usdToIlsRate.toStringAsFixed(2)}₪'),
                avatar: const Icon(Icons.currency_exchange_rounded, size: 18),
              ),
              Chip(
                label: Text('ربح ${_profitPercent.toStringAsFixed(2)}%'),
                avatar: const Icon(Icons.percent_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    final normalizedSearch = _categorySearch.toLowerCase();
    final visibleCategories = normalizedSearch.isEmpty
        ? _categories
        : _categories.where((category) {
            final title = (category['title']?.toString() ?? '').toLowerCase();
            return title.contains(normalizedSearch);
          }).toList();

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('الأقسام', style: AppTheme.h3)),
              Text('${visibleCategories.length} قسم', style: AppTheme.caption),
            ],
          ),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            Text('لا توجد أقسام متاحة حالياً.', style: AppTheme.bodyAction)
          else if (visibleCategories.isEmpty)
            Text('لا يوجد قسم بهذا الاسم.', style: AppTheme.bodyAction)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 980 ? 4 : (width >= 680 ? 3 : 2);
                return GridView.builder(
                  itemCount: visibleCategories.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: columns == 2 ? 0.92 : 0.98,
                  ),
                  itemBuilder: (context, index) =>
                      _categoryTile(visibleCategories[index]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySearch() {
    return TextField(
      controller: _categorySearchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'ابحث باسم القسم',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _categorySearch.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                onPressed: _categorySearchController.clear,
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

  Widget _categoryTile(Map<String, dynamic> category) {
    final id = int.tryParse(category['id']?.toString() ?? '') ?? 2;
    final title = category['title']?.toString() ?? 'قسم';
    final description = (category['description']?.toString() ?? '').trim();
    final selected = _selectedCategory?['id']?.toString() == id.toString();

    return InkWell(
      onTap: _isLoadingCards
          ? null
          : () => _loadCardsForCategory(id, category: category),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.4 : 1,
          ),
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
                        ? 'اضغط لعرض البطاقات المتاحة في هذا القسم.'
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

  Widget _buildCards() {
    if (_selectedCategory == null) {
      return ShwakelCard(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.touch_app_rounded,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'اختر قسماً من الأعلى لعرض البطاقات المتاحة داخله.',
                style: AppTheme.bodyAction.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingCards) {
      return const ShwakelCard(
        padding: EdgeInsets.all(28),
        borderRadius: BorderRadius.all(Radius.circular(22)),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_cards.isEmpty) {
      return ShwakelCard(
        padding: const EdgeInsets.all(28),
        borderRadius: BorderRadius.circular(22),
        child: Center(
          child: Text(
            'لا توجد بطاقات متاحة في قسم ${_selectedCategory?['title'] ?? 'هذا القسم'}.',
            style: AppTheme.h3,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'بطاقات ${_selectedCategory?['title'] ?? 'القسم'}',
                  style: AppTheme.h3,
                ),
              ),
              Text('${_cards.length} بطاقة', style: AppTheme.caption),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1040 ? 3 : (width >= 680 ? 2 : 1);
              return GridView.builder(
                itemCount: _cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 1 ? 1.22 : 0.82,
                ),
                itemBuilder: (context, index) => _cardTile(_cards[index]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cardTile(Map<String, dynamic> card) {
    final title = card['title']?.toString() ?? 'بطاقة';
    final providerPriceUsd =
        (card['providerPriceUsd'] as num?)?.toDouble() ?? 0;
    final convertedPrice = (card['convertedPrice'] as num?)?.toDouble() ?? 0;
    final profitAmount = (card['profitAmount'] as num?)?.toDouble() ?? 0;
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
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
                  const Spacer(),
                  _priceBreakdown(
                    providerPriceUsd: providerPriceUsd,
                    convertedPrice: convertedPrice,
                    profitAmount: profitAmount,
                    finalPrice: finalPrice,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isPurchasing ? null : () => _purchase(card),
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
          ),
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

  Widget _priceBreakdown({
    required double providerPriceUsd,
    required double convertedPrice,
    required double profitAmount,
    required double finalPrice,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _compactPriceRow(
            'سعر المزود',
            '\$ ${providerPriceUsd.toStringAsFixed(2)}',
          ),
          _compactPriceRow(
            'بالشيكل',
            CurrencyFormatter.ils(convertedPrice),
            note: '× ${_usdToIlsRate.toStringAsFixed(2)}',
          ),
          _compactPriceRow(
            'الربح',
            CurrencyFormatter.ils(profitAmount),
            note: '${_profitPercent.toStringAsFixed(2)}%',
          ),
          const Divider(height: 16),
          _compactPriceRow(
            'السعر النهائي',
            CurrencyFormatter.ils(finalPrice),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _compactPriceRow(
    String label,
    String value, {
    String? note,
    bool emphasized = false,
  }) {
    final style = emphasized ? AppTheme.bodyBold : AppTheme.caption;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          if (note != null) ...[
            Text(note, style: AppTheme.caption),
            const SizedBox(width: 8),
          ],
          Text(value, style: style),
        ],
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
}
