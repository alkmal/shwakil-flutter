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

  bool _isLoading = true;
  bool _isPurchasing = false;
  int _categoryId = 2;
  final int _type = 2;
  double _usdToIlsRate = 3.5;
  double _profitPercent = 3;
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({int? categoryId}) async {
    setState(() {
      _isLoading = true;
      if (categoryId != null) {
        _categoryId = categoryId;
      }
    });

    try {
      final results = await Future.wait<dynamic>([
        _api.getExternalCardStoreCatalog(
          categoryId: _categoryId,
          type: _type,
        ),
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
        _cards = List<Map<String, dynamic>>.from(
          (payload['cards'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _orders = orders;
        _usdToIlsRate =
            (payload['cards'] as List? ?? const []).isNotEmpty
                ? ((payload['cards'] as List).first as Map)['usdToIlsRate']
                          is num
                      ? (((payload['cards'] as List).first
                                as Map)['usdToIlsRate'] as num)
                            .toDouble()
                      : 3.5
                : 3.5;
        _profitPercent =
            (payload['cards'] as List? ?? const []).isNotEmpty
                ? ((payload['cards'] as List).first as Map)['profitPercent']
                          is num
                      ? (((payload['cards'] as List).first
                                as Map)['profitPercent'] as num)
                            .toDouble()
                      : 3
                : 3;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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
    final status = order['statusLabel']?.toString() ??
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
          SizedBox(
            width: 80,
            child: Text(label, style: AppTheme.caption),
          ),
          Expanded(
            child: SelectableText(value, style: AppTheme.bodyBold),
          ),
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
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الأقسام الفرعية', style: AppTheme.h3),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            Text('لا توجد أقسام فرعية.', style: AppTheme.bodyAction)
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.map((category) {
                final id = int.tryParse(category['id']?.toString() ?? '') ?? 2;
                return ChoiceChip(
                  selected: id == _categoryId,
                  label: Text(category['title']?.toString() ?? 'قسم'),
                  onSelected: (_) => _load(categoryId: id),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCards() {
    if (_cards.isEmpty) {
      return ShwakelCard(
        padding: const EdgeInsets.all(28),
        borderRadius: BorderRadius.circular(22),
        child: Center(
          child: Text('لا توجد بطاقات متاحة في هذا القسم.', style: AppTheme.h3),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980 ? 3 : (width >= 640 ? 2 : 1);
        return GridView.builder(
          itemCount: _cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: columns == 1 ? 2.1 : 1.45,
          ),
          itemBuilder: (context, index) => _cardTile(_cards[index]),
        );
      },
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

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (available ? AppTheme.success : AppTheme.warning)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (available ? AppTheme.success : AppTheme.warning)
                      .withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    available
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    size: 15,
                    color: available ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    availabilityLabel,
                    style: AppTheme.caption.copyWith(
                      color: available ? AppTheme.success : AppTheme.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text('السعر النهائي', style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(CurrencyFormatter.ils(finalPrice), style: AppTheme.h2),
          const SizedBox(height: 2),
          Text(
            '\$ ${providerPriceUsd.toStringAsFixed(2)} × ${_usdToIlsRate.toStringAsFixed(2)} + ${CurrencyFormatter.ils(profitAmount)} ربح',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
          Text(
            'بعد التحويل ${CurrencyFormatter.ils(convertedPrice)}',
            style: AppTheme.caption,
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
                  : const Icon(Icons.shopping_cart_checkout_rounded),
              label: Text(available ? 'شراء مباشر' : 'غير متوفرة'),
            ),
          ),
        ],
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
