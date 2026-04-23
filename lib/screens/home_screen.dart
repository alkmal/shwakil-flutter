import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final DebtBookService _debtBookService = DebtBookService();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _hasOfflineWorkspace = false;
  bool _isSyncingOfflineWorkspace = false;
  bool _didSuggestOfflineWorkspace = false;
  bool _lastKnownDeviceOnline = ConnectivityService.instance.isOnline.value;
  int _pendingOfflineCount = 0;
  String? _lastOfflineSyncAt;
  StreamSubscription<Map<String, dynamic>>? _balanceSubscription;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnline.addListener(
      _handleConnectivityChanged,
    );
    _loadUser();
    _balanceSubscription = RealtimeNotificationService.balanceUpdatesStream
        .listen((_) {
          if (mounted) _loadUser();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    ConnectivityService.instance.isOnline.removeListener(
      _handleConnectivityChanged,
    );
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPopNext() => _loadUser();

  bool get _canTransfer {
    return AppPermissions.fromUser(_user).canTransfer;
  }

  bool get _canOfflineScan {
    return AppPermissions.fromUser(_user).canOfflineCardScan;
  }

  bool get _canOpenCardTools {
    return AppPermissions.fromUser(_user).canOpenCardTools;
  }

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  String get _displayName {
    final username = _user?['username']?.toString().trim() ?? '';
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    return fullName.isNotEmpty ? fullName : username;
  }

  String get _roleLabel {
    return _user?['roleLabel']?.toString().trim() ??
        _user?['role']?.toString().trim() ??
        '';
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      await _authService.refreshCurrentUser();
      final user = await _authService.currentUser();
      final hasOfflineWorkspace = await _resolveOfflineWorkspace(user);
      final pendingSummary = await _resolveOfflinePendingSummary(user);
      final lastSyncAt = await _resolveLastOfflineSyncAt(user);
      if (!mounted) return;
      setState(() {
        _user = user;
        _hasOfflineWorkspace = hasOfflineWorkspace;
        _pendingOfflineCount = (pendingSummary['count'] as num?)?.toInt() ?? 0;
        _lastOfflineSyncAt = lastSyncAt;
        _isLoading = false;
      });
      _maybeSuggestOfflineWorkspace();
    } catch (_) {
      final user = await _authService.currentUser();
      final hasOfflineWorkspace = await _resolveOfflineWorkspace(user);
      final pendingSummary = await _resolveOfflinePendingSummary(user);
      final lastSyncAt = await _resolveLastOfflineSyncAt(user);
      if (!mounted) return;
      setState(() {
        _user = user;
        _hasOfflineWorkspace = hasOfflineWorkspace;
        _pendingOfflineCount = (pendingSummary['count'] as num?)?.toInt() ?? 0;
        _lastOfflineSyncAt = lastSyncAt;
        _isLoading = false;
      });
      _maybeSuggestOfflineWorkspace();
    }
  }

  Future<Map<String, dynamic>> _resolveOfflinePendingSummary(
    Map<String, dynamic>? user,
  ) async {
    final permissions = AppPermissions.fromUser(user);
    if (user == null || user['id'] == null || !permissions.canOfflineCardScan) {
      return const {'count': 0, 'amount': 0.0};
    }
    return _offlineCardService.pendingRedeemSummary(user['id'].toString());
  }

  Future<String?> _resolveLastOfflineSyncAt(Map<String, dynamic>? user) async {
    final permissions = AppPermissions.fromUser(user);
    if (user == null || user['id'] == null || !permissions.canOfflineCardScan) {
      return null;
    }
    final settings = await _offlineCardService.offlineSettings(
      user['id'].toString(),
    );
    return settings['lastSyncAt']?.toString();
  }

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    final isOnline = ConnectivityService.instance.isOnline.value;
    final regainedConnection = !_lastKnownDeviceOnline && isOnline;
    _lastKnownDeviceOnline = isOnline;
    if (regainedConnection) {
      OfflineSessionService.setOfflineMode(false);
      unawaited(_syncOfflineWorkspace(triggeredAutomatically: true));
    }
    setState(() {});
  }

  Future<void> _syncOfflineWorkspace({
    bool triggeredAutomatically = false,
  }) async {
    if (_isSyncingOfflineWorkspace ||
        !ConnectivityService.instance.isOnline.value) {
      return;
    }

    final user = _user ?? await _authService.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      return;
    }

    final userId = user['id'].toString();
    final queuedBeforeSync = await _offlineCardService.getRedeemQueue(userId);
    final unknownLookups = await _offlineCardService.getUnknownCardLookups(
      userId,
    );
    if (mounted) {
      setState(() => _isSyncingOfflineWorkspace = true);
    }

    try {
      final payload = await _apiService.getOfflineCardCache();
      await _offlineCardService.cacheCards(
        userId: userId,
        cards: List<VirtualCard>.from(payload['cards'] as List? ?? const []),
        settings: Map<String, dynamic>.from(
          payload['settings'] as Map? ?? const {},
        ),
      );

      if (unknownLookups.isNotEmpty) {
        await _resolveUnknownOfflineLookups(userId, unknownLookups);
      }

      if (permissions.canManageDebtBook) {
        await _debtBookService.syncPending(userId: userId, api: _apiService);
      }

      if (queuedBeforeSync.isNotEmpty) {
        final result = await _apiService.syncOfflineCardRedeems(
          items: queuedBeforeSync,
        );
        final resultItems = List<Map<String, dynamic>>.from(
          (result['results'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        final rejectedBarcodes = <String>{
          for (final item in resultItems)
            if (item['ok'] != true) (item['barcode'] ?? '').toString(),
        }..remove('');
        final acceptedBarcodes = <String>{
          for (final item in resultItems)
            if (item['ok'] == true) (item['barcode'] ?? '').toString(),
        }..remove('');
        final syncedAt = DateTime.now().toIso8601String();
        final historyEntries = queuedBeforeSync.map((entry) {
          final barcode = entry['barcode']?.toString() ?? '';
          Map<String, dynamic>? matchedResult;
          for (final item in resultItems) {
            if (item['barcode']?.toString() == barcode) {
              matchedResult = item;
              break;
            }
          }
          final ok = matchedResult?['ok'] == true;
          return {
            ...entry,
            'status': ok ? 'confirmed' : 'rejected',
            'message': matchedResult?['message']?.toString(),
            'syncedAt': syncedAt,
            'confirmedOffline': true,
          };
        }).toList();
        final rejectedHistoryEntries = historyEntries
            .where((item) => item['status'] == 'rejected')
            .toList();

        await _offlineCardService.replaceRedeemQueue(
          userId,
          queuedBeforeSync
              .where(
                (item) =>
                    rejectedBarcodes.contains(item['barcode']?.toString()),
              )
              .toList(),
        );
        await _offlineCardService.replaceRejectedRedeems(
          userId,
          rejectedHistoryEntries,
        );
        await _offlineCardService.appendSyncHistory(
          userId,
          rejectedHistoryEntries,
        );
        await _offlineCardService.removeCardsByBarcode(
          userId: userId,
          barcodes: acceptedBarcodes,
        );

        final updatedBalance = (result['balance'] as num?)?.toDouble();
        if (updatedBalance != null) {
          await _authService.patchCurrentUser({'balance': updatedBalance});
        }
      }

      try {
        await _authService.refreshCurrentUser();
      } catch (_) {
        // Keep the cached user if refreshing the profile is temporarily unavailable.
      }

      await _offlineCardService.recordLastSync(
        userId,
        source: queuedBeforeSync.isNotEmpty ? 'queue' : 'inventory',
      );

      await _loadUser();
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted || triggeredAutomatically) {
        return;
      }
      AppAlertService.showError(
        context,
        title: _t('screens_home_screen.054'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingOfflineWorkspace = false);
      }
    }
  }

  Future<void> _resolveUnknownOfflineLookups(
    String userId,
    List<Map<String, dynamic>> lookups,
  ) async {
    final foundCards = <VirtualCard>[];
    final unresolved = <Map<String, dynamic>>[];
    final l = context.loc;

    for (final item in lookups) {
      final barcode = item['barcode']?.toString().trim() ?? '';
      if (barcode.isEmpty) {
        continue;
      }
      try {
        final card = await _apiService.getCardByBarcode(barcode);
        if (card == null) {
          unresolved.add({
            ...item,
            'status': 'pending_lookup',
            'message': l.tr('screens_home_screen.055'),
            'lastCheckedAt': DateTime.now().toIso8601String(),
          });
          continue;
        }
        foundCards.add(card);
      } catch (_) {
        unresolved.add({
          ...item,
          'status': 'pending_lookup',
          'message': l.tr('screens_home_screen.056'),
          'lastCheckedAt': DateTime.now().toIso8601String(),
        });
      }
    }

    if (foundCards.isNotEmpty) {
      await _offlineCardService.cacheCards(userId: userId, cards: foundCards);
    }
    await _offlineCardService.replaceUnknownCardLookups(userId, unresolved);
  }

  void _maybeSuggestOfflineWorkspace() {
    if (!mounted ||
        _didSuggestOfflineWorkspace ||
        OfflineSessionService.isOfflineMode ||
        !_hasOfflineWorkspace ||
        _isDeviceOnline) {
      return;
    }
    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canOfflineCardScan) {
      return;
    }
    _didSuggestOfflineWorkspace = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final openOffline = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('screens_home_screen.057')),
          content: Text(_t('screens_home_screen.058')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t('screens_home_screen.059')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t('screens_home_screen.060')),
            ),
          ],
        ),
      );
      if (openOffline == true && mounted) {
        Navigator.pushNamed(context, '/scan-card-offline');
      }
    });
  }

  Future<bool> _resolveOfflineWorkspace(Map<String, dynamic>? user) async {
    final permissions = AppPermissions.fromUser(user);
    if (user == null || user['id'] == null || !permissions.canOfflineCardScan) {
      return false;
    }
    return _offlineCardService.hasOfflineWorkspace(user['id'].toString());
  }

  bool get _isDeviceOnline => ConnectivityService.instance.isOnline.value;

  String get _scanCameraRoute => OfflineSessionService.isOfflineMode
      ? '/scan-card-offline-camera'
      : '/scan-card-camera';

  void _openScanScreen() {
    Navigator.pushNamed(context, _scanCameraRoute);
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: _t('screens_home_screen.061'),
      message: _t('screens_home_screen.062'),
    );
  }

  Future<void> _openOnlineOnlyRoute(String routeName) async {
    if (OfflineSessionService.isOfflineMode) {
      await _showOfflineBlockedMessage();
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.pushNamed(context, routeName);
  }

  @override
  Widget build(BuildContext context) {
    final services = _serviceItems(context);
    _HomeServiceItem? scanShortcut;
    for (final item in services) {
      if (item.kind == _HomeServiceKind.scan) {
        scanShortcut = item;
        break;
      }
    }
    final listServices = services
        .where((item) => item.kind != _HomeServiceKind.scan)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          if (_canOfflineScan && !OfflineSessionService.isOfflineMode)
            _buildSyncStatusAction(),
          if (!OfflineSessionService.isOfflineMode)
            const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: OfflineSessionService.isOfflineMode ? null : const AppSidebar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ResponsiveScaffoldContainer(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeCard(),
                        if (scanShortcut != null) ...[
                          const SizedBox(height: 14),
                          _buildScanShortcut(scanShortcut),
                        ],
                        const SizedBox(height: 18),
                        _buildServicesSection(listServices),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<_HomeServiceItem> _serviceItems(BuildContext context) {
    final permissions = AppPermissions.fromUser(_user);
    final canIssueCards = permissions.canIssueCards;
    final canScanCards = permissions.canOpenCardTools;
    final canReviewCards = permissions.canReviewCards;
    final canViewBalance = permissions.canViewBalance;
    final canViewTransactions = permissions.canViewTransactions;
    final canViewInventory = permissions.canViewInventory;
    final canViewQuickTransfer = permissions.canOpenQuickTransfer;
    final canManageDebtBook = permissions.canManageDebtBook;
    final canViewSecuritySettings = permissions.canViewSecuritySettings;
    final canRequestCardPrinting = permissions.canRequestCardPrinting;
    final l = context.loc;
    final showOfflineSyncAction =
        _canOfflineScan &&
        _isDeviceOnline &&
        (_pendingOfflineCount > 0 || _isSyncingOfflineWorkspace);

    if (OfflineSessionService.isOfflineMode) {
      return [
        if (canScanCards)
          _HomeServiceItem(
            title: l.tr('screens_home_screen.015'),
            subtitle: l.tr('screens_home_screen.016'),
            icon: Icons.qr_code_scanner_rounded,
            color: AppTheme.success,
            kind: _HomeServiceKind.scan,
            onTap: _openScanScreen,
          ),
      ];
    }

    if (canReviewCards && !canIssueCards) {
      return [
        if (showOfflineSyncAction)
          _HomeServiceItem(
            title: _isSyncingOfflineWorkspace
                ? _t('screens_home_screen.064')
                : _t('screens_home_screen.065'),
            subtitle: _pendingOfflineCount > 0
                ? _t(
                    'screens_home_screen.073',
                    params: {'count': '$_pendingOfflineCount'},
                  )
                : _t('screens_home_screen.074'),
            icon: Icons.cloud_sync_rounded,
            color: AppTheme.primary,
            kind: _HomeServiceKind.sync,
            onTap: () => unawaited(_syncOfflineWorkspace()),
          ),
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          kind: _HomeServiceKind.scan,
          onTap: _openScanScreen,
        ),
        if (canManageDebtBook)
          _HomeServiceItem(
            title: _t('screens_home_screen.071'),
            subtitle: _t('screens_home_screen.076'),
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF7C3AED),
            kind: _HomeServiceKind.debtBook,
            onTap: () => Navigator.pushNamed(context, '/debt-book'),
          ),
      ];
    }

    return [
      if (showOfflineSyncAction)
        _HomeServiceItem(
          title: _isSyncingOfflineWorkspace
              ? _t('screens_home_screen.064')
              : _t('screens_home_screen.065'),
          subtitle: _pendingOfflineCount > 0
              ? _t(
                  'screens_home_screen.077',
                  params: {'count': '$_pendingOfflineCount'},
                )
              : _t('screens_home_screen.078'),
          icon: Icons.cloud_sync_rounded,
          color: AppTheme.primary,
          kind: _HomeServiceKind.sync,
          onTap: () => unawaited(_syncOfflineWorkspace()),
        ),
      if (canScanCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          kind: _HomeServiceKind.scan,
          onTap: _openScanScreen,
        ),
      if (canViewBalance)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.017'),
          subtitle: l.tr('screens_home_screen.018'),
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.primary,
          kind: _HomeServiceKind.balance,
          onTap: () => unawaited(_openOnlineOnlyRoute('/balance')),
        ),
      if (canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.019'),
          subtitle: l.tr('screens_home_screen.020'),
          icon: Icons.add_card_rounded,
          color: const Color(0xFF0B75B7),
          kind: _HomeServiceKind.createCard,
          onTap: () => unawaited(_openOnlineOnlyRoute('/create-card')),
        ),
      if (canViewQuickTransfer && _canTransfer)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.021'),
          subtitle: l.tr('screens_home_screen.022'),
          icon: Icons.send_to_mobile_rounded,
          color: AppTheme.accent,
          kind: _HomeServiceKind.quickTransfer,
          onTap: () => unawaited(_openOnlineOnlyRoute('/quick-transfer')),
        ),
      if (canViewInventory && canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.023'),
          subtitle: l.tr('screens_home_screen.024'),
          icon: Icons.inventory_2_rounded,
          color: AppTheme.textSecondary,
          kind: _HomeServiceKind.inventory,
          onTap: () => unawaited(_openOnlineOnlyRoute('/inventory')),
        ),
      if (canRequestCardPrinting)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.025'),
          subtitle: l.tr('screens_home_screen.026'),
          icon: Icons.print_rounded,
          color: AppTheme.secondary,
          kind: _HomeServiceKind.printRequests,
          onTap: () => unawaited(_openOnlineOnlyRoute('/card-print-requests')),
        ),
      if (canViewTransactions)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.027'),
          subtitle: l.tr('screens_home_screen.028'),
          icon: Icons.receipt_long_rounded,
          color: AppTheme.warning,
          kind: _HomeServiceKind.transactions,
          onTap: () => unawaited(_openOnlineOnlyRoute('/transactions')),
        ),
      _HomeServiceItem(
        title: l.tr('screens_home_screen.082'),
        subtitle: l.tr('screens_home_screen.083'),
        icon: Icons.campaign_rounded,
        color: const Color(0xFF0F766E),
        kind: _HomeServiceKind.affiliate,
        onTap: () => unawaited(_openOnlineOnlyRoute('/affiliate-center')),
      ),
      if (canManageDebtBook)
        _HomeServiceItem(
          title: _t('screens_home_screen.071'),
          subtitle: _t('screens_home_screen.079'),
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF7C3AED),
          kind: _HomeServiceKind.debtBook,
          onTap: () => Navigator.pushNamed(context, '/debt-book'),
        ),
      if (canViewSecuritySettings)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.029'),
          subtitle: l.tr('screens_home_screen.030'),
          icon: Icons.security_rounded,
          color: AppTheme.secondary,
          kind: _HomeServiceKind.security,
          onTap: () => unawaited(_openOnlineOnlyRoute('/security-settings')),
        ),
    ];
  }

  Widget _buildWelcomeCard() {
    final title = _displayName.isEmpty
        ? _t('screens_home_screen.084')
        : '${_t('screens_home_screen.084')}، $_displayName';
    final subtitle = _roleLabel.isEmpty
        ? _t('screens_home_screen.085')
        : _roleLabel;
    final userLogoUrl = _user?['printLogoUrl']?.toString().trim() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(26),
      shadowLevel: ShwakelShadowLevel.medium,
      gradient: const LinearGradient(
        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;
          final logo = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: userLogoUrl.isNotEmpty
                  ? Image.network(
                      userLogoUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/images/shwakel_app_icon.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/images/shwakel_app_icon.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                    ),
            ),
          );

          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: AppTheme.h2.copyWith(fontSize: 18, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTheme.bodyAction.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
                maxLines: isCompact ? null : 1,
                overflow: isCompact
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ],
          );

          return Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              logo,
              SizedBox(width: isCompact ? 0 : 14, height: isCompact ? 14 : 0),
              if (isCompact) textBlock else Expanded(child: textBlock),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScanShortcut(_HomeServiceItem item) {
    return ShwakelCard(
      onTap: item.onTap,
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.medium,
      borderColor: item.color.withValues(alpha: 0.16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final cta = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt_rounded, size: 18, color: item.color),
                const SizedBox(width: 6),
                Text(
                  _t('screens_home_screen.088'),
                  style: AppTheme.caption.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
          return Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              SizedBox(width: isCompact ? 0 : 14, height: isCompact ? 12 : 0),
              if (isCompact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('screens_home_screen.086'),
                      style: AppTheme.bodyBold.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t('screens_home_screen.087'),
                      style: AppTheme.bodyAction.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    cta,
                  ],
                )
              else ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('screens_home_screen.086'),
                        style: AppTheme.bodyBold.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t('screens_home_screen.087'),
                        style: AppTheme.bodyAction.copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                cta,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSyncStatusAction() {
    final hasPending = _pendingOfflineCount > 0;
    final canOpenStatus = _hasOfflineWorkspace || _canOpenCardTools;
    final backgroundColor = _isSyncingOfflineWorkspace
        ? AppTheme.warning.withValues(alpha: 0.16)
        : hasPending
        ? AppTheme.warning.withValues(alpha: 0.16)
        : AppTheme.success.withValues(alpha: 0.14);
    final iconColor = _isSyncingOfflineWorkspace
        ? AppTheme.warning
        : hasPending
        ? AppTheme.warning
        : AppTheme.success;
    final tooltip = _isSyncingOfflineWorkspace
        ? _t('screens_home_screen.064')
        : hasPending
        ? _t(
            'screens_home_screen.077',
            params: {'count': '$_pendingOfflineCount'},
          )
        : _t('screens_home_screen.053');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: IconButton(
        tooltip: tooltip,
        onPressed: !canOpenStatus ? null : _showSyncStatusSheet,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: _isSyncingOfflineWorkspace
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  : Icon(Icons.check_rounded, color: iconColor, size: 20),
            ),
            if (hasPending && !_isSyncingOfflineWorkspace)
              Positioned(
                top: -5,
                left: -5,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    _pendingOfflineCount > 9 ? '9+' : '$_pendingOfflineCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSyncStatusSheet() async {
    final lastSync = _formatSyncTimestamp(_lastOfflineSyncAt);
    final statusText = _isSyncingOfflineWorkspace
        ? _t('screens_home_screen.064')
        : _pendingOfflineCount > 0
        ? _t(
            'screens_home_screen.077',
            params: {'count': '$_pendingOfflineCount'},
          )
        : _t('screens_home_screen.053');

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('screens_home_screen.089'), style: AppTheme.h3),
              const SizedBox(height: 14),
              _syncInfoRow(_t('screens_home_screen.090'), statusText),
              _syncInfoRow(_t('screens_home_screen.091'), lastSync),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSyncTimestamp(String? raw) {
    final date = raw == null ? null : DateTime.tryParse(raw);
    if (date == null) {
      return _t('screens_home_screen.092');
    }
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Widget _syncInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _buildServicesSection(List<_HomeServiceItem> services) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.tr('screens_home_screen.004'), style: AppTheme.h2),
                    const SizedBox(height: 4),
                    Text(
                      services.isEmpty
                          ? l.tr('screens_home_screen.005')
                          : l.tr(
                              'screens_home_screen.034',
                              params: {'count': services.length.toString()},
                            ),
                      style: AppTheme.bodyAction,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (services.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                l.tr('screens_home_screen.005'),
                style: AppTheme.bodyAction,
              ),
            )
          else
            ...services.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == services.length - 1 ? 0 : 12,
                ),
                child: _buildServiceListItem(entry.value),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceListItem(_HomeServiceItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: item.onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;
              return Flex(
                direction: isCompact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isCompact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(item.icon, color: item.color, size: 26),
                  ),
                  SizedBox(
                    width: isCompact ? 0 : 14,
                    height: isCompact ? 12 : 0,
                  ),
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: AppTheme.bodyBold),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: AppTheme.bodyAction.copyWith(height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                          color: AppTheme.textSecondary.withValues(alpha: 0.7),
                        ),
                      ],
                    )
                  else ...[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: AppTheme.bodyBold),
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            style: AppTheme.bodyAction.copyWith(height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeServiceItem {
  const _HomeServiceItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.kind,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _HomeServiceKind kind;
  final VoidCallback onTap;
}

enum _HomeServiceKind {
  scan,
  sync,
  balance,
  createCard,
  quickTransfer,
  inventory,
  printRequests,
  transactions,
  affiliate,
  debtBook,
  security,
}
