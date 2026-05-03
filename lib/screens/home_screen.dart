import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.openSyncStatus = false});

  final bool openSyncStatus;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  static const String _balanceVisibleKeyPrefix = 'home_balance_visible';
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final DebtBookService _debtBookService = DebtBookService();
  final PrepaidMultipayOfflineCacheService _prepaidOfflineCache =
      const PrepaidMultipayOfflineCacheService();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _hasOfflineWorkspace = false;
  bool _hasOfflinePrepaidCards = false;
  bool _isSyncingOfflineWorkspace = false;
  bool _didPromptLocalSecuritySetup = false;
  bool _isBalanceVisible = true;
  bool _lastKnownDeviceOnline = ConnectivityService.instance.isOnline.value;
  int _pendingOfflineCount = 0;
  int _availableOfflineCount = 0;
  int _cachedOfflineCount = 0;
  int _rejectedOfflineCount = 0;
  int _offlineSyncIntervalMinutes = 60;
  String? _lastOfflineSyncAt;
  bool _offlineAccessExpired = false;
  StreamSubscription<Map<String, dynamic>>? _balanceSubscription;
  bool _routeSubscribed = false;
  bool _connectivityNoticeOpen = false;

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
    if (widget.openSyncStatus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showSyncStatusSheet());
        }
      });
    }
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

  bool get _canOpenPrepaidOfflineCards {
    return _hasOfflinePrepaidCards ||
        AppPermissions.fromUser(_user).canOpenPrepaidMultipayCards;
  }

  bool get _canOpenCardTools {
    return AppPermissions.fromUser(_user).canOpenCardTools;
  }

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  String get _displayName {
    final username = _user?['username']?.toString().trim() ?? '';
    return UserDisplayName.fromMap(_user, fallback: username);
  }

  String get _roleLabel {
    return _user?['roleLabel']?.toString().trim() ??
        _user?['role']?.toString().trim() ??
        '';
  }

  bool get _isVerifiedUser {
    final verificationStatus =
        _user?['transferVerificationStatus']?.toString().trim().toLowerCase() ??
        '';
    return _user?['isVerified'] == true || verificationStatus == 'approved';
  }

  String get _verificationLabel {
    return _isVerifiedUser
        ? context.loc.tr('screens_balance_screen.036')
        : context.loc.tr('screens_balance_screen.037');
  }

  Future<void> _loadUser() async {
    final hadUser = _user != null;
    if (!hadUser) {
      setState(() => _isLoading = true);
    }
    try {
      var user = await _authService.currentUser();
      if (user != null) {
        await _applyUserSnapshot(user, isLoading: false);
      }

      try {
        await _authService.refreshCurrentUser().timeout(
          const Duration(milliseconds: 1800),
        );
        user = await _authService.currentUser();
      } catch (_) {
        user ??= await _authService.currentUser();
      }

      await _applyUserSnapshot(user, isLoading: false);
    } catch (_) {
      final user = await _authService.currentUser();
      await _applyUserSnapshot(user, isLoading: false);
    }
  }

  Future<void> _applyUserSnapshot(
    Map<String, dynamic>? user, {
    required bool isLoading,
  }) async {
    final hasOfflineWorkspaceFuture = _resolveOfflineWorkspace(user);
    final hasOfflinePrepaidCardsFuture = _prepaidOfflineCache.hasCards();
    final offlineOverviewFuture = _resolveOfflineOverview(user);
    final isBalanceVisibleFuture = _resolveBalanceVisibility(user);

    final hasOfflineWorkspace = await hasOfflineWorkspaceFuture;
    final hasOfflinePrepaidCards = await hasOfflinePrepaidCardsFuture;
    final offlineOverview = await offlineOverviewFuture;
    final isBalanceVisible = await isBalanceVisibleFuture;

    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _hasOfflineWorkspace = hasOfflineWorkspace;
      _hasOfflinePrepaidCards = hasOfflinePrepaidCards;
      _isBalanceVisible = isBalanceVisible;
      _pendingOfflineCount =
          (offlineOverview['pendingCount'] as num?)?.toInt() ?? 0;
      _availableOfflineCount =
          (offlineOverview['availableCount'] as num?)?.toInt() ?? 0;
      _cachedOfflineCount =
          (offlineOverview['cachedCount'] as num?)?.toInt() ?? 0;
      _rejectedOfflineCount =
          (offlineOverview['rejectedCount'] as num?)?.toInt() ?? 0;
      _offlineSyncIntervalMinutes =
          (offlineOverview['syncIntervalMinutes'] as num?)?.toInt() ?? 60;
      _lastOfflineSyncAt = offlineOverview['lastSyncAt']?.toString();
      _offlineAccessExpired = offlineOverview['expired'] == true;
      _isLoading = isLoading;
    });
    _maybeSyncOfflineWorkspaceInBackground();
    unawaited(_maybePromptLocalSecuritySetup());
  }

  Future<void> _maybePromptLocalSecuritySetup() async {
    if (!mounted || _didPromptLocalSecuritySetup) {
      return;
    }
    if (await LocalSecurityService.hasConfiguredLocalSecurity()) {
      return;
    }
    final shouldPrompt =
        await LocalSecurityService.shouldPromptLocalSecuritySetupReminder();
    if (!mounted || !shouldPrompt) {
      return;
    }
    _didPromptLocalSecuritySetup = true;
    final l = context.loc;
    final shouldOpenSecuritySetup = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_security_settings_screen.072')),
        content: Text(l.tr('screens_security_settings_screen.073')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('screens_login_screen.019')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.tr('screens_login_screen.020')),
          ),
        ],
      ),
    );
    await LocalSecurityService.markLocalSecuritySetupReminderShown();
    if (!mounted || shouldOpenSecuritySetup != true) {
      return;
    }
    Navigator.pushNamed(
      context,
      '/security-settings',
      arguments: const {'showSetupHint': true},
    );
  }

  Future<Map<String, dynamic>> _resolveOfflineOverview(
    Map<String, dynamic>? user,
  ) async {
    final permissions = AppPermissions.fromUser(user);
    if (user == null || user['id'] == null || !permissions.canOfflineCardScan) {
      return const {
        'pendingCount': 0,
        'availableCount': 0,
        'cachedCount': 0,
        'rejectedCount': 0,
        'syncIntervalMinutes': 60,
        'lastSyncAt': null,
        'expired': false,
      };
    }
    final overview = await _offlineCardService.offlineOverview(
      user['id'].toString(),
    );
    final summary = Map<String, dynamic>.from(
      overview['summary'] as Map? ?? const {},
    );
    final settings = Map<String, dynamic>.from(
      overview['settings'] as Map? ?? const {},
    );
    final interval =
        (((settings['syncIntervalMinutes'] as num?)?.toInt() ?? 60).clamp(
          5,
          1440,
        )).toInt();
    final lastSyncAt = settings['lastSyncAt']?.toString();
    final parsedLastSync = DateTime.tryParse(lastSyncAt ?? '');
    final expired =
        parsedLastSync == null ||
        DateTime.now().difference(parsedLastSync.toLocal()).inMinutes >=
            interval;
    return {
      'pendingCount': (summary['count'] as num?)?.toInt() ?? 0,
      'availableCount': (overview['availableCount'] as num?)?.toInt() ?? 0,
      'cachedCount': (overview['cachedCount'] as num?)?.toInt() ?? 0,
      'rejectedCount': (summary['rejectedCount'] as num?)?.toInt() ?? 0,
      'syncIntervalMinutes': interval,
      'lastSyncAt': lastSyncAt,
      'expired': expired,
    };
  }

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    final isOnline = ConnectivityService.instance.isOnline.value;
    final regainedConnection = !_lastKnownDeviceOnline && isOnline;
    final lostConnection = _lastKnownDeviceOnline && !isOnline;
    _lastKnownDeviceOnline = isOnline;

    if (lostConnection) {
      final canOffline = _canOfflineScan || _hasOfflinePrepaidCards;
      if (canOffline) {
        OfflineSessionService.setOfflineMode(true);
        AppAlertService.showSnack(
          context,
          message: 'تم فصل الانترنت. تم تفعيل وضع الأوفلاين.',
          type: AppAlertType.info,
          duration: const Duration(seconds: 4),
        );
      } else {
        // User cannot operate offline; require secure logout to avoid broken flows.
        if (!_connectivityNoticeOpen) {
          _connectivityNoticeOpen = true;
          unawaited(() async {
            await AppAlertService.showInfo(
              context,
              title: 'تم فصل الانترنت',
              message:
                  'لا تملك صلاحية استخدام التطبيق بدون اتصال. سيتم تحويلك لتسجيل خروج آمن.',
            );
            if (!mounted) return;
            _connectivityNoticeOpen = false;
            await QuickLogoutAction.logout(context);
          }());
        }
      }
    }

    if (regainedConnection) {
      if (OfflineSessionService.isOfflineMode) {
        OfflineSessionService.setOfflineMode(false);
        AppAlertService.showSnack(
          context,
          message: 'تم استعادة الاتصال. تم تفعيل وضع الأونلاين.',
          type: AppAlertType.success,
          duration: const Duration(seconds: 4),
        );
      } else {
        AppAlertService.showSnack(
          context,
          message: 'تم استعادة الاتصال.',
          type: AppAlertType.success,
        );
      }
      _maybeSyncOfflineWorkspaceInBackground();
    }
    setState(() {});
  }

  void _maybeSyncOfflineWorkspaceInBackground() {
    if (!mounted ||
        !_canOfflineScan ||
        !_isDeviceOnline ||
        _isSyncingOfflineWorkspace) {
      return;
    }
    final needsSync = _pendingOfflineCount > 0 || _offlineAccessExpired;
    if (!needsSync) {
      return;
    }
    unawaited(_syncOfflineWorkspace(triggeredAutomatically: true));
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
    var rejectedSyncCount = 0;
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
        rejectedSyncCount = rejectedHistoryEntries.length;

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
        final balanceOwnerId = result['balanceOwnerId']?.toString();
        if (updatedBalance != null &&
            (balanceOwnerId == null ||
                balanceOwnerId.isEmpty ||
                balanceOwnerId == userId)) {
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
      OfflineSessionService.setOfflineMode(false);

      await _loadUser();
      if (!mounted) {
        return;
      }
      if (!triggeredAutomatically) {
        final successMessage = queuedBeforeSync.isNotEmpty
            ? _t(
                'screens_home_screen.052',
                params: {
                  'accepted': '${queuedBeforeSync.length - rejectedSyncCount}',
                  'rejected': '$rejectedSyncCount',
                },
              )
            : _t('screens_home_screen.053');
        AppAlertService.showSnack(
          context,
          message: successMessage,
          type: AppAlertType.success,
        );
      }
    } catch (error) {
      if (!mounted || triggeredAutomatically) {
        return;
      }
      AppAlertService.showSnack(
        context,
        message:
            '${_t('screens_home_screen.054')}: ${ErrorMessageService.sanitize(error)}',
        type: AppAlertType.error,
        duration: const Duration(seconds: 4),
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

  Future<bool> _resolveOfflineWorkspace(Map<String, dynamic>? user) async {
    final permissions = AppPermissions.fromUser(user);
    if (user == null || user['id'] == null || !permissions.canOfflineCardScan) {
      return false;
    }
    return _offlineCardService.hasOfflineWorkspace(user['id'].toString());
  }

  bool get _isDeviceOnline => ConnectivityService.instance.isOnline.value;

  String _balanceVisibilityPreferenceKey(Map<String, dynamic>? user) {
    final userId = user?['id']?.toString().trim();
    return '${_balanceVisibleKeyPrefix}_${userId?.isNotEmpty == true ? userId : 'guest'}';
  }

  Future<bool> _resolveBalanceVisibility(Map<String, dynamic>? user) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_balanceVisibilityPreferenceKey(user)) ?? true;
  }

  Future<void> _setBalanceVisibility(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_balanceVisibilityPreferenceKey(_user), visible);
    if (!mounted) {
      return;
    }
    setState(() => _isBalanceVisible = visible);
  }

  String get _scanCameraRoute => OfflineSessionService.isOfflineMode
      ? '/scan-card-offline-camera'
      : '/scan-card-camera';

  void _openScanScreen() {
    if (OfflineSessionService.isOfflineMode && _offlineAccessExpired) {
      unawaited(_showExpiredOfflineSyncRequired());
      return;
    }
    Navigator.pushNamed(context, _scanCameraRoute);
  }

  Future<void> _showExpiredOfflineSyncRequired() {
    return AppAlertService.showError(
      context,
      title: _t('screens_scan_card_screen.118'),
      message: _t(
        'screens_scan_card_screen.119',
        params: {'minutes': _offlineSyncIntervalMinutes.toString()},
      ),
    );
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: _t('screens_home_screen.061'),
      message: _t('screens_home_screen.062'),
    );
  }

  Future<void> _openOnlineOnlyRoute(
    String routeName, {
    Object? arguments,
  }) async {
    if (OfflineSessionService.isOfflineMode &&
        routeName != '/inventory' &&
        routeName != '/prepaid-multipay-cards') {
      await _showOfflineBlockedMessage();
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.pushNamed(context, routeName, arguments: arguments);
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
          if (_canOfflineScan) _buildSyncStatusAction(),
          if (!OfflineSessionService.isOfflineMode)
            const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ResponsiveScaffoldContainer(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
                    child: _buildHomeContent(
                      context,
                      scanShortcut: scanShortcut,
                      listServices: listServices,
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
    final canManageDebtBook = permissions.canManageDebtBook;
    final canViewAffiliateCenter = permissions.canViewAffiliateCenter;
    final canViewSecuritySettings = permissions.canViewSecuritySettings;
    final canRequestCardPrinting = permissions.canRequestCardPrinting;
    final canOpenPrepaidMultipayCards = _canOpenPrepaidOfflineCards;
    final canAcceptNfcPayments = permissions.canAcceptPrepaidMultipayPayments;
    final l = context.loc;
    final showOfflineSyncAction =
        _canOfflineScan &&
        _isDeviceOnline &&
        (_pendingOfflineCount > 0 || _isSyncingOfflineWorkspace);

    if (OfflineSessionService.isOfflineMode) {
      return [
        if (_canOfflineScan && (_isDeviceOnline || _offlineAccessExpired))
          _HomeServiceItem(
            title: _isSyncingOfflineWorkspace
                ? _t('screens_home_screen.064')
                : _t('screens_home_screen.108'),
            subtitle: _offlineAccessExpired
                ? _t('screens_home_screen.109')
                : _t('screens_home_screen.110'),
            icon: Icons.cloud_sync_rounded,
            color: _offlineAccessExpired ? AppTheme.error : AppTheme.primary,
            kind: _HomeServiceKind.sync,
            onTap: () => unawaited(_syncOfflineWorkspace()),
            badgeIcon: _isSyncingOfflineWorkspace
                ? Icons.sync_rounded
                : _offlineAccessExpired
                ? Icons.priority_high_rounded
                : Icons.check_rounded,
            badgeColor: _offlineAccessExpired
                ? AppTheme.error
                : AppTheme.success,
          ),
        if (canScanCards)
          _HomeServiceItem(
            title:
                '${l.tr('screens_home_screen.015')} ($_availableOfflineCount)',
            subtitle: _offlineAccessExpired
                ? _t('screens_home_screen.111')
                : _t('screens_home_screen.112'),
            icon: Icons.qr_code_scanner_rounded,
            color: _offlineAccessExpired ? AppTheme.error : AppTheme.success,
            kind: _HomeServiceKind.scan,
            onTap: _openScanScreen,
            badgeIcon: _offlineAccessExpired
                ? Icons.priority_high_rounded
                : Icons.check_rounded,
            badgeColor: _offlineAccessExpired
                ? AppTheme.error
                : AppTheme.success,
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
        if (canViewAffiliateCenter)
          _HomeServiceItem(
            title: l.tr('screens_home_screen.082'),
            subtitle: _t('screens_home_screen.113'),
            icon: Icons.campaign_rounded,
            color: const Color(0xFF0F766E),
            kind: _HomeServiceKind.affiliate,
            onTap: () => Navigator.pushNamed(context, '/affiliate-center'),
          ),
        if (canViewInventory && canIssueCards && _hasOfflineWorkspace)
          _HomeServiceItem(
            title: l.tr('screens_home_screen.023'),
            subtitle: _t('screens_home_screen.114'),
            icon: Icons.inventory_2_rounded,
            color: AppTheme.textSecondary,
            kind: _HomeServiceKind.inventory,
            onTap: () => unawaited(_openOnlineOnlyRoute('/inventory')),
          ),
        if (canOpenPrepaidMultipayCards)
          _HomeServiceItem(
            title: l.tr('screens_home_screen.118'),
            subtitle: 'بطاقات محفوظة على الجهاز للعرض والدفع بدون تلامس.',
            icon: Icons.credit_card_rounded,
            color: const Color(0xFF334155),
            kind: _HomeServiceKind.prepaidMultipay,
            onTap: () =>
                Navigator.pushNamed(context, '/prepaid-multipay-cards'),
            badgeIcon: Icons.offline_bolt_rounded,
            badgeColor: AppTheme.warning,
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
                ? _t('screens_home_screen.109')
                : _t('screens_home_screen.115'),
            icon: Icons.cloud_sync_rounded,
            color: AppTheme.primary,
            kind: _HomeServiceKind.sync,
            onTap: () => unawaited(_syncOfflineWorkspace()),
            badgeIcon: _isSyncingOfflineWorkspace
                ? Icons.sync_rounded
                : _pendingOfflineCount > 0
                ? Icons.priority_high_rounded
                : Icons.check_rounded,
            badgeColor: _pendingOfflineCount > 0
                ? AppTheme.warning
                : AppTheme.success,
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
              ? _t('screens_home_screen.109')
              : _t('screens_home_screen.115'),
          icon: Icons.cloud_sync_rounded,
          color: AppTheme.primary,
          kind: _HomeServiceKind.sync,
          onTap: () => unawaited(_syncOfflineWorkspace()),
          badgeIcon: _isSyncingOfflineWorkspace
              ? Icons.sync_rounded
              : _pendingOfflineCount > 0
              ? Icons.priority_high_rounded
              : Icons.check_rounded,
          badgeColor: _pendingOfflineCount > 0
              ? AppTheme.warning
              : AppTheme.success,
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
      if (canOpenPrepaidMultipayCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.118'),
          subtitle: permissions.canUsePrepaidMultipayCards
              ? l.tr('screens_home_screen.119')
              : l.tr('screens_home_screen.120'),
          icon: Icons.credit_card_rounded,
          color: const Color(0xFF334155),
          kind: _HomeServiceKind.prepaidMultipay,
          onTap: () =>
              unawaited(_openOnlineOnlyRoute('/prepaid-multipay-cards')),
        ),
      if (canAcceptNfcPayments)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.121'),
          subtitle: l.tr('screens_home_screen.122'),
          icon: Icons.contactless_rounded,
          color: const Color(0xFF0F766E),
          kind: _HomeServiceKind.prepaidMultipay,
          onTap: () => Navigator.pushNamed(
            context,
            '/prepaid-multipay-contactless-accept',
            arguments: const {'autoReadNfc': true},
          ),
          badgeIcon: Icons.contactless_rounded,
          badgeColor: AppTheme.success,
        ),
      if (_canTransfer)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.021'),
          subtitle: l.tr('screens_home_screen.022'),
          icon: Icons.send_to_mobile_rounded,
          color: AppTheme.accent,
          kind: _HomeServiceKind.quickTransfer,
          onTap: () => unawaited(_openOnlineOnlyRoute('/quick-transfer')),
        ),
      if (_canTransfer)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.123'),
          subtitle: l.tr('screens_home_screen.124'),
          icon: Icons.qr_code_2_rounded,
          color: const Color(0xFF0F766E),
          kind: _HomeServiceKind.temporaryTransfer,
          onTap: () => unawaited(
            _openOnlineOnlyRoute(
              '/scan-card',
              arguments: const {'openTemporaryTransferCreator': true},
            ),
          ),
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
      if (canViewAffiliateCenter)
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
    final greeting = _t('screens_home_screen.084');
    final displayName = _displayName;
    final roleLabel = _roleLabel.isEmpty
        ? _t('screens_home_screen.085')
        : _roleLabel;
    final userLogoUrl = _user?['printLogoUrl']?.toString().trim() ?? '';
    final balance = (_user?['balance'] as num?)?.toDouble() ?? 0;
    final balanceTextColor = balance < 0
        ? const Color(0xFFFCA5A5)
        : Colors.white;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
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
          final logoSize = isCompact ? 64.0 : 72.0;
          final logoImageSize = isCompact ? 38.0 : 44.0;
          Widget infoChip({
            required IconData icon,
            required String label,
            required Color color,
          }) {
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 10 : 12,
                vertical: isCompact ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTheme.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }

          final metaBlock = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              infoChip(
                icon: Icons.badge_rounded,
                label: roleLabel,
                color: Colors.white,
              ),
              infoChip(
                icon: _isVerifiedUser
                    ? Icons.verified_rounded
                    : Icons.pending_outlined,
                label: _verificationLabel,
                color: _isVerifiedUser
                    ? const Color(0xFFA7F3D0)
                    : const Color(0xFFFDE68A),
              ),
            ],
          );
          final logo = Container(
            width: logoSize,
            height: logoSize,
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
                      width: logoImageSize,
                      height: logoImageSize,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Image.asset(
                        'assets/images/shwakel_app_icon.png',
                        width: logoImageSize,
                        height: logoImageSize,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Image.asset(
                      'assets/images/shwakel_app_icon.png',
                      width: logoImageSize,
                      height: logoImageSize,
                      fit: BoxFit.contain,
                    ),
            ),
          );
          final balanceCard = Container(
            width: double.infinity,
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('screens_home_screen.093'),
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _isBalanceVisible
                          ? _t('screens_home_screen.096')
                          : _t('screens_home_screen.099'),
                      onPressed: () =>
                          _setBalanceVisibility(!_isBalanceVisible),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        _isBalanceVisible
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isBalanceVisible
                            ? CurrencyFormatter.ils(balance)
                            : '******',
                        textAlign: TextAlign.end,
                        style: AppTheme.h1.copyWith(
                          color: balanceTextColor,
                          fontSize: isCompact ? 28 : 32,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isCompact ? 6 : 8),
                Text(
                  _t('screens_home_screen.094'),
                  textAlign: TextAlign.start,
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                    height: 1.4,
                    fontSize: isCompact ? 14 : 15,
                  ),
                ),
                if (_canOfflineScan) ...[
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'screens_home_screen.116',
                      params: {
                        'time': _formatSyncTimestamp(_lastOfflineSyncAt),
                        'suffix': OfflineSessionService.isOfflineMode
                            ? _t('screens_home_screen.117')
                            : '',
                      },
                    ),
                    style: AppTheme.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          );

          final compactHeader = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (displayName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        style: AppTheme.h2.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    metaBlock,
                  ],
                ),
              ),
              const SizedBox(width: 14),
              logo,
            ],
          );

          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact)
                compactHeader
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    logo,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: AppTheme.bodyAction.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (displayName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              displayName,
                              style: AppTheme.h2.copyWith(
                                fontSize: 22,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                metaBlock,
              ],
              SizedBox(height: isCompact ? 12 : 16),
              balanceCard,
            ],
          );

          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 144),
            child: textBlock,
          );
        },
      ),
    );
  }

  Widget _buildHomeContent(
    BuildContext context, {
    required _HomeServiceItem? scanShortcut,
    required List<_HomeServiceItem> listServices,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isLandscapePhone =
            mediaQuery.orientation == Orientation.landscape &&
            constraints.maxWidth < 1100;

        if (!isLandscapePhone) {
          return Column(
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
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: _buildWelcomeCard()),
                if (scanShortcut != null) ...[
                  const SizedBox(width: 14),
                  Expanded(flex: 9, child: _buildScanShortcut(scanShortcut)),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _buildServicesSection(listServices),
          ],
        );
      },
    );
  }

  Widget _buildServicesGrid(
    List<_HomeServiceItem> services, {
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: services.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, index) =>
          _buildCompactServiceTile(services[index]),
    );
  }

  Widget _buildScanShortcut(_HomeServiceItem item) {
    return ShwakelCard(
      onTap: item.onTap,
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.medium,
      borderColor: item.color.withValues(alpha: 0.16),
      color: item.color.withValues(alpha: 0.04),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final cta = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: item.color.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
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
          final iconBox = Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(item.icon, color: item.color, size: 30),
          );

          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('screens_home_screen.086'),
                style: AppTheme.bodyBold.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                _t('screens_home_screen.087'),
                style: AppTheme.bodyAction.copyWith(height: 1.45),
              ),
            ],
          );

          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 148),
            child: isCompact
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconBox,
                          const SizedBox(width: 14),
                          Expanded(child: textBlock),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(width: double.infinity, child: cta),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      iconBox,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [textBlock],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Align(
                        alignment: Alignment.center,
                        child: SizedBox(width: 170, child: cta),
                      ),
                    ],
                  ),
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
              _syncInfoRow(
                _t('screens_home_screen.100'),
                _t(
                  'screens_home_screen.101',
                  params: {
                    'available': '$_availableOfflineCount',
                    'cached': '$_cachedOfflineCount',
                  },
                ),
              ),
              _syncInfoRow(
                _t('screens_home_screen.102'),
                '$_pendingOfflineCount',
              ),
              if (_rejectedOfflineCount > 0)
                _syncInfoRow(
                  _t('screens_home_screen.103'),
                  '$_rejectedOfflineCount',
                ),
              _syncInfoRow(
                _t('screens_home_screen.104'),
                _t(
                  'screens_home_screen.105',
                  params: {'minutes': '$_offlineSyncIntervalMinutes'},
                ),
              ),
              if (_offlineAccessExpired)
                _syncInfoRow(
                  _t('screens_home_screen.090'),
                  _t('screens_home_screen.106'),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSyncingOfflineWorkspace || !_isDeviceOnline
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          unawaited(_syncOfflineWorkspace());
                        },
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: Text(_t('screens_home_screen.107')),
                ),
              ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final isLandscapePhone =
            mediaQuery.orientation == Orientation.landscape &&
            constraints.maxWidth < 1100;
        final useCompactGrid = constraints.maxWidth < 640 || isLandscapePhone;
        final sectionHeader = Row(
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
        );

        final emptyState = Container(
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
        );

        final compactBody = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionHeader,
            const SizedBox(height: 16),
            if (services.isEmpty)
              emptyState
            else
              _buildServicesGrid(
                services,
                crossAxisCount: isLandscapePhone ? 4 : 3,
                childAspectRatio: isLandscapePhone ? 1.15 : 0.92,
              ),
          ],
        );

        if (useCompactGrid) {
          return compactBody;
        }

        return ShwakelCard(
          padding: const EdgeInsets.all(20),
          borderRadius: BorderRadius.circular(28),
          shadowLevel: ShwakelShadowLevel.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionHeader,
              const SizedBox(height: 18),
              if (services.isEmpty)
                emptyState
              else
                Column(
                  children: services
                      .asMap()
                      .entries
                      .map((entry) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.key == services.length - 1 ? 0 : 12,
                          ),
                          child: _buildServiceListItem(entry.value),
                        );
                      })
                      .toList(growable: false),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactServiceTile(_HomeServiceItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: item.onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(item.icon, color: item.color, size: 24),
                  ),
                  if (item.badgeIcon != null)
                    Positioned(
                      top: -4,
                      left: -4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (item.badgeColor ?? item.color).withValues(
                              alpha: 0.24,
                            ),
                          ),
                        ),
                        child: Icon(
                          item.badgeIcon,
                          size: 12,
                          color: item.badgeColor ?? item.color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
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
                  Stack(
                    clipBehavior: Clip.none,
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
                      if (item.badgeIcon != null)
                        Positioned(
                          top: -4,
                          left: -4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (item.badgeColor ?? item.color)
                                    .withValues(alpha: 0.24),
                              ),
                            ),
                            child: Icon(
                              item.badgeIcon,
                              size: 14,
                              color: item.badgeColor ?? item.color,
                            ),
                          ),
                        ),
                    ],
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
    this.badgeIcon,
    this.badgeColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _HomeServiceKind kind;
  final VoidCallback onTap;
  final IconData? badgeIcon;
  final Color? badgeColor;
}

enum _HomeServiceKind {
  scan,
  sync,
  balance,
  createCard,
  prepaidMultipay,
  quickTransfer,
  temporaryTransfer,
  inventory,
  printRequests,
  transactions,
  affiliate,
  debtBook,
  security,
}
