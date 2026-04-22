import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';

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
  bool _isAuthorized = false;
  bool _canRequestCardPrinting = false;
  int _page = 1;
  static const int _perPage = 12;
  int _lastPage = 1;
  int _totalCards = 0;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(user);
      if (!permissions.canViewInventory) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
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
      final cards = List<VirtualCard>.from(
        payload['cards'] as List? ?? const [],
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = true;
        _canRequestCardPrinting = permissions.canRequestCardPrinting;
        _cards = cards;
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _totalCards = (pagination['total'] as num?)?.toInt() ?? _cards.length;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_inventory_screen.001')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  l.tr('screens_inventory_screen.015'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_inventory_screen.001')),
        actions: [
          if (_canRequestCardPrinting)
            IconButton(
              tooltip: l.tr('screens_inventory_screen.003'),
              onPressed: () =>
                  Navigator.pushNamed(context, '/card-print-requests'),
              icon: const Icon(Icons.print_rounded),
            ),
          IconButton(
            tooltip: _showFilters
                ? l.tr('screens_inventory_screen.016')
                : l.tr('screens_inventory_screen.017'),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            icon: Icon(
              _showFilters
                  ? Icons.filter_alt_off_rounded
                  : Icons.filter_alt_rounded,
            ),
          ),
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              children: [
                if (_showFilters) ...[
                  _buildFilters(),
                  const SizedBox(height: 16),
                ] else ...[
                  ToolToggleHint(
                    message: l.tr('screens_inventory_screen.018'),
                    icon: Icons.filter_alt_rounded,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_cards.isEmpty)
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

  Future<void> _showHelpDialog() {
    final l = context.loc;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_inventory_screen.001')),
        content: Text(
          l.tr('screens_inventory_screen.019'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.tr('screens_admin_customers_screen.046')),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHero() {
    final l = context.loc;
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
                  l.tr('screens_inventory_screen.002'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_inventory_screen.014'),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 18),
                if (_canRequestCardPrinting)
                  ShwakelButton(
                    label: l.tr('screens_inventory_screen.003'),
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
              l.tr(
                'screens_inventory_screen.004',
                params: {'totalCards': '$_totalCards'},
              ),
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
    final l = context.loc;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CardStatus.values.map((status) {
          final label = status == CardStatus.unused
              ? l.tr('screens_inventory_screen.005')
              : (status == CardStatus.used
                    ? l.tr('screens_inventory_screen.006')
                    : l.tr('screens_inventory_screen.007'));
          final isSelected = _filter == status;
          return Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                if (!selected) {
                  return;
                }
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
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    final categoryLabel = isLocationSpecific
        ? l.tr('screens_scan_card_screen.065')
        : (card.isPrivate
              ? l.tr('screens_scan_card_screen.066')
              : l.tr('screens_scan_card_screen.067'));

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
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        borderRadius: AppTheme.radiusMd,
                      ),
                      child: Text(
                        categoryLabel,
                        style: AppTheme.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                        ),
                      ),
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

  Widget _buildPopup(VirtualCard card) {
    final l = context.loc;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) =>
          value == 'print' ? _reprint(card) : _delete(card.id),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              const Icon(Icons.print_rounded, size: 18),
              const SizedBox(width: 8),
              Text(l.tr('screens_inventory_screen.008')),
            ],
          ),
        ),
        if (card.status == CardStatus.unused)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  l.tr('screens_inventory_screen.009'),
                  style: const TextStyle(color: AppTheme.error),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final l = context.loc;
    return Center(
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
              l.tr('screens_inventory_screen.015'),
              style: AppTheme.h3.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reprint(VirtualCard card) async {
    final l = context.loc;
    final user = await _authService.currentUser();
    await _pdfService.printCards([
      card,
    ], printedBy: user?['username'] ?? l.tr('screens_inventory_screen.010'));
    if (mounted) {
      AppAlertService.showSuccess(
        context,
        message: l.tr('screens_inventory_screen.016'),
      );
    }
  }

  Future<void> _delete(String id) async {
    final l = context.loc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_inventory_screen.011')),
        content: Text(l.tr('screens_inventory_screen.017')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('screens_inventory_screen.012')),
          ),
          ShwakelButton(
            label: l.tr('screens_inventory_screen.013'),
            onPressed: () => Navigator.pop(dialogContext, true),
            isSecondary: true,
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _apiService.deleteCard(id);
      await _load();
      if (mounted) {
        AppAlertService.showSuccess(
          context,
          message: l.tr('screens_inventory_screen.018'),
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
