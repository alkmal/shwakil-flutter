import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final PDFService _pdfService = PDFService();

  List<VirtualCard> _cards = const [];
  CardStatus _filter = CardStatus.unused;
  bool _isLoading = true;
  int _page = 1;
  static const int _perPage = 12;
  int _lastPage = 1;
  int _totalCards = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final statusMap = {
        CardStatus.used: 'used',
        CardStatus.archived: 'archived',
        CardStatus.unused: 'unused',
      };
      final payload = await _apiService.getMyCards(
        status: statusMap[_filter] ?? 'unused',
        page: _page,
        perPage: _perPage,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _cards = List<VirtualCard>.from(payload['cards'] as List? ?? const []);
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _totalCards = (pagination['total'] as num?)?.toInt() ?? _cards.length;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('مخزون البطاقات الرقمية')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              children: [
                _buildHero(),
                const SizedBox(height: 24),
                _buildFilters(),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_cards.isEmpty)
                  _buildEmptyState()
                else ...[
                  _buildGrid(),
                  const SizedBox(height: 32),
                  AdminPaginationFooter(
                    currentPage: _page,
                    lastPage: _lastPage,
                    totalItems: _totalCards,
                    itemsPerPage: _perPage,
                    onPageChanged: (page) {
                      setState(() => _page = page);
                      _load();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.darkGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;
          final iconBox = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Colors.white,
              size: 34,
            ),
          );
          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مخزون البطاقات',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'استعرض البطاقات الصادرة، وأعد طباعتها، أو احذف البطاقات غير المستخدمة عند الحاجة.',
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                ShwakelButton(
                  label: 'طلب طباعة بطاقات',
                  icon: Icons.print_rounded,
                  isSecondary: true,
                  onPressed: () =>
                      Navigator.pushNamed(context, '/card-print-requests'),
                ),
              ],
            ),
          );
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_totalCards بطاقة',
              style: AppTheme.bodyBold.copyWith(color: Colors.white),
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [iconBox, const SizedBox(width: 16), badge]),
                const SizedBox(height: 18),
                content,
              ],
            );
          }

          return Row(
            children: [iconBox, const SizedBox(width: 24), content, badge],
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CardStatus.values.map((status) {
          final label = status == CardStatus.unused
              ? 'جديدة'
              : (status == CardStatus.used ? 'مستخدمة' : 'مؤرشفة');
          final isSelected = _filter == status;
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                if (!selected) return;
                setState(() {
                  _filter = status;
                  _page = 1;
                });
                _load();
              },
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1000
            ? 3
            : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 180,
          ),
          itemCount: _cards.length,
          itemBuilder: (context, index) => _buildCardTile(_cards[index]),
        );
      },
    );
  }

  Widget _buildCardTile(VirtualCard card) {
    final isUnused = card.status == CardStatus.unused;
    final color = isUnused ? AppTheme.success : AppTheme.error;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppTheme.radiusMd,
                ),
                child: Icon(
                  isUnused
                      ? Icons.credit_card_rounded
                      : Icons.check_circle_rounded,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(CurrencyFormatter.ils(card.value), style: AppTheme.h3),
                    Text(
                      card.barcode,
                      style: AppTheme.caption.copyWith(letterSpacing: 1.5),
                    ),
                  ],
                ),
              ),
              _buildPopup(card),
            ],
          ),
          const Spacer(),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${card.createdAt.day}/${card.createdAt.month}/${card.createdAt.year}',
                style: AppTheme.caption,
              ),
              if (card.usedBy != null)
                Expanded(
                  child: Text(
                    card.usedBy!,
                    style: AppTheme.bodyBold.copyWith(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                    textAlign: TextAlign.left,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopup(VirtualCard card) => PopupMenuButton<String>(
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (value) => value == 'print' ? _reprint(card) : _delete(card.id),
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'print',
        child: Row(
          children: [
            Icon(Icons.print_rounded, size: 18),
            SizedBox(width: 8),
            Text('طباعة'),
          ],
        ),
      ),
      if (card.status == CardStatus.unused)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: AppTheme.error),
              SizedBox(width: 8),
              Text(
                'حذف وإرجاع القيمة',
                style: TextStyle(color: AppTheme.error),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _buildEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 64,
            color: AppTheme.textTertiary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'لا توجد بطاقات في هذا القسم',
            style: AppTheme.h3.copyWith(color: AppTheme.textTertiary),
          ),
        ],
      ),
    ),
  );

  Future<void> _reprint(VirtualCard card) async {
    final user = await _authService.currentUser();
    await _pdfService.printCards([
      card,
    ], printedBy: user?['username'] ?? 'شواكل');
    if (mounted) {
      AppAlertService.showSuccess(context, message: 'تم إرسال الطلب للطباعة.');
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف نهائي؟'),
        content: const Text('سيتم حذف البطاقة وإعادة الرصيد لحسابك فورًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ShwakelButton(
            label: 'حذف',
            onPressed: () => Navigator.pop(dialogContext, true),
            isSecondary: true,
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _apiService.deleteCard(id);
      await _load();
      if (mounted) {
        AppAlertService.showSuccess(
          context,
          message: 'تم حذف البطاقة وإرجاع القيمة.',
        );
      }
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    }
  }
}
