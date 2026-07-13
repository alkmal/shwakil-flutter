// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/thermal_card_ticket.dart';
import '../widgets/tool_toggle_hint.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final PDFService _pdfService = PDFService();
  final TextEditingController _creatorController = TextEditingController();
  final TextEditingController _valueMinController = TextEditingController();
  final TextEditingController _valueMaxController = TextEditingController();
  List<VirtualCard> _cards = const [];
  CardStatus _filter = CardStatus.unused;
  bool _isLoading = true;
  bool _isActionInProgress = false;
  bool _isAuthorized = false;
  bool _canRequestCardPrinting = false;
  bool _canPrintCards = false;
  bool _canDeleteCards = false;
  bool _canUseAdminInventory = false;
  bool _canMonitorOfflineWorkflow = false;
  int _page = 1;
  static const int _perPage = 12;
  static const int _adminPerPage = 24;
  int _lastPage = 1;
  int _totalCards = 0;
  int _filteredTotalCards = 0;
  DateTime? _issuedFrom;
  DateTime? _issuedTo;
  bool _isOfflineData = false;
  Set<String> _revealedBarcodes = const <String>{};
  Map<String, dynamic>? _offlineOverview;
  Map<String, dynamic> _summary = const {};
  String _actionStatusMessage = '';
  StateSetter? _inventoryToolsSetState;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inventoryToolsSetState = null;
    _creatorController.dispose();
    _valueMinController.dispose();
    _valueMaxController.dispose();
    super.dispose();
  }

  void _openRoute(String routeName) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      return;
    }
    Navigator.pushNamed(context, routeName);
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final requestedPage = _page;
    try {
      final user = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(user);
      final canUseAdminInventory =
          permissions.canManageUsers || permissions.canManageCardPrintRequests;
      final canMonitorOfflineWorkflow = permissions.canMonitorOfflineCards;
      if (!permissions.canViewInventory && !canUseAdminInventory) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
      final userId = user?['id']?.toString() ?? '';
      final statusMap = {
        CardStatus.used: 'used',
        CardStatus.archived: 'archived',
        CardStatus.unused: 'unused',
      };
      final isOnline = await ConnectivityService.instance.checkNow();
      late final List<VirtualCard> cards;
      late final Map<String, dynamic> pagination;
      late final Map<String, dynamic> summary;
      late final Set<String> revealedBarcodes;
      Map<String, dynamic>? offlineOverview;
      var isOfflineData = false;

      if (!canUseAdminInventory && userId.isNotEmpty && !isOnline) {
        final cachedCards = await _offlineCardService.getCachedCards(userId);
        revealedBarcodes = (await _offlineCardService.getRevealedCards(
          userId,
        )).toSet();
        cards = cachedCards.where((card) {
          switch (_filter) {
            case CardStatus.used:
              return card.status == CardStatus.used;
            case CardStatus.archived:
              return card.status == CardStatus.archived;
            case CardStatus.unused:
              return card.status == CardStatus.unused;
          }
        }).toList();
        pagination = {'lastPage': 1, 'currentPage': 1, 'total': cards.length};
        summary = {
          'total': cachedCards.length,
          'unusedCount': cachedCards
              .where((card) => card.status == CardStatus.unused)
              .length,
          'usedCount': cachedCards
              .where((card) => card.status == CardStatus.used)
              .length,
          'archivedCount': cachedCards
              .where((card) => card.status == CardStatus.archived)
              .length,
        };
        isOfflineData = true;
      } else {
        final payload = canUseAdminInventory
            ? await _apiService.getAdminCards(
                status: statusMap[_filter] ?? 'unused',
                creator: _creatorController.text,
                valueMin: _parseDouble(_valueMinController.text),
                valueMax: _parseDouble(_valueMaxController.text),
                issuedFrom: _formatDate(_issuedFrom),
                issuedTo: _formatDate(_issuedTo),
                page: requestedPage,
                perPage: _adminPerPage,
              )
            : await _apiService.getMyCards(
                status: statusMap[_filter] ?? 'unused',
                page: requestedPage,
                perPage: _perPage,
              );
        cards = List<VirtualCard>.from(payload['cards'] as List? ?? const []);
        pagination = Map<String, dynamic>.from(
          payload['pagination'] as Map? ?? const {},
        );
        summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        if (!canUseAdminInventory && userId.isNotEmpty) {
          await _offlineCardService.cacheCards(userId: userId, cards: cards);
          await _offlineCardService.syncRevealedCards(
            userId,
            currentCards: cards,
            online: true,
          );
          revealedBarcodes = (await _offlineCardService.getRevealedCards(
            userId,
          )).toSet();
        } else {
          revealedBarcodes = <String>{};
        }
      }

      if (userId.isNotEmpty && canMonitorOfflineWorkflow) {
        offlineOverview = await _offlineCardService.offlineOverview(userId);
        final settings = Map<String, dynamic>.from(
          offlineOverview['settings'] as Map? ?? const {},
        );
        settings['revealedCount'] = revealedBarcodes.length;
        offlineOverview = {...offlineOverview, 'settings': settings};
      }

      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage);
      if (requestedPage > lastPage && lastPage > 0) {
        if (!mounted) {
          return;
        }
        setState(() => _page = lastPage);
        await _load();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = true;
        _canRequestCardPrinting = permissions.canRequestCardPrinting;
        _canPrintCards = permissions.canPrintCards;
        _canDeleteCards = permissions.canDeleteCards;
        _canUseAdminInventory = canUseAdminInventory;
        _canMonitorOfflineWorkflow = canMonitorOfflineWorkflow;
        _cards = cards;
        _page = normalizedPage;
        _lastPage = lastPage;
        _filteredTotalCards =
            (pagination['total'] as num?)?.toInt() ?? _cards.length;
        _totalCards =
            (summary['total'] as num?)?.toInt() ??
            (pagination['total'] as num?)?.toInt() ??
            _cards.length;
        _isOfflineData = isOfflineData;
        _revealedBarcodes = revealedBarcodes;
        _offlineOverview = offlineOverview;
        _summary = summary;
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
                Text(l.tr('screens_inventory_screen.015'), style: AppTheme.h3),
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
          IconButton(
            tooltip: l.tr('screens_inventory_screen.018'),
            onPressed: _openInventoryTools,
            icon: const Icon(Icons.tune_rounded),
          ),
          if (_canRequestCardPrinting)
            IconButton(
              tooltip: l.tr('screens_inventory_screen.003'),
              onPressed: () => _openRoute('/card-print-requests'),
              icon: const Icon(Icons.print_rounded),
            ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _inventoryListItemCount,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _inventoryListItemAt(index);
                  switch (item.kind) {
                    case _InventoryListItemKind.overview:
                      return _buildOverviewCard();
                    case _InventoryListItemKind.filters:
                      return _buildFiltersPanel();
                    case _InventoryListItemKind.resultsHeader:
                      return _buildResultsHeader();
                    case _InventoryListItemKind.offlineBanner:
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          context.loc.text(
                            'بطاقات محفوظة محليًا.',
                            'Cards saved locally.',
                          ),
                          style: AppTheme.bodyAction.copyWith(fontSize: 14),
                        ),
                      );
                    case _InventoryListItemKind.offlineFollowup:
                      return _buildOfflineFollowupCard();
                    case _InventoryListItemKind.adminActions:
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ShwakelButton(
                              label: context.loc.text(
                                'إنشاء بطاقة لمستخدم',
                                'Create card for user',
                              ),
                              icon: Icons.add_card_rounded,
                              onPressed: _createAdminCard,
                            ),
                            if (_canPrintCards &&
                                _printableCards(_cards).isNotEmpty)
                              ShwakelButton(
                                label: l.tr('screens_inventory_screen.021'),
                                icon: Icons.print_rounded,
                                onPressed: _reprintFilteredCards,
                                isSecondary: true,
                              ),
                          ],
                        ),
                      );
                    case _InventoryListItemKind.userPrintAction:
                      return Align(
                        alignment: Alignment.centerRight,
                        child: ShwakelButton(
                          label: context.loc.text(
                            'طباعة البطاقات الظاهرة',
                            'Print visible cards',
                          ),
                          icon: Icons.print_rounded,
                          isSecondary: true,
                          onPressed: _reprintFilteredCards,
                        ),
                      );
                    case _InventoryListItemKind.empty:
                      return _buildEmptyState();
                    case _InventoryListItemKind.card:
                      return _buildCardTile(_cards[item.cardIndex]);
                    case _InventoryListItemKind.pagination:
                      return _buildInventoryPagination();
                  }
                },
              ),
            ),
          ),
          if (_isActionInProgress) _buildBusyOverlay(),
        ],
      ),
    );
  }

  int get _inventoryListItemCount => _inventoryListItems.length;

  _InventoryListItem _inventoryListItemAt(int index) =>
      _inventoryListItems[index];

  List<_InventoryListItem> get _inventoryListItems {
    final items = <_InventoryListItem>[];
    if (_isOfflineData) {
      items.add(const _InventoryListItem(_InventoryListItemKind.offlineBanner));
    }
    if (_canMonitorOfflineWorkflow &&
        _offlineOverview != null &&
        !_canUseAdminInventory) {
      items.add(
        const _InventoryListItem(_InventoryListItemKind.offlineFollowup),
      );
    }
    if (_canUseAdminInventory) {
      items.add(const _InventoryListItem(_InventoryListItemKind.adminActions));
    }
    if (!_canUseAdminInventory &&
        _canPrintCards &&
        _printableCards(_cards).isNotEmpty) {
      items.add(
        const _InventoryListItem(_InventoryListItemKind.userPrintAction),
      );
    }
    if (_cards.isEmpty) {
      items.add(const _InventoryListItem(_InventoryListItemKind.empty));
    } else {
      for (var index = 0; index < _cards.length; index++) {
        items.add(
          _InventoryListItem(_InventoryListItemKind.card, cardIndex: index),
        );
      }
      items.add(const _InventoryListItem(_InventoryListItemKind.pagination));
    }
    return items;
  }

  Future<void> _openInventoryTools() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _inventoryToolsSetState = setSheetState;
            return DraggableScrollableSheet(
              initialChildSize: 0.82,
              minChildSize: 0.46,
              maxChildSize: 0.94,
              expand: false,
              builder: (context, scrollController) {
                return DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildOverviewCard(),
                      const SizedBox(height: 12),
                      _buildFiltersPanel(),
                      const SizedBox(height: 12),
                      _buildResultsHeader(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    _inventoryToolsSetState = null;
  }

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.16),
          alignment: Alignment.center,
          child: ShwakelCard(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 14),
                Text(
                  _actionStatusMessage.trim().isEmpty
                      ? 'جارٍ تنفيذ الطلب...'
                      : _actionStatusMessage,
                  style: AppTheme.bodyBold,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmCardOutputSecurity() async {
    final security = await TransferSecurityService.confirmTransfer(context);
    return mounted && security.isVerified;
  }

  Widget _buildOverviewCard() {
    final l = context.loc;
    final unusedCount = (_summary['unusedCount'] as num?)?.toInt() ?? 0;
    final usedCount = (_summary['usedCount'] as num?)?.toInt() ?? 0;
    final archivedCount = (_summary['archivedCount'] as num?)?.toInt() ?? 0;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flex(
                direction: isCompact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isCompact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                  ),
                  SizedBox(
                    width: isCompact ? 0 : 12,
                    height: isCompact ? 10 : 0,
                  ),
                  if (isCompact)
                    Text(
                      l.tr('screens_inventory_screen.002'),
                      style: AppTheme.bodyBold,
                    )
                  else
                    Expanded(
                      child: Text(
                        l.tr('screens_inventory_screen.002'),
                        style: AppTheme.bodyBold,
                      ),
                    ),
                  SizedBox(
                    width: isCompact ? 0 : 12,
                    height: isCompact ? 12 : 0,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_totalCards',
                      style: AppTheme.bodyBold.copyWith(
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildOverviewChip(
                    l.tr('screens_inventory_screen.034'),
                    '$unusedCount',
                    AppTheme.success,
                  ),
                  _buildOverviewChip(
                    l.tr('screens_inventory_screen.035'),
                    '$usedCount',
                    AppTheme.warning,
                  ),
                  _buildOverviewChip(
                    l.tr('screens_inventory_screen.036'),
                    '$archivedCount',
                    AppTheme.error,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ToolToggleHint(
                message: l.tr('screens_inventory_screen.018'),
                icon: Icons.filter_alt_rounded,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return _buildFilters();
  }

  Widget _buildResultsHeader() {
    final label = _statusFilterLabel(_filter);
    final firstItem = _cards.isEmpty
        ? 0
        : ((_page - 1) * (_canUseAdminInventory ? _adminPerPage : _perPage)) +
              1;
    final lastItem = _cards.isEmpty ? 0 : firstItem + _cards.length - 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final title = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _statusFilterIcon(_filter),
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(label, style: AppTheme.bodyBold),
            ],
          );
          final meta = Text(
            _cards.isEmpty
                ? context.loc.text(
                    'لا توجد بطاقات ضمن هذا القسم',
                    'No cards in this section',
                  )
                : '${context.loc.text('عرض', 'Showing')} $firstItem - $lastItem ${context.loc.text('من', 'of')} $_filteredTotalCards',
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 6), meta],
            );
          }
          return Row(children: [title, const Spacer(), meta]);
        },
      ),
    );
  }

  Widget _buildInventoryPagination() {
    final perPage = _canUseAdminInventory ? _adminPerPage : _perPage;
    final l = context.loc;
    final totalText =
        '$_filteredTotalCards ${l.text('بطاقة', 'card')} • ${l.text('صفحة', 'page')} $_page ${l.text('من', 'of')} $_lastPage';
    if (_lastPage <= 1) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          totalText,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Column(
      children: [
        Text(
          totalText,
          style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
        AdminPaginationFooter(
          currentPage: _page,
          lastPage: _lastPage,
          totalItems: _filteredTotalCards,
          itemsPerPage: perPage,
          onPageChanged: (page) {
            setState(() => _page = page);
            _load();
          },
        ),
      ],
    );
  }

  String _statusFilterLabel(CardStatus status) {
    final l = context.loc;
    return switch (status) {
      CardStatus.unused => l.tr('screens_inventory_screen.005'),
      CardStatus.used => l.tr('screens_inventory_screen.006'),
      CardStatus.archived => l.tr('screens_inventory_screen.007'),
    };
  }

  IconData _statusFilterIcon(CardStatus status) {
    return switch (status) {
      CardStatus.unused => Icons.inventory_2_rounded,
      CardStatus.used => Icons.task_alt_rounded,
      CardStatus.archived => Icons.archive_rounded,
    };
  }

  Widget _buildOfflineFollowupCard() {
    final overview = _offlineOverview ?? const <String, dynamic>{};
    final summary = Map<String, dynamic>.from(
      overview['summary'] as Map? ?? const {},
    );
    final settings = Map<String, dynamic>.from(
      overview['settings'] as Map? ?? const {},
    );
    final history = List<Map<String, dynamic>>.from(
      overview['history'] as List? ?? const [],
    );
    final unknownLookups = List<Map<String, dynamic>>.from(
      overview['unknownLookups'] as List? ?? const [],
    );
    final lastSyncAt = settings['lastSyncAt']?.toString().trim() ?? '';
    final syncSource = settings['lastSyncSource']?.toString().trim() ?? '';
    final revealedCount = (settings['revealedCount'] as num?)?.toInt() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.cloud_sync_rounded,
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.loc.text(
                        'متابعة البطاقات الأوفلاين',
                        'Offline card tracking',
                      ),
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.loc.text(
                        'هذه اللوحة تظهر فقط للحسابات المصرح لها بمتابعة المسار الأوفلاين على هذا الجهاز.',
                        'This panel is only visible to accounts authorized to monitor the offline workflow on this device.',
                      ),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildOverviewChip(
                context.loc.text('المحفوظة', 'Saved'),
                '${(overview['cachedCount'] as num?)?.toInt() ?? 0}',
                AppTheme.primary,
              ),
              _buildOverviewChip(
                context.loc.text('بانتظار المزامنة', 'Awaiting sync'),
                '${(summary['count'] as num?)?.toInt() ?? 0}',
                AppTheme.warning,
              ),
              _buildOverviewChip(
                context.loc.text('بطاقات عُرضت', 'Cards revealed'),
                '$revealedCount',
                AppTheme.secondary,
              ),
              _buildOverviewChip(
                context.loc.text('بطاقات غير معروفة', 'Unknown cards'),
                '${unknownLookups.length}',
                AppTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChip(
                Icons.account_balance_wallet_rounded,
                '${context.loc.text('قيمة المعلّق', 'Pending value')} ${CurrencyFormatter.ils((summary['amount'] as num?)?.toDouble() ?? 0)}',
              ),
              _buildInfoChip(
                Icons.tune_rounded,
                '${context.loc.text('حد المعلّق', 'Pending limit')} ${(settings['maxPendingCount'] as num?)?.toInt() ?? 0} ${context.loc.text('بطاقة', 'card')}',
              ),
              _buildInfoChip(
                Icons.hourglass_bottom_rounded,
                '${context.loc.text('كل', 'Every')} ${(settings['syncIntervalMinutes'] as num?)?.toInt() ?? 0} ${context.loc.text('دقيقة', 'minutes')}',
              ),
              if (lastSyncAt.isNotEmpty)
                _buildInfoChip(
                  Icons.history_rounded,
                  '${context.loc.text('آخر مزامنة', 'Last sync')} ${_formatIsoString(lastSyncAt)}',
                ),
              if (syncSource.isNotEmpty)
                _buildInfoChip(
                  Icons.info_outline_rounded,
                  '${context.loc.text('المصدر', 'Source')}: $syncSource',
                ),
            ],
          ),
          if (history.isNotEmpty || unknownLookups.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            if (unknownLookups.isNotEmpty) ...[
              Text(
                context.loc.text(
                  'تنبيهات تحتاج متابعة',
                  'Alerts needing follow-up',
                ),
                style: AppTheme.bodyBold,
              ),
              const SizedBox(height: 8),
              ...unknownLookups
                  .take(3)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildOfflineFollowupRow(
                        icon: Icons.help_outline_rounded,
                        color: AppTheme.error,
                        title: item['barcode']?.toString() ?? '-',
                        subtitle:
                            item['message']?.toString() ??
                            context.loc.text(
                              'بانتظار التحقق عند توفر الإنترنت.',
                              'Awaiting verification when internet is available.',
                            ),
                      ),
                    ),
                  ),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.loc.text('آخر نشاط مزامنة', 'Last sync activity'),
                style: AppTheme.bodyBold,
              ),
              const SizedBox(height: 8),
              ...history
                  .take(3)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildOfflineFollowupRow(
                        icon: Icons.sync_rounded,
                        color: AppTheme.success,
                        title:
                            item['barcode']?.toString() ??
                            context.loc.text('دفعة مزامنة', 'Sync batch'),
                        subtitle:
                            item['message']?.toString() ??
                            item['status']?.toString() ??
                            context.loc.text(
                              'تمت مزامنة نشاط أوفلاين.',
                              'Offline activity synced.',
                            ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOfflineFollowupRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyBold.copyWith(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final l = context.loc;
    final statusChips = SingleChildScrollView(
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
                Navigator.of(context).maybePop();
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

    if (!_canUseAdminInventory) {
      return statusChips;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statusChips,
        const SizedBox(height: 16),
        ShwakelCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.tr('screens_inventory_screen.022'),
                style: AppTheme.bodyBold,
              ),
              const SizedBox(height: 8),
              Text(
                l.tr('screens_inventory_screen.023'),
                style: AppTheme.caption,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 780;
                  final fields = <Widget>[
                    _adminFilterField(
                      controller: _creatorController,
                      label: l.tr('screens_inventory_screen.024'),
                      hint: l.tr('screens_inventory_screen.025'),
                      icon: Icons.person_search_rounded,
                    ),
                    _adminFilterField(
                      controller: _valueMinController,
                      label: l.tr('screens_inventory_screen.026'),
                      hint: '0.00',
                      icon: Icons.south_rounded,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _adminFilterField(
                      controller: _valueMaxController,
                      label: l.tr('screens_inventory_screen.027'),
                      hint: '500.00',
                      icon: Icons.north_rounded,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _adminDateField(
                      label: l.tr('screens_inventory_screen.028'),
                      value: _issuedFrom,
                      onTap: () => _pickDate(true),
                    ),
                    _adminDateField(
                      label: l.tr('screens_inventory_screen.029'),
                      value: _issuedTo,
                      onTap: () => _pickDate(false),
                    ),
                  ];

                  if (isCompact) {
                    return Column(
                      children: [
                        ...fields.map(
                          (field) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: field,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: ShwakelButton(
                                label: l.tr('screens_inventory_screen.030'),
                                icon: Icons.filter_alt_rounded,
                                onPressed: _applyAdminFilters,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ShwakelButton(
                                label: l.tr('screens_inventory_screen.031'),
                                icon: Icons.refresh_rounded,
                                isSecondary: true,
                                onPressed: _clearAdminFilters,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  final itemWidth = constraints.maxWidth > 1120
                      ? (constraints.maxWidth - 24) / 3
                      : (constraints.maxWidth - 12) / 2;

                  return Column(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: fields
                            .map(
                              (field) =>
                                  SizedBox(width: itemWidth, child: field),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ShwakelButton(
                            label: l.tr('screens_inventory_screen.030'),
                            icon: Icons.filter_alt_rounded,
                            onPressed: _applyAdminFilters,
                          ),
                          const SizedBox(width: 10),
                          ShwakelButton(
                            label: l.tr('screens_inventory_screen.031'),
                            icon: Icons.refresh_rounded,
                            isSecondary: true,
                            onPressed: _clearAdminFilters,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTile(VirtualCard card) {
    final isUnused = card.status == CardStatus.unused;
    final isRevealed = _revealedBarcodes.contains(card.barcode);
    final isArchived = card.status == CardStatus.archived;
    final color = isUnused
        ? AppTheme.success
        : isArchived
        ? AppTheme.textTertiary
        : AppTheme.error;
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        card.isDelivery ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    final categoryLabel = card.isDelivery
        ? l.tr('shared.delivery_card_label')
        : card.isAppointment
        ? l.text('تذكرة موعد', 'Appointment ticket')
        : card.isQueueTicket
        ? l.text('تذكرة طابور', 'Queue ticket')
        : isLocationSpecific
        ? l.tr('screens_scan_card_screen.065')
        : (card.isPrivate
              ? l.tr('screens_scan_card_screen.066')
              : l.tr('screens_scan_card_screen.067'));

    return GestureDetector(
      onTap: isUnused ? () => _showCardPreview(card) : null,
      child: ShwakelCard(
        borderRadius: BorderRadius.circular(22),
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact)
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: _buildPopup(card),
                  ),
                Flex(
                  direction: isCompact ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isUnused
                            ? Icons.credit_card_rounded
                            : isArchived
                            ? Icons.archive_rounded
                            : Icons.check_circle_rounded,
                        color: color,
                        size: 28,
                      ),
                    ),
                    SizedBox(
                      width: isCompact ? 0 : 16,
                      height: isCompact ? 12 : 0,
                    ),
                    if (isCompact)
                      _buildCardTileBody(card, categoryLabel, l)
                    else
                      Expanded(
                        child: _buildCardTileBody(card, categoryLabel, l),
                      ),
                    if (!isCompact) _buildPopup(card),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      Icons.schedule_rounded,
                      '${card.createdAt.day}/${card.createdAt.month}/${card.createdAt.year}',
                    ),
                    if (isUnused)
                      _buildInfoChip(
                        Icons.touch_app_rounded,
                        isRevealed
                            ? l.text('تم عرض البطاقة', 'Card revealed')
                            : l.text('اضغط لعرض البطاقة', 'Tap to reveal card'),
                      ),
                    if (card.usedBy != null && card.usedBy!.trim().isNotEmpty)
                      _buildInfoChip(Icons.person_rounded, card.usedBy!),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _rawCardTypeLabel(dynamic l, String type) {
    switch (type.trim().toLowerCase()) {
      case 'delivery':
        return l.tr('shared.delivery_card_label');
      case 'appointment':
        return l.text('تذكرة موعد', 'Appointment ticket');
      case 'queue':
        return l.text('تذكرة طابور', 'Queue ticket');
      case 'single_use':
        return l.text('بطاقة دخول', 'Entry card');
      default:
        return l.tr('shared.balance_card_label');
    }
  }

  Widget _buildCardTileBody(VirtualCard card, String categoryLabel, dynamic l) {
    final isRevealed = _revealedBarcodes.contains(card.barcode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (card.isAppointment || card.isQueueTicket) && card.value <= 0
              ? (card.isQueueTicket
                    ? l.text('تذكرة طابور', 'Queue ticket')
                    : l.text('تذكرة موعد', 'Appointment ticket'))
              : CurrencyFormatter.ils(card.value),
          style: AppTheme.h3,
        ),
        Text(card.barcode, style: AppTheme.caption.copyWith(letterSpacing: 0)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        if (card.isTrial) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusMd,
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.20),
              ),
            ),
            child: Text(
              card.trialLabel?.trim().isNotEmpty == true
                  ? card.trialLabel!.trim()
                  : l.text('تجريبية', 'Trial'),
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.warning,
              ),
            ),
          ),
        ],
        if (card.isLoadedAsDeliveryForDriver) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: AppTheme.radiusMd,
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              l.tr(
                'shared.driver_delivery_proxy_note',
                params: {
                  'type': _rawCardTypeLabel(l, card.resolvedOriginalCardType),
                },
              ),
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
        if (isRevealed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusMd,
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              l.text('تم عرضها', 'Revealed'),
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.warning,
              ),
            ),
          ),
        ],
        if (card.isDelivery) ...[
          const SizedBox(height: 8),
          Text(
            l.tr('shared.delivery_card_payments_note'),
            style: AppTheme.caption.copyWith(
              color: AppTheme.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (card.title?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            card.title!.trim(),
            style: AppTheme.bodyBold.copyWith(fontSize: 13),
          ),
        ],
        if (card.ownerUsername?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            l.tr(
              'screens_inventory_screen.037',
              params: {'owner': card.ownerUsername ?? '-'},
            ),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (card.issuedByUsername?.trim().isNotEmpty == true)
              _buildInfoChip(
                Icons.person_add_alt_rounded,
                l.tr(
                  'screens_inventory_screen.038',
                  params: {'name': card.issuedByUsername ?? '-'},
                ),
              ),
            if (card.usedBy?.trim().isNotEmpty == true)
              _buildInfoChip(
                Icons.person_rounded,
                l.tr(
                  'screens_inventory_screen.039',
                  params: {'name': card.usedBy ?? '-'},
                ),
              ),
            _buildInfoChip(
              Icons.event_available_rounded,
              l.tr(
                'screens_inventory_screen.040',
                params: {'date': _formatDateTime(card.createdAt)},
              ),
            ),
            if (card.usedAt != null)
              _buildInfoChip(
                Icons.event_busy_rounded,
                l.tr(
                  'screens_inventory_screen.041',
                  params: {'date': _formatDateTime(card.usedAt)},
                ),
              ),
            if (card.validUntil != null)
              _buildInfoChip(
                Icons.timer_off_rounded,
                '${l.text('تنتهي', 'Expires')} ${_formatDateTime(card.validUntil)}',
              ),
            if (card.isAppointment && card.appointmentStartsAt != null)
              _buildInfoChip(
                Icons.schedule_rounded,
                '${l.text('الموعد', 'Appointment')} ${_formatDateTime(card.appointmentStartsAt)}',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }

  String _formatIsoString(String value) {
    final parsed = DateTime.tryParse(value);
    return _formatDateTime(parsed);
  }

  void _setBusyState(bool value, {String message = ''}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isActionInProgress = value;
      _actionStatusMessage = value ? message : '';
    });
  }

  List<VirtualCard> _printableCards(Iterable<VirtualCard> cards) {
    return cards.where((card) => card.status == CardStatus.unused).toList();
  }

  Widget _buildPopup(VirtualCard card) {
    final l = context.loc;
    final menuItems = <PopupMenuEntry<String>>[
      if (_canPrintCards && card.status == CardStatus.unused)
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
      if (!_canUseAdminInventory &&
          _canDeleteCards &&
          card.status == CardStatus.unused)
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_rounded, size: 18, color: AppTheme.error),
              const SizedBox(width: 8),
              Text(
                l.tr('screens_inventory_screen.009'),
                style: const TextStyle(color: AppTheme.error),
              ),
            ],
          ),
        ),
      if (_canUseAdminInventory)
        PopupMenuItem(
          value: 'transfer',
          child: Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 18),
              const SizedBox(width: 8),
              Text(l.text('نقل لمستخدم آخر', 'Transfer to another user')),
            ],
          ),
        ),
      if (_canUseAdminInventory && card.status == CardStatus.unused)
        PopupMenuItem(
          value: 'admin_delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_forever_rounded,
                size: 18,
                color: AppTheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                l.text('حذف إداري', 'Admin delete'),
                style: const TextStyle(color: AppTheme.error),
              ),
            ],
          ),
        ),
    ];
    if (menuItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        if (value == 'print') {
          _reprint(card);
        } else if (value == 'transfer') {
          _transferAdminCard(card);
        } else if (value == 'admin_delete') {
          _deleteAdminCard(card.id);
        } else {
          _delete(card.id);
        }
      },
      itemBuilder: (context) => menuItems,
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
    if (card.status != CardStatus.unused) {
      await AppAlertService.showInfo(
        context,
        title: context.loc.text('الطباعة غير متاحة', 'Printing not available'),
        message: context.loc.text(
          'لا يمكن طباعة بطاقة مستخدمة أو مؤرشفة.',
          'Cannot print a used or archived card.',
        ),
      );
      return;
    }
    if (!await _confirmCardOutputSecurity()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final fallbackPrintedBy = context.loc.tr('screens_inventory_screen.010');
    final successMessage = context.loc.tr('screens_inventory_screen.016');
    final user = await _authService.currentUser();
    _setBusyState(
      true,
      message: context.loc.text(
        'جارٍ تجهيز البطاقة للطباعة...',
        'Preparing card for printing...',
      ),
    );
    try {
      final printedBy = UserDisplayName.fromMap(
        user,
        fallback: fallbackPrintedBy,
      );
      await _pdfService.printCards([card], printedBy: printedBy);
      if (mounted) {
        AppAlertService.showSuccess(context, message: successMessage);
      }
    } catch (error, stackTrace) {
      await AppAlertService.reportUnhandledCrash(
        title: 'Card reprint failed',
        message: ErrorMessageService.sanitize(error),
        details:
            'action: reprint_card\nbarcode: ${card.barcode}\ncardId: ${card.id}\nerrorType: ${error.runtimeType}\nerror: $error',
        stackTrace: stackTrace.toString(),
        route: '/inventory',
        extraContext: {
          'errorKind': 'card_reprint_failed',
          'barcode': card.barcode,
          'cardId': card.id,
        },
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: context.loc.text(
          'تعذر إعادة طباعة البطاقة',
          'Could not reprint card',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      _setBusyState(false);
    }
  }

  Future<void> _showCardPreview(VirtualCard card) async {
    if (card.status != CardStatus.unused || !mounted) {
      return;
    }
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    final userId = user?['id']?.toString() ?? '';
    final isOnline = await ConnectivityService.instance.checkNow();
    var previewCard = card;

    if (isOnline) {
      _setBusyState(
        true,
        message: context.loc.text(
          'جارٍ تحديث بيانات البطاقة...',
          'Updating card data...',
        ),
      );
      try {
        final freshCard = await _apiService.getCardByBarcode(card.barcode);
        if (!mounted) {
          return;
        }
        if (freshCard == null || freshCard.status != CardStatus.unused) {
          await _load();
          if (!context.mounted) {
            return;
          }
          await AppAlertService.showInfo(
            context,
            title: context.loc.text(
              'تم تحديث حالة البطاقة',
              'Card status updated',
            ),
            message: context.loc.text(
              'هذه البطاقة لم تعد متاحة للعرض الآن.',
              'This card is no longer available for display.',
            ),
          );
          return;
        }
        previewCard = freshCard;
      } catch (error) {
        if (!mounted) {
          return;
        }
        await AppAlertService.showError(
          context,
          title: context.loc.text(
            'تعذر تحديث البطاقة',
            'Could not update card',
          ),
          message: ErrorMessageService.sanitize(error),
        );
        return;
      } finally {
        _setBusyState(false);
      }
    }

    if (userId.isNotEmpty) {
      final alreadyRevealed = await _offlineCardService.isCardRevealed(
        userId,
        previewCard.barcode,
      );
      if (!mounted) {
        return;
      }
      if (alreadyRevealed) {
        await AppAlertService.showInfo(
          context,
          title: 'تم عرض البطاقة مسبقًا',
          message: isOnline
              ? 'هذه البطاقة عُرضت مؤخرًا. إذا لم تُستخدم فستتمكن من عرضها مجددًا بعد خمس دقائق.'
              : 'هذه البطاقة عُرضت سابقًا في وضع الأوفلاين. عند عودة الإنترنت سنحدّث حالتها، وإذا بقيت غير مستخدمة فستتاح مجددًا بعد خمس دقائق.',
        );
        return;
      }
      await _offlineCardService.markCardRevealed(
        userId,
        previewCard.barcode,
        allowRetryAfterReconnect: isOnline,
      );
      if (mounted) {
        setState(() {
          _revealedBarcodes = {..._revealedBarcodes, previewCard.barcode};
        });
      }
      if (!mounted) {
        return;
      }
    }
    final issuerName = UserDisplayName.fromMap(user, fallback: 'Shwakel');
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThermalCardTicket(
                  card: previewCard,
                  issuerName: issuerName,
                  title: issuerName,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ShwakelButton(
                    label: 'إغلاق',
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    isSecondary: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(String id) async {
    if (_isActionInProgress) {
      return;
    }
    final l = context.loc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_inventory_screen.011')),
        content: Text(l.tr('screens_inventory_screen.017')),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l.tr('screens_inventory_screen.012')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShwakelButton(
                    label: l.tr('screens_inventory_screen.013'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    isSecondary: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      _setBusyState(true, message: 'جارٍ حذف البطاقة وتحديث الرصيد...');
      await _apiService.deleteCard(
        id,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
      );
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
    } finally {
      _setBusyState(false);
    }
  }

  Future<void> _deleteAdminCard(String id) async {
    if (_isActionInProgress) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف البطاقة'),
        content: const Text('سيتم حذف البطاقة وإرجاع قيمتها إلى رصيد صاحبها.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      _setBusyState(true, message: 'جارٍ حذف البطاقة إداريًا...');
      await _apiService.deleteAdminCard(
        id,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
      );
      await _load();
      if (mounted) {
        AppAlertService.showSuccess(context, message: 'تم حذف البطاقة.');
      }
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      _setBusyState(false);
    }
  }

  Future<Map<String, dynamic>?> _selectUserDialog(String title) async {
    final searchController = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var isSearching = false;
    try {
      return showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> search() async {
              final query = searchController.text.trim();
              if (query.isEmpty) {
                return;
              }
              setDialogState(() => isSearching = true);
              try {
                final found = await _apiService.searchUsers(query);
                if (dialogContext.mounted) {
                  setDialogState(() => results = found);
                }
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => isSearching = false);
                }
              }
            }

            return AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        labelText: 'بحث عن المستخدم',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          onPressed: isSearching ? null : search,
                          icon: isSearching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final user = results[index];
                          final username = user['username']?.toString() ?? '';
                          final name = UserDisplayName.fromMap(
                            user,
                            fallback: username,
                          );
                          return ListTile(
                            leading: const Icon(Icons.person_rounded),
                            title: Text(name),
                            subtitle: Text(username),
                            onTap: () => Navigator.pop(dialogContext, user),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _transferAdminCard(VirtualCard card) async {
    if (_isActionInProgress) {
      return;
    }
    final target = await _selectUserDialog('نقل البطاقة إلى مستخدم');
    if (target == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final targetName = UserDisplayName.fromMap(target);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد نقل البطاقة'),
        content: Text(
          'سيتم نقل ملكية البطاقة إلى $targetName. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      _setBusyState(true, message: 'جارٍ نقل البطاقة إلى المستخدم المحدد...');
      await _apiService.transferAdminCard(
        cardId: card.id,
        targetUserId: target['id']?.toString() ?? '',
        otpCode: security.otpCode,
        securityPin: security.securityPin,
      );
      await _load();
      if (mounted) {
        AppAlertService.showSuccess(context, message: 'تم نقل البطاقة.');
      }
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      _setBusyState(false);
    }
  }

  Future<void> _createAdminCard() async {
    final target = await _selectUserDialog('إنشاء بطاقة لمستخدم');
    if (target == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final valueController = TextEditingController(text: '1');
    final quantityController = TextEditingController(text: '1');
    var cardType = 'standard';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('إنشاء بطاقة لمستخدم'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: cardType,
                  decoration: const InputDecoration(labelText: 'نوع البطاقة'),
                  items: const [
                    DropdownMenuItem(value: 'standard', child: Text('رصيد')),
                    DropdownMenuItem(value: 'delivery', child: Text('توصيل')),
                    DropdownMenuItem(value: 'single_use', child: Text('دخول')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => cardType = value ?? 'standard');
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'القيمة'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'العدد'),
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
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) {
        return;
      }

      _setBusyState(true, message: 'جارٍ إنشاء البطاقة للمستخدم...');
      await _apiService.createAdminCardForUser(
        userId: target['id']?.toString() ?? '',
        value: double.tryParse(valueController.text.trim()) ?? 0,
        quantity: int.tryParse(quantityController.text.trim()) ?? 1,
        cardType: cardType,
      );
      await _load();
      if (mounted) {
        AppAlertService.showSuccess(context, message: 'تم إنشاء البطاقة.');
      }
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      _setBusyState(false);
      valueController.dispose();
      quantityController.dispose();
    }
  }

  Future<void> _reprintFilteredCards() async {
    final initialPrintableCards = _printableCards(_cards);
    if (initialPrintableCards.isEmpty) {
      if (mounted) {
        await AppAlertService.showInfo(
          context,
          title: 'لا توجد بطاقات صالحة للطباعة',
          message: 'اطبع البطاقات غير المستخدمة فقط.',
        );
      }
      return;
    }
    if (!_canPrintCards) {
      return;
    }
    if (!await _confirmCardOutputSecurity()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final fallbackPrintedBy = context.loc.tr('screens_inventory_screen.010');
    final successMessage = context.loc.tr('screens_inventory_screen.032');
    var cardsToPrint = initialPrintableCards;
    if (_canUseAdminInventory && _totalCards > _cards.length) {
      final statusMap = {
        CardStatus.used: 'used',
        CardStatus.archived: 'archived',
        CardStatus.unused: 'unused',
      };
      final payload = await _apiService.getAdminCards(
        status: statusMap[_filter] ?? 'unused',
        creator: _creatorController.text,
        valueMin: _parseDouble(_valueMinController.text),
        valueMax: _parseDouble(_valueMaxController.text),
        issuedFrom: _formatDate(_issuedFrom),
        issuedTo: _formatDate(_issuedTo),
        page: 1,
        perPage: _totalCards > 250 ? 250 : _totalCards,
      );
      cardsToPrint = List<VirtualCard>.from(
        payload['cards'] as List? ?? cardsToPrint,
      );
    }
    cardsToPrint = _printableCards(cardsToPrint);
    if (cardsToPrint.isEmpty) {
      if (mounted) {
        await AppAlertService.showInfo(
          context,
          title: 'لا توجد بطاقات صالحة للطباعة',
          message: 'لا توجد بطاقات غير مستخدمة.',
        );
      }
      return;
    }
    final user = await _authService.currentUser();
    _setBusyState(true, message: 'جارٍ تجهيز البطاقات للطباعة...');
    try {
      await _pdfService.printCards(
        cardsToPrint,
        printedBy: UserDisplayName.fromMap(user, fallback: fallbackPrintedBy),
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(context, message: successMessage);
    } catch (error, stackTrace) {
      await AppAlertService.reportUnhandledCrash(
        title: 'Filtered card reprint failed',
        message: ErrorMessageService.sanitize(error),
        details:
            'action: reprint_filtered_cards\ncount: ${cardsToPrint.length}\nerrorType: ${error.runtimeType}\nerror: $error',
        stackTrace: stackTrace.toString(),
        route: '/inventory',
        extraContext: {
          'errorKind': 'filtered_card_reprint_failed',
          'cardCount': cardsToPrint.length,
        },
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر إعادة طباعة البطاقات',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      _setBusyState(false);
    }
  }

  Widget _adminFilterField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onSubmitted: (_) => _applyAdminFilters(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _adminDateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_rounded),
        ),
        child: Text(
          value == null
              ? context.loc.tr('screens_inventory_screen.033')
              : _formatDate(value),
          style: value == null
              ? AppTheme.bodyAction.copyWith(color: AppTheme.textTertiary)
              : AppTheme.bodyAction,
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final initialDate = isFrom
        ? (_issuedFrom ?? DateTime.now())
        : (_issuedTo ?? _issuedFrom ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isFrom) {
        _issuedFrom = picked;
        if (_issuedTo != null && _issuedTo!.isBefore(picked)) {
          _issuedTo = picked;
        }
      } else {
        _issuedTo = picked;
      }
    });
    _inventoryToolsSetState?.call(() {});
  }

  void _applyAdminFilters() {
    setState(() => _page = 1);
    Navigator.of(context).maybePop();
    _load();
  }

  void _clearAdminFilters() {
    _creatorController.clear();
    _valueMinController.clear();
    _valueMaxController.clear();
    setState(() {
      _issuedFrom = null;
      _issuedTo = null;
      _page = 1;
    });
    Navigator.of(context).maybePop();
    _load();
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  double? _parseDouble(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }
}

class _InventoryListItem {
  const _InventoryListItem(this.kind, {this.cardIndex = -1});

  final _InventoryListItemKind kind;
  final int cardIndex;
}

enum _InventoryListItemKind {
  overview,
  filters,
  resultsHeader,
  offlineBanner,
  offlineFollowup,
  adminActions,
  userPrintAction,
  empty,
  card,
  pagination,
}
