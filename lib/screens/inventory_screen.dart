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
  bool _isAuthorized = false;
  bool _canRequestCardPrinting = false;
  bool _canUseAdminInventory = false;
  bool _canMonitorOfflineWorkflow = false;
  int _page = 1;
  static const int _perPage = 12;
  static const int _adminPerPage = 24;
  int _lastPage = 1;
  int _totalCards = 0;
  DateTime? _issuedFrom;
  DateTime? _issuedTo;
  bool _isOfflineData = false;
  Set<String> _revealedBarcodes = const <String>{};
  Map<String, dynamic>? _offlineOverview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _creatorController.dispose();
    _valueMinController.dispose();
    _valueMaxController.dispose();
    super.dispose();
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
        revealedBarcodes = <String>{};
        if (!canUseAdminInventory && userId.isNotEmpty) {
          await _offlineCardService.cacheCards(userId: userId, cards: cards);
          await _offlineCardService.clearRevealedCards(userId);
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
        _canUseAdminInventory = canUseAdminInventory;
        _canMonitorOfflineWorkflow = canMonitorOfflineWorkflow;
        _cards = cards;
        _page = normalizedPage;
        _lastPage = lastPage;
        _totalCards = (pagination['total'] as num?)?.toInt() ?? _cards.length;
        _isOfflineData = isOfflineData;
        _revealedBarcodes = revealedBarcodes;
        _offlineOverview = offlineOverview;
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
            tooltip: l.tr('screens_inventory_screen.020'),
            onPressed: _showSummarySheet,
            icon: const Icon(Icons.dashboard_customize_rounded),
          ),
          if (_canRequestCardPrinting)
            IconButton(
              tooltip: l.tr('screens_inventory_screen.003'),
              onPressed: () =>
                  Navigator.pushNamed(context, '/card-print-requests'),
              icon: const Icon(Icons.print_rounded),
            ),
          IconButton(
            tooltip: l.tr('screens_inventory_screen.017'),
            onPressed: _showFiltersSheet,
            icon: const Icon(Icons.filter_alt_rounded),
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
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_isOfflineData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ShwakelCard(
                    padding: const EdgeInsets.all(16),
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderColor: AppTheme.warning.withValues(alpha: 0.15),
                    child: Text(
                      'أنت تعرض بطاقات محفوظة محليًا. يمكن فتح البطاقة غير المستخدمة واستخدامها حتى بدون إنترنت.',
                      style: AppTheme.bodyAction.copyWith(fontSize: 14),
                    ),
                  ),
                ),
              if (_canMonitorOfflineWorkflow &&
                  _offlineOverview != null &&
                  !_canUseAdminInventory)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildOfflineFollowupCard(),
                ),
              if (_canUseAdminInventory && _cards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ShwakelButton(
                      label: l.tr('screens_inventory_screen.021'),
                      icon: Icons.print_rounded,
                      onPressed: _reprintFilteredCards,
                    ),
                  ),
                ),
              if (_cards.isEmpty)
                _buildEmptyState()
              else ...[
                ..._cards.map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildCardTile(card),
                  ),
                ),
                AdminPaginationFooter(
                  currentPage: _page,
                  lastPage: _lastPage,
                  totalItems: _totalCards,
                  itemsPerPage: _canUseAdminInventory
                      ? _adminPerPage
                      : _perPage,
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
    );
  }

  Future<void> _showHelpDialog() {
    final l = context.loc;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_inventory_screen.001')),
        content: Text(l.tr('screens_inventory_screen.019')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.tr('screens_admin_customers_screen.046')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmCardOutputSecurity() async {
    final security = await TransferSecurityService.confirmTransfer(context);
    return mounted && security.isVerified;
  }

  Widget _buildOverviewCard() {
    final l = context.loc;
    final unusedCount = _cards
        .where((card) => card.status == CardStatus.unused)
        .length;
    final usedCount = _cards
        .where((card) => card.status == CardStatus.used)
        .length;
    final archivedCount = _cards
        .where((card) => card.status == CardStatus.archived)
        .length;
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
              const SizedBox(height: 10),
              Text(
                l.tr('screens_inventory_screen.014'),
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
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
                    Text('متابعة البطاقات الأوفلاين', style: AppTheme.bodyBold),
                    const SizedBox(height: 4),
                    Text(
                      'هذه اللوحة تظهر فقط للحسابات المصرح لها بمتابعة المسار الأوفلاين على هذا الجهاز.',
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
                'المحفوظة',
                '${(overview['cachedCount'] as num?)?.toInt() ?? 0}',
                AppTheme.primary,
              ),
              _buildOverviewChip(
                'بانتظار المزامنة',
                '${(summary['count'] as num?)?.toInt() ?? 0}',
                AppTheme.warning,
              ),
              _buildOverviewChip(
                'بطاقات عُرضت',
                '$revealedCount',
                AppTheme.secondary,
              ),
              _buildOverviewChip(
                'بطاقات غير معروفة',
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
                'قيمة المعلّق ${CurrencyFormatter.ils((summary['amount'] as num?)?.toDouble() ?? 0)}',
              ),
              _buildInfoChip(
                Icons.tune_rounded,
                'حد المعلّق ${(settings['maxPendingCount'] as num?)?.toInt() ?? 0} بطاقة',
              ),
              _buildInfoChip(
                Icons.hourglass_bottom_rounded,
                'كل ${(settings['syncIntervalMinutes'] as num?)?.toInt() ?? 0} دقيقة',
              ),
              if (lastSyncAt.isNotEmpty)
                _buildInfoChip(
                  Icons.history_rounded,
                  'آخر مزامنة ${_formatIsoString(lastSyncAt)}',
                ),
              if (syncSource.isNotEmpty)
                _buildInfoChip(
                  Icons.info_outline_rounded,
                  'المصدر: $syncSource',
                ),
            ],
          ),
          if (history.isNotEmpty || unknownLookups.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            if (unknownLookups.isNotEmpty) ...[
              Text('تنبيهات تحتاج متابعة', style: AppTheme.bodyBold),
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
                            'بانتظار التحقق عند توفر الإنترنت.',
                      ),
                    ),
                  ),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('آخر نشاط مزامنة', style: AppTheme.bodyBold),
              const SizedBox(height: 8),
              ...history
                  .take(3)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildOfflineFollowupRow(
                        icon: Icons.sync_rounded,
                        color: AppTheme.success,
                        title: item['barcode']?.toString() ?? 'دفعة مزامنة',
                        subtitle:
                            item['message']?.toString() ??
                            item['status']?.toString() ??
                            'تمت مزامنة نشاط أوفلاين.',
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
    final color = isUnused ? AppTheme.success : AppTheme.error;
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
        ? 'تذكرة موعد'
        : card.isQueueTicket
        ? 'تذكرة طابور'
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
                        isRevealed ? 'تم عرض البطاقة' : 'اضغط لعرض البطاقة',
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
        return 'تذكرة موعد';
      case 'queue':
        return 'تذكرة طابور';
      case 'single_use':
        return 'بطاقة دخول';
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
              ? (card.isQueueTicket ? 'تذكرة طابور' : 'تذكرة موعد')
              : CurrencyFormatter.ils(card.value),
          style: AppTheme.h3,
        ),
        Text(
          card.barcode,
          style: AppTheme.caption.copyWith(letterSpacing: 1.5),
        ),
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
                  : 'تجريبية',
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
              'تم عرضها',
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
                'تنتهي ${_formatDateTime(card.validUntil)}',
              ),
            if (card.isAppointment && card.appointmentStartsAt != null)
              _buildInfoChip(
                Icons.schedule_rounded,
                'الموعد ${_formatDateTime(card.appointmentStartsAt)}',
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

  Future<void> _showSummarySheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              context.loc.tr('screens_inventory_screen.020'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              context.loc.tr('screens_inventory_screen.014'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildOverviewCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _showFiltersSheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              context.loc.tr('screens_inventory_screen.017'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              context.loc.tr('screens_inventory_screen.018'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildFilters(),
          ],
        ),
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
    if (!await _confirmCardOutputSecurity()) {
      return;
    }
    final user = await _authService.currentUser();
    final printedBy = UserDisplayName.fromMap(
      user,
      fallback: l.tr('screens_inventory_screen.010'),
    );
    await _pdfService.printCards([card], printedBy: printedBy);
    if (mounted) {
      AppAlertService.showSuccess(
        context,
        message: l.tr('screens_inventory_screen.016'),
      );
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
    if (userId.isNotEmpty) {
      final alreadyRevealed = await _offlineCardService.isCardRevealed(
        userId,
        card.barcode,
      );
      if (!mounted) {
        return;
      }
      if (alreadyRevealed) {
        await AppAlertService.showInfo(
          context,
          title: 'تم عرض البطاقة مسبقًا',
          message:
              'هذه البطاقة تم فتحها مرة واحدة بالفعل. أعد الاتصال بالإنترنت أولًا حتى يمكن فتحها مرة أخرى.',
        );
        return;
      }
      await _offlineCardService.markCardRevealed(userId, card.barcode);
      if (mounted) {
        setState(() {
          _revealedBarcodes = {..._revealedBarcodes, card.barcode};
        });
      }
      if (!mounted) {
        return;
      }
    }
    final issuerName = UserDisplayName.fromMap(user, fallback: 'Shwakel');
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
                  card: card,
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

  Future<void> _reprintFilteredCards() async {
    if (_cards.isEmpty) {
      return;
    }
    if (!await _confirmCardOutputSecurity()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final fallbackPrintedBy = context.loc.tr('screens_inventory_screen.010');
    var cardsToPrint = _cards;
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
    final user = await _authService.currentUser();
    await _pdfService.printCards(
      cardsToPrint,
      printedBy: UserDisplayName.fromMap(user, fallback: fallbackPrintedBy),
    );
    if (!mounted) {
      return;
    }
    AppAlertService.showSuccess(
      context,
      message: context.loc.tr('screens_inventory_screen.032'),
    );
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
  }

  void _applyAdminFilters() {
    setState(() => _page = 1);
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
