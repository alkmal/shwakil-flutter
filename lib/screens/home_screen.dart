import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import 'scan_card_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final OfflineCardService _offlineCardService = OfflineCardService();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _hasOfflineWorkspace = false;
  bool _isSyncingOfflineWorkspace = false;
  bool _didSuggestOfflineWorkspace = false;
  bool _lastKnownDeviceOnline = ConnectivityService.instance.isOnline.value;
  int _pendingOfflineCount = 0;
  double _pendingOfflineAmount = 0;
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

  bool get _canIssueCards {
    return AppPermissions.fromUser(_user).canIssueCards;
  }

  bool get _canTransfer {
    return AppPermissions.fromUser(_user).canTransfer;
  }

  bool get _canReviewCards {
    return AppPermissions.fromUser(_user).canReviewCards;
  }

  bool get _canOfflineScan {
    return AppPermissions.fromUser(_user).canOfflineCardScan;
  }

  bool get _canOpenCardTools {
    return AppPermissions.fromUser(_user).canOpenCardTools;
  }

  bool get _isVerifiedAccount =>
      _user?['transferVerificationStatus']?.toString() == 'approved';

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      await _authService.refreshCurrentUser();
      final user = await _authService.currentUser();
      final hasOfflineWorkspace = await _resolveOfflineWorkspace(user);
      final pendingSummary = await _resolveOfflinePendingSummary(user);
      if (!mounted) return;
      setState(() {
        _user = user;
        _hasOfflineWorkspace = hasOfflineWorkspace;
        _pendingOfflineCount = (pendingSummary['count'] as num?)?.toInt() ?? 0;
        _pendingOfflineAmount =
            (pendingSummary['amount'] as num?)?.toDouble() ?? 0;
        _isLoading = false;
      });
      _maybeSuggestOfflineWorkspace();
    } catch (_) {
      final user = await _authService.currentUser();
      final hasOfflineWorkspace = await _resolveOfflineWorkspace(user);
      final pendingSummary = await _resolveOfflinePendingSummary(user);
      if (!mounted) return;
      setState(() {
        _user = user;
        _hasOfflineWorkspace = hasOfflineWorkspace;
        _pendingOfflineCount = (pendingSummary['count'] as num?)?.toInt() ?? 0;
        _pendingOfflineAmount =
            (pendingSummary['amount'] as num?)?.toDouble() ?? 0;
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
    final hadPendingItems = queuedBeforeSync.isNotEmpty;

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

      int acceptedCount = 0;
      int rejectedCount = 0;
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

        acceptedCount = acceptedBarcodes.length;
        rejectedCount = rejectedBarcodes.length;

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

      await _loadUser();
      if (!mounted) {
        return;
      }

      if (hadPendingItems || triggeredAutomatically) {
        AppAlertService.showSuccess(
          context,
          title: triggeredAutomatically
              ? 'تمت مزامنة الأوف لاين'
              : 'اكتملت مزامنة البطاقات',
          message: hadPendingItems
              ? 'تمت مزامنة $acceptedCount بطاقة معلقة، وبقي $rejectedCount للمراجعة، كما تم تنزيل أحدث بطاقات الأوف لاين.'
              : 'تم تنزيل أحدث بطاقات الأوف لاين وتحديث مساحة العمل المحلية.',
        );
      }
    } catch (error) {
      if (!mounted || triggeredAutomatically) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذرت مزامنة الأوف لاين',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingOfflineWorkspace = false);
      }
    }
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
          title: const Text('مساحة الأوف لاين جاهزة'),
          content: const Text(
            'يوجد على هذا الجهاز مخزون أوف لاين جاهز. هل تريد الانتقال مباشرة إلى قراءة البطاقات الأوف لاين؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('لاحقًا'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('فتح الأوف لاين'),
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

  bool get _isRestrictedOfflineWorkspaceUser {
    final permissions = AppPermissions.fromUser(_user);
    return permissions.canOfflineCardScan && !permissions.canIssueCards;
  }

  bool get _isDeviceOnline => ConnectivityService.instance.isOnline.value;

  String get _scanRoute =>
      OfflineSessionService.isOfflineMode ? '/scan-card-offline' : '/scan-card';

  void _openScanScreen() {
    Navigator.pushNamed(context, _scanRoute);
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: 'هذه الشاشة غير متاحة دون إنترنت',
      message:
          'أنت الآن في وضع الأوفلاين. هذه الشاشة تحتاج اتصالًا بالإنترنت حتى تعمل.',
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

  Future<void> _startHomeBarcodeScan() async {
    if (!_canOpenCardTools && !_canReviewCards) return;
    final l = context.loc;
    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BarcodeScannerDialog(
        title: l.tr('screens_home_screen.014'),
        description: l.tr('screens_home_screen.013'),
        height: 320,
        onCancelLabel: l.tr('screens_home_screen.001'),
      ),
    );
    if (!mounted || scannedValue == null || scannedValue.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanCardScreen(
          initialBarcode: scannedValue,
          offlineMode: OfflineSessionService.isOfflineMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final services = _serviceItems(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_home_screen.002')),
        actions: [const AppNotificationAction(), const QuickLogoutAction()],
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
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final isMobile = width < 700;
                        final isTablet = width < 1100;
                        final showBarcodeCard =
                            _canIssueCards || _canReviewCards;
                        final columns = width < 420
                            ? 1
                            : (isMobile ? 2 : (isTablet ? 2 : 3));
                        final spacing = isMobile ? 16.0 : 18.0;
                        final itemWidth =
                            (width - (spacing * (columns - 1))) / columns;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopSection(
                              isMobile: isMobile,
                              showBarcodeCard: showBarcodeCard,
                            ),
                            const SizedBox(height: 24),
                            _buildSectionHeader(
                              title: l.tr('screens_home_screen.004'),
                              subtitle: l.tr('screens_home_screen.005'),
                              actionLabel: '${services.length} خدمات',
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: services
                                  .map(
                                    (service) => SizedBox(
                                      width: itemWidth,
                                      child: _buildServiceCard(
                                        title: service.title,
                                        subtitle: service.subtitle,
                                        icon: service.icon,
                                        color: service.color,
                                        onTap: service.onTap,
                                        compact: isMobile,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        );
                      },
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
    final canOpenOfflineCenter = _hasOfflineWorkspace || canScanCards;
    final showOfflineSyncAction =
        _canOfflineScan &&
        _isDeviceOnline &&
        (_pendingOfflineCount > 0 || _isSyncingOfflineWorkspace);

    if (OfflineSessionService.isOfflineMode ||
        _isRestrictedOfflineWorkspaceUser) {
      return [
        if (showOfflineSyncAction)
          _HomeServiceItem(
            title: _isSyncingOfflineWorkspace
                ? 'جاري مزامنة الأوف لاين'
                : 'مزامنة الأوف لاين',
            subtitle: _pendingOfflineCount > 0
                ? 'يوجد $_pendingOfflineCount بطاقة معلقة بقيمة ${_pendingOfflineAmount.toStringAsFixed(2)} شيكل وسيتم تحديث المخزون المحلي أيضًا.'
                : 'تحديث البطاقات المحلية وتنزيل أي بطاقات جديدة متاحة لهذا الجهاز.',
            icon: Icons.cloud_sync_rounded,
            color: AppTheme.primary,
            onTap: () => unawaited(_syncOfflineWorkspace()),
          ),
        if (canScanCards)
          _HomeServiceItem(
            title: l.tr('screens_home_screen.015'),
            subtitle: l.tr('screens_home_screen.016'),
            icon: Icons.qr_code_scanner_rounded,
            color: AppTheme.success,
            onTap: _openScanScreen,
          ),
        if (canOpenOfflineCenter)
          _HomeServiceItem(
            title: 'مركز الأوف لاين',
            subtitle: OfflineSessionService.isOfflineMode
                ? 'إظهار أدوات الأوف لاين فقط دون أي شاشات أونلاين.'
                : 'إدارة مخزون الأوف لاين ومزامنة العمليات دون كشف البطاقات المحفوظة.',
            icon: Icons.cloud_done_rounded,
            color: AppTheme.warning,
            onTap: () => Navigator.pushNamed(context, '/offline-center'),
          ),
        if (canManageDebtBook)
          _HomeServiceItem(
            title: 'دفتر الديون',
            subtitle: 'متاح للعمل المحلي مع رفع التعديلات عند عودة الإنترنت.',
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.pushNamed(context, '/debt-book'),
          ),
      ];
    }

    if (canReviewCards && !canIssueCards) {
      return [
        if (showOfflineSyncAction)
          _HomeServiceItem(
            title: _isSyncingOfflineWorkspace
                ? 'جاري مزامنة الأوف لاين'
                : 'مزامنة الأوف لاين',
            subtitle: _pendingOfflineCount > 0
                ? 'يوجد $_pendingOfflineCount بطاقة معلقة للمزامنة، مع تحديث تلقائي لمخزون الأوف لاين.'
                : 'تحديث مساحة الأوف لاين وتنزيل البطاقات الجديدة لهذا الجهاز.',
            icon: Icons.cloud_sync_rounded,
            color: AppTheme.primary,
            onTap: () => unawaited(_syncOfflineWorkspace()),
          ),
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: _openScanScreen,
        ),
        if (canOpenOfflineCenter)
          _HomeServiceItem(
            title: 'مركز الأوف لاين',
            subtitle: 'متابعة المزامنة المحلية بدون عرض أكواد البطاقات.',
            icon: Icons.cloud_done_rounded,
            color: AppTheme.warning,
            onTap: () => Navigator.pushNamed(context, '/offline-center'),
          ),
        if (canManageDebtBook)
          _HomeServiceItem(
            title: 'دفتر الديون',
            subtitle: 'إدارة العملاء والمديونيات محليًا حتى أثناء انقطاع الإنترنت.',
            icon: Icons.menu_book_rounded,
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.pushNamed(context, '/debt-book'),
          ),
      ];
    }

    return [
      if (showOfflineSyncAction)
        _HomeServiceItem(
          title: _isSyncingOfflineWorkspace
              ? 'جاري مزامنة الأوف لاين'
              : 'مزامنة الأوف لاين',
          subtitle: _pendingOfflineCount > 0
              ? 'لديك $_pendingOfflineCount بطاقة معلقة للمزامنة، وسيتم تنزيل بطاقات أوف لاين جديدة أيضًا.'
              : 'تحديث مخزون الأوف لاين على الجهاز وتنزيل أي بطاقات جديدة.',
          icon: Icons.cloud_sync_rounded,
          color: AppTheme.primary,
          onTap: () => unawaited(_syncOfflineWorkspace()),
        ),
      if (canScanCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: _openScanScreen,
        ),
      if (canViewBalance)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.017'),
          subtitle: l.tr('screens_home_screen.018'),
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.primary,
          onTap: () => unawaited(_openOnlineOnlyRoute('/balance')),
        ),
      if (canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.019'),
          subtitle: l.tr('screens_home_screen.020'),
          icon: Icons.add_card_rounded,
          color: const Color(0xFF0B75B7),
          onTap: () => unawaited(_openOnlineOnlyRoute('/create-card')),
        ),
      if (canViewQuickTransfer && _canTransfer)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.021'),
          subtitle: l.tr('screens_home_screen.022'),
          icon: Icons.send_to_mobile_rounded,
          color: AppTheme.accent,
          onTap: () => unawaited(_openOnlineOnlyRoute('/quick-transfer')),
        ),
      if (canViewInventory && canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.023'),
          subtitle: l.tr('screens_home_screen.024'),
          icon: Icons.inventory_2_rounded,
          color: AppTheme.textSecondary,
          onTap: () => unawaited(_openOnlineOnlyRoute('/inventory')),
        ),
      if (canRequestCardPrinting)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.025'),
          subtitle: l.tr('screens_home_screen.026'),
          icon: Icons.print_rounded,
          color: AppTheme.secondary,
          onTap: () => unawaited(_openOnlineOnlyRoute('/card-print-requests')),
        ),
      if (canViewTransactions)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.027'),
          subtitle: l.tr('screens_home_screen.028'),
          icon: Icons.receipt_long_rounded,
          color: AppTheme.warning,
          onTap: () => unawaited(_openOnlineOnlyRoute('/transactions')),
        ),
      if (canManageDebtBook)
        _HomeServiceItem(
          title: 'دفتر الديون',
          subtitle: 'إدارة العملاء والمديونيات والسداد أون لاين وأوف لاين.',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF7C3AED),
          onTap: () => Navigator.pushNamed(context, '/debt-book'),
        ),
      if (canViewSecuritySettings)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.029'),
          subtitle: l.tr('screens_home_screen.030'),
          icon: Icons.security_rounded,
          color: AppTheme.secondary,
          onTap: () => unawaited(_openOnlineOnlyRoute('/security-settings')),
        ),
    ];
  }

  Widget _buildTopSection({
    required bool isMobile,
    required bool showBarcodeCard,
  }) {
    if (isMobile) {
      return Column(
        children: [
          _buildHeroCard(isMobile: true),
          if (showBarcodeCard) ...[
            const SizedBox(height: 16),
            _buildHomeBarcodeCard(isMobile: true),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: showBarcodeCard ? 3 : 1,
          child: _buildHeroCard(isMobile: false),
        ),
        if (showBarcodeCard) ...[
          const SizedBox(width: 18),
          Expanded(flex: 2, child: _buildHomeBarcodeCard(isMobile: false)),
        ],
      ],
    );
  }

  Widget _buildHeroCard({required bool isMobile}) {
    final l = context.loc;
    final username = _user?['username']?.toString() ?? '';
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final role =
        _user?['roleLabel']?.toString() ?? _user?['role']?.toString() ?? '';
    final displayName = fullName.isNotEmpty ? fullName : username;
    final serviceCount = _serviceItems(context).length;
    final heroChips = [
      _HeroChipData(
        icon: Icons.verified_user_rounded,
        label: _isVerifiedAccount
            ? l.tr('screens_home_screen.009')
            : l.tr('screens_home_screen.010'),
      ),
      if (role.isNotEmpty)
        _HeroChipData(icon: Icons.badge_rounded, label: role),
      _HeroChipData(
        icon: Icons.grid_view_rounded,
        label: l.tr(
          'screens_home_screen.034',
          params: {'count': serviceCount.toString()},
        ),
      ),
    ];

    return ShwakelCard(
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      gradient: const LinearGradient(
        colors: [Color(0xFF0C4A6E), Color(0xFF0F766E), Color(0xFF22C1C3)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      shadowLevel: ShwakelShadowLevel.premium,
      withBorder: false,
      borderRadius: BorderRadius.circular(34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الواجهة الرئيسية',
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayName.isEmpty
                          ? l.tr('screens_home_screen.006')
                          : l.tr(
                              'screens_home_screen.031',
                              params: {'name': displayName},
                            ),
                      style: AppTheme.h2.copyWith(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      role.isEmpty ? l.tr('screens_home_screen.007') : role,
                      style: AppTheme.bodyBold.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: isMobile ? 62 : 70,
                height: isMobile ? 62 : 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: const ShwakelLogo(size: 38, framed: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isMobile ? 18 : 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.tr('screens_home_screen.008'),
                        style: AppTheme.bodyBold.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l.tr('screens_home_screen.032'),
                        style: AppTheme.h1.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l.tr('screens_home_screen.033'),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: heroChips
                            .map(
                              (chip) => _buildHeroChip(
                                icon: chip.icon,
                                label: chip.label,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('screens_home_screen.008'),
                              style: AppTheme.bodyBold.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.tr('screens_home_screen.032'),
                              style: AppTheme.h1.copyWith(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.tr('screens_home_screen.033'),
                              style: AppTheme.bodyAction.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: heroChips
                              .map(
                                (chip) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildHeroChip(
                                    icon: chip.icon,
                                    label: chip.label,
                                    expanded: true,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool compact,
  }) {
    return ShwakelCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 18 : 22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: compact
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'خدمة',
                          style: AppTheme.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.h3.copyWith(color: color, fontSize: 17),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyAction.copyWith(
                          height: 1.4,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: color,
                    size: 24,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'خدمة',
                          style: AppTheme.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: AppTheme.h3.copyWith(color: color, fontSize: 19),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: AppTheme.bodyAction.copyWith(height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward_rounded, color: color, size: 26),
              ],
            ),
    );
  }

  Widget _buildHeroChip({
    required IconData icon,
    required String label,
    bool expanded = false,
  }) {
    return Container(
      width: expanded ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? actionLabel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.h1),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              actionLabel,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHomeBarcodeCard({required bool isMobile}) {
    final l = context.loc;
    return ShwakelCard(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      borderRadius: BorderRadius.circular(30),
      shadowLevel: ShwakelShadowLevel.medium,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppTheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('screens_home_screen.011'),
                            style: AppTheme.h2.copyWith(fontSize: 17),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.tr('screens_home_screen.035'),
                            style: AppTheme.bodyAction.copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShwakelButton(
                  label: l.tr('screens_home_screen.012'),
                  icon: Icons.camera_alt_rounded,
                  onPressed: _startHomeBarcodeScan,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('screens_home_screen.011'),
                            style: AppTheme.h2.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.tr('screens_home_screen.035'),
                            style: AppTheme.bodyAction.copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppTheme.primary,
                        size: 36,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ShwakelButton(
                  label: l.tr('screens_home_screen.012'),
                  icon: Icons.camera_alt_rounded,
                  onPressed: _startHomeBarcodeScan,
                ),
              ],
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _HeroChipData {
  const _HeroChipData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
