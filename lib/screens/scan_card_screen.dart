import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class ScanCardScreen extends StatefulWidget {
  const ScanCardScreen({
    super.key,
    this.initialBarcode,
    this.offlineMode = false,
  });

  final String? initialBarcode;
  final bool offlineMode;

  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> with RouteAware {
  final TextEditingController _bcC = TextEditingController();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();

  VirtualCard? _card;
  Map<String, dynamic>? _user;
  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _isSyncingOfflineCards = false;
  bool _isSyncingOfflineRedeems = false;
  bool _showDetails = false;
  bool _routeSubscribed = false;
  int _pendingOfflineCount = 0;
  double _pendingOfflineAmount = 0;
  int _rejectedOfflineCount = 0;
  List<Map<String, dynamic>> _rejectedOfflineItems = const [];
  Map<String, dynamic> _offlineSettings = const {};

  bool get _canOfflineScan => AppPermissions.fromUser(_user).canOfflineCardScan;
  bool get _canAccessScanScreen {
    final permissions = AppPermissions.fromUser(_user);
    return permissions.canOpenCardTools || permissions.canReviewCards;
  }

  String _t(String ar, String en) => context.loc.text(ar, en);

  @override
  void initState() {
    super.initState();
    OfflineSessionService.setOfflineMode(widget.offlineMode);
    _load();
    if (widget.initialBarcode?.isNotEmpty == true) {
      _bcC.text = widget.initialBarcode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
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
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _bcC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (mounted) {
      setState(() => _user = user);
    }
    if (!widget.offlineMode) {
      await _syncOfflineCards();
      await _syncOfflineRedeems();
    }
    await _loadOfflineSummary();
  }

  Future<void> _syncOfflineCards() async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      return;
    }

    setState(() => _isSyncingOfflineCards = true);
    try {
      final payload = await _api.getOfflineCardCache();
      final cards = List<VirtualCard>.from(
        payload['cards'] as List? ?? const [],
      );
      final settings = Map<String, dynamic>.from(
        payload['settings'] as Map? ?? const {},
      );
      await _offlineCardService.cacheCards(
        userId: user['id'].toString(),
        cards: cards,
        settings: settings,
      );
    } catch (_) {
      // Keep cached cards locally when there is no connection.
    } finally {
      if (mounted) {
        setState(() => _isSyncingOfflineCards = false);
      }
    }
  }

  Future<void> _loadOfflineSummary() async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    final userId = user['id'].toString();
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      if (!mounted) return;
      setState(() {
        _pendingOfflineCount = 0;
        _pendingOfflineAmount = 0;
        _rejectedOfflineCount = 0;
        _rejectedOfflineItems = const [];
        _offlineSettings = const {};
      });
      return;
    }

    final summary = await _offlineCardService.pendingRedeemSummary(userId);
    final rejected = await _offlineCardService.getRejectedRedeems(userId);
    final settings = await _offlineCardService.offlineSettings(userId);
    if (!mounted) return;
    setState(() {
      _pendingOfflineCount = (summary['count'] as num?)?.toInt() ?? 0;
      _pendingOfflineAmount = (summary['amount'] as num?)?.toDouble() ?? 0;
      _rejectedOfflineCount = (summary['rejectedCount'] as num?)?.toInt() ?? 0;
      _rejectedOfflineItems = rejected;
      _offlineSettings = settings;
    });
  }

  Future<void> _syncOfflineRedeems() async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      return;
    }
    final queue = await _offlineCardService.getRedeemQueue(
      user['id'].toString(),
    );
    if (queue.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() => _isSyncingOfflineRedeems = true);
    }
    try {
      final result = await _api.syncOfflineCardRedeems(items: queue);
      final resultItems = List<Map<String, dynamic>>.from(
        (result['results'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final rejectedBarcodes = <String>{
        for (final item in resultItems)
          if (item['ok'] != true) (item['barcode'] ?? '').toString(),
      }..remove('');
      final rejectedQueue = queue
          .where(
            (item) => rejectedBarcodes.contains(item['barcode']?.toString()),
          )
          .toList();
      await _offlineCardService.replaceRedeemQueue(
        user['id'].toString(),
        rejectedQueue,
      );
      await _offlineCardService.replaceRejectedRedeems(
        user['id'].toString(),
        resultItems.where((item) => item['ok'] != true).toList(),
      );
      final acceptedCount = resultItems
          .where((item) => item['ok'] == true)
          .length;
      final acceptedBarcodes = <String>{
        for (final item in resultItems)
          if (item['ok'] == true) (item['barcode'] ?? '').toString(),
      }..remove('');
      await _offlineCardService.removeCardsByBarcode(
        userId: user['id'].toString(),
        barcodes: acceptedBarcodes,
      );
      if (acceptedCount > 0 || rejectedBarcodes.isNotEmpty) {
        await LocalNotificationService.showBalanceChange(
          title: _t('نتيجة مزامنة البطاقات', 'Card sync result'),
          body:
              _t(
                'تم اعتماد $acceptedCount بطاقة، وبقيت ${rejectedBarcodes.length} بطاقة للمراجعة.',
                '$acceptedCount cards approved, ${rejectedBarcodes.length} still need review.',
              ),
          isCredit: rejectedBarcodes.isEmpty,
        );
      }
      if (!mounted) {
        return;
      }
      final updatedBalance = (result['balance'] as num?)?.toDouble();
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      await _loadOfflineSummary();
    } catch (_) {
      // Keep queue for the next attempt when connection is available.
    } finally {
      if (mounted) {
        setState(() => _isSyncingOfflineRedeems = false);
      }
    }
  }

  Future<void> _refreshOfflineState() async {
    await _syncOfflineCards();
    await _syncOfflineRedeems();
    await _loadOfflineSummary();
  }

  Future<void> _search() async {
    final l = context.loc;
    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isSearching = true);
    if (widget.offlineMode) {
      await _searchOffline(barcode, l);
      return;
    }
    try {
      final result = await _api.getCardByBarcode(barcode);
      if (!mounted) return;
      setState(() {
        _card = result;
        _showDetails = false;
        _isSearching = false;
      });
      if (result == null) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_scan_card_screen.039'),
          message: l.tr('screens_scan_card_screen.040'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.039'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _searchOffline(String barcode, AppLocalizer l) async {
    final user = _user;
    final permissions = AppPermissions.fromUser(user);
    if (!(permissions.canOfflineCardScan &&
        user != null &&
        user['id'] != null)) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.039'),
        message: 'لا تتوفر صلاحية الفحص الأوف لاين على هذا الجهاز.',
      );
      return;
    }

    final userId = user['id'].toString();
    final cached = await _offlineCardService.findCachedCard(userId, barcode);
    if (!mounted) return;
    if (cached != null) {
      await _offlineCardService.clearUnknownOfflineScans(userId);
      if (!mounted) return;
      setState(() {
        _card = cached;
        _showDetails = false;
        _isSearching = false;
      });
      return;
    }

    final blocked = await _offlineCardService.recordUnknownOfflineScan(
      userId,
      barcode,
    );
    if (!mounted) return;
    setState(() => _isSearching = false);
    AppAlertService.showError(
      context,
      title: l.tr('screens_scan_card_screen.039'),
      message: blocked
          ? 'تم إيقاف الفحص مؤقتًا بسبب محاولات كثيرة لبطاقات غير موجودة في ذاكرة الأوف لاين.'
          : l.tr('screens_scan_card_screen.040'),
    );
  }

  Future<void> _openScannerDialog() async {
    final l = context.loc;
    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BarcodeScannerDialog(
        title: l.tr('screens_scan_card_screen.001'),
        description: l.tr('screens_scan_card_screen.041'),
        height: 360,
        showFrame: true,
        backgroundColor: Colors.transparent,
      ),
    );
    if (!mounted || scannedValue == null || scannedValue.isEmpty) {
      return;
    }

    setState(() {
      _bcC.text = scannedValue;
    });
    await _search();
    if (!mounted) return;
  }

  Future<void> _redeem() async {
    final l = context.loc;
    if (_card == null) return;

    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canRedeemCards) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.043'),
        message: l.tr('screens_scan_card_screen.022'),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    if (widget.offlineMode) {
      await _redeemOffline(l);
      return;
    }

    Map<String, dynamic>? location;
    try {
      try {
        location = await TransactionLocationService.captureCurrentLocation();
      } catch (_) {
        location = null;
      }
      final response = await _api.redeemCard(
        cardId: _card!.id,
        customerName:
            _user?['fullName'] ??
            _user?['username'] ??
            l.tr('screens_scan_card_screen.060'),
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_scan_card_screen.044'),
        message: l.tr('screens_scan_card_screen.045'),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.046'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _redeemOffline(AppLocalizer l) async {
    final user = _user;
    if (user == null || user['id'] == null || _card == null) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      return;
    }

    final userId = user['id'].toString();
    final limitMessage = await _offlineCardService.validateCanQueueRedeem(
      userId: userId,
      cardValue: _card!.value,
    );
    if (!mounted) return;
    if (limitMessage != null) {
      setState(() => _isSubmitting = false);
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.046'),
        message: limitMessage,
      );
      return;
    }

    final customerName =
        _user?['fullName'] ??
        _user?['username'] ??
        l.tr('screens_scan_card_screen.060');
    await _offlineCardService.enqueueRedeem(userId, {
      'barcode': _card!.barcode,
      'cardId': _card!.id,
      'value': _card!.value,
      'sourceOwnerId': _card!.ownerId,
      'sourceOwnerUsername': _card!.ownerUsername,
      'sourceIssuedById': _card!.issuedById,
      'sourceIssuedByUsername': _card!.issuedByUsername,
      'customerName': customerName,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    await _offlineCardService.markCardUsed(
      userId: userId,
      barcode: _card!.barcode,
      customerName: customerName,
      usedBy: _user?['username']?.toString(),
    );
    setState(() {
      _card = _card!.copyWith(
        status: CardStatus.used,
        usedAt: DateTime.now(),
        usedBy: _user?['username']?.toString(),
      );
    });
    await _loadOfflineSummary();
    if (!mounted) return;
    AppAlertService.showSuccess(
      context,
      title: l.tr('screens_scan_card_screen.063'),
      message: l.tr('screens_scan_card_screen.064'),
    );
  }

  Future<void> _resell() async {
    final l = context.loc;
    if (_card == null) return;

    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canResellCards) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.043'),
        message: l.tr('screens_scan_card_screen.047'),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_scan_card_screen.048')),
        content: Text(l.tr('screens_scan_card_screen.049')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('screens_scan_card_screen.050')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.autorenew_rounded),
            label: Text(l.tr('screens_scan_card_screen.011')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _api.resellCard(
        cardId: _card!.id,
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_scan_card_screen.051'),
        message: l.tr('screens_scan_card_screen.052'),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.046'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _statusLabel(VirtualCard card) {
    final l = context.loc;
    switch (card.status) {
      case CardStatus.used:
        return l.tr('screens_scan_card_screen.053');
      case CardStatus.archived:
        return l.tr('screens_scan_card_screen.054');
      case CardStatus.unused:
        return l.tr('screens_scan_card_screen.055');
    }
  }

  String _cardTypeLabel(VirtualCard card) {
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.066')
        : l.tr('screens_scan_card_screen.067');
  }

  String _visibilityLabel(VirtualCard card) {
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.058')
        : l.tr('screens_scan_card_screen.059');
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (!_canAccessScanScreen && _user != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: Text(l.tr('screens_scan_card_screen.001'))),
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
                  _t(
                    'لا تملك صلاحية استخدام شاشة البطاقات',
                    'You do not have access to the card screen',
                  ),
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
        title: Text(l.tr('screens_scan_card_screen.001')),
        actions: [
          IconButton(
            tooltip: _t('مساعدة', 'Help'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: AppTheme.pagePadding(context, top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildScannerPanel(),
              if (_canOfflineScan) ...[
                const SizedBox(height: 18),
                _buildOfflinePanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('طريقة الاستخدام', 'How to use')),
        content: Text(
          widget.offlineMode
              ? _t(
                  'أدخل الكود أو امسحه، وسيتم الفحص من البيانات المحلية فقط.',
                  'Enter or scan the code. The check will use local data only.',
                )
              : _t(
                  'أدخل الكود أو امسحه لفحص البطاقة مباشرة. تفاصيل إضافية تظهر فقط عند الحاجة.',
                  'Enter or scan the code to check the card. Extra details appear only when needed.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_t('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerPanel() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_scan_card_screen.002'),
                      style: AppTheme.h3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.tr('screens_scan_card_screen.003'),
                      style: AppTheme.bodyAction,
                    ),
                  ],
                ),
              ),
            ],
          ),
          TextField(
            controller: _bcC,
            decoration: InputDecoration(
              labelText: l.tr('screens_scan_card_screen.004'),
              prefixIcon: const Icon(Icons.qr_code_rounded),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            onSubmitted: (_) => _search(),
          ),
          if (widget.offlineMode) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(
                        'وضع الأوف لاين مفعل. سيتم الفحص من البيانات المحلية فقط.',
                        'Offline mode is active. The check will use local data only.',
                      ),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;
              if (isCompact) {
                return Column(
                  children: [
                    ShwakelButton(
                      label: l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                    if (_canOfflineScan) ...[
                      const SizedBox(height: 12),
                      ShwakelButton(
                        label: _t('مركز الأوف لاين', 'Offline center'),
                        icon: Icons.cloud_done_rounded,
                        isSecondary: true,
                        onPressed: () =>
                            Navigator.pushNamed(context, '/offline-center'),
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ),
                  if (_canOfflineScan) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ShwakelButton(
                        label: _t('مركز الأوف لاين', 'Offline center'),
                        icon: Icons.cloud_done_rounded,
                        isSecondary: true,
                        onPressed: () =>
                            Navigator.pushNamed(context, '/offline-center'),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildInlineResultSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineResultSection() {
    final l = context.loc;
    if (_card == null) {
      return Container(
        key: const ValueKey('scan-empty'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_t('نتيجة الفحص', 'Scan result'), style: AppTheme.h3),
          ],
        ),
      );
    }

    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards = appPermissions.canRedeemCards;
    final canResellCards = appPermissions.canResellCards;

    return Container(
      key: ValueKey(card.barcode),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
                  color: accent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUsed
                          ? _t('البطاقة مستخدمة', 'Card used')
                          : _t('البطاقة صالحة', 'Card valid'),
                      style: AppTheme.h3.copyWith(color: accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card.barcode,
                      style: AppTheme.bodyBold.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(
                icon: Icons.payments_rounded,
                label: CurrencyFormatter.ils(card.value),
              ),
              _infoChip(
                icon: Icons.category_rounded,
                label: _cardTypeLabel(card),
              ),
              _infoChip(
                icon: Icons.public_rounded,
                label: _visibilityLabel(card),
              ),
              _infoChip(
                icon: isUsed
                    ? Icons.cancel_schedule_send_rounded
                    : Icons.verified_rounded,
                label: _statusLabel(card),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!isUsed && canRedeemCards)
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.021'),
              icon: Icons.download_done_rounded,
              onPressed: _redeem,
              isLoading: _isSubmitting,
            )
          else if (isUsed && canResellCards)
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.011'),
              icon: Icons.autorenew_rounded,
              onPressed: _resell,
              isLoading: _isSubmitting,
            )
          else
            Text(
              isUsed
                  ? _t('هذه البطاقة مستعملة بالفعل.', 'This card is already used.')
                  : _t(
                      'لا تملك صلاحية تنفيذ إجراء مباشر على هذه البطاقة.',
                      'You do not have permission to run a direct action on this card.',
                    ),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOfflinePanel() {
    if (!_canOfflineScan) {
      return const SizedBox.shrink();
    }

    final maxPendingCount =
        (_offlineSettings['maxPendingCount'] as num?)?.toInt() ?? 50;
    final maxPendingAmount =
        (_offlineSettings['maxPendingAmount'] as num?)?.toDouble() ?? 500;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.cloud_sync_rounded,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('حالة الأوف لاين', 'Offline status'), style: AppTheme.h3),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: _t('تحديث الآن', 'Refresh now'),
                onPressed: _isSyncingOfflineCards || _isSyncingOfflineRedeems
                    ? null
                    : _refreshOfflineState,
                icon: (_isSyncingOfflineCards || _isSyncingOfflineRedeems)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statTile(
                label: _t('عمليات معلقة', 'Pending items'),
                value: '$_pendingOfflineCount / $maxPendingCount',
                hint: CurrencyFormatter.ils(_pendingOfflineAmount),
                color: AppTheme.primary,
                icon: Icons.layers_rounded,
              ),
              _statTile(
                label: _t('حد الأوف لاين', 'Offline limit'),
                value: CurrencyFormatter.ils(maxPendingAmount),
                hint: _t('الحد قبل طلب المزامنة', 'Threshold before sync is needed'),
                color: AppTheme.warning,
                icon: Icons.account_balance_wallet_rounded,
              ),
              _statTile(
                label: _t('مرفوض للمراجعة', 'Rejected for review'),
                value: '$_rejectedOfflineCount',
                hint: _rejectedOfflineCount == 0
                    ? _t('لا توجد عناصر مرفوضة', 'No rejected items')
                    : _t(
                        'تحتاج مراجعة بعد المزامنة',
                        'Needs review after sync',
                      ),
                color: AppTheme.error,
                icon: Icons.rule_folder_rounded,
              ),
            ],
          ),
          if (_rejectedOfflineItems.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              _t('آخر العمليات المرفوضة', 'Latest rejected items'),
              style: AppTheme.bodyBold,
            ),
            const SizedBox(height: 10),
            ..._rejectedOfflineItems
                .take(3)
                .map((item) => _buildRejectedItem(item)),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildResultPanel() {
    return _card == null ? _buildEmptyPreview() : _buildDetails();
  }

  Widget _buildDetails() {
    final l = context.loc;
    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards = appPermissions.canRedeemCards;
    final canResellCards = appPermissions.canResellCards;
    final canReviewCards = appPermissions.canReviewCards;
    final canViewCardDetails =
        !widget.offlineMode && (canReviewCards || canResellCards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(24),
          color: accent.withValues(alpha: 0.08),
          borderColor: accent.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(30),
          shadowLevel: ShwakelShadowLevel.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
                      color: accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_scan_card_screen.014'),
                          style: AppTheme.caption.copyWith(color: accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isUsed
                              ? l.tr('screens_scan_card_screen.015')
                              : l.tr('screens_scan_card_screen.016'),
                          style: AppTheme.h2.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                  if (isUsed && canResellCards)
                    IconButton.filledTonal(
                      tooltip: context.loc.tr('screens_scan_card_screen.011'),
                      onPressed: _isSubmitting ? null : _resell,
                      icon: const Icon(Icons.autorenew_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _infoChip(icon: Icons.qr_code_2_rounded, label: card.barcode),
                  _infoChip(
                    icon: Icons.category_rounded,
                    label: _cardTypeLabel(card),
                  ),
                  _infoChip(
                    icon: Icons.public_rounded,
                    label: _visibilityLabel(card),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUsed
                      ? l.tr('screens_scan_card_screen.017')
                      : l.tr('screens_scan_card_screen.018'),
                  style: AppTheme.bodyBold.copyWith(color: accent),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _resultBadge(
                    l.tr('screens_scan_card_screen.019'),
                    _statusLabel(card),
                    accent,
                    icon: isUsed
                        ? Icons.cancel_schedule_send_rounded
                        : Icons.verified_rounded,
                  ),
                  _resultBadge(
                    l.tr('screens_scan_card_screen.020'),
                    CurrencyFormatter.ils(card.value),
                    AppTheme.primary,
                    icon: Icons.payments_rounded,
                  ),
                  _resultBadge(
                    l.tr('screens_scan_card_screen.027'),
                    CurrencyFormatter.ils(card.issueCost),
                    AppTheme.warning,
                    icon: Icons.sell_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildActionPanel(
          isUsed: isUsed,
          canRedeemCards: canRedeemCards,
          canResellCards: canResellCards,
          canViewCardDetails: canViewCardDetails,
        ),
        if (_showDetails && canViewCardDetails) ...[
          const SizedBox(height: 16),
          ShwakelCard(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(28),
            shadowLevel: ShwakelShadowLevel.medium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShwakelLogo(size: 40, framed: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.loc.tr('screens_scan_card_screen.007'),
                        style: AppTheme.h2,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.ils(card.value),
                      style: AppTheme.h2.copyWith(color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 620;
                    final items = [
                      _detailTile(
                        l.tr('screens_scan_card_screen.023'),
                        card.barcode,
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.019'),
                        _statusLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.024'),
                        _cardTypeLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.025'),
                        _visibilityLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.026'),
                        CurrencyFormatter.ils(card.value),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.027'),
                        CurrencyFormatter.ils(card.issueCost),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.028'),
                        card.ownerUsername ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.029'),
                        card.issuedByUsername ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.030'),
                        card.usedBy ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.031'),
                        card.customerName ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.032'),
                        _formatDate(card.createdAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.033'),
                        _formatDate(card.usedAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.034'),
                        _formatDate(card.lastResoldAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.035'),
                        '${card.useCount}',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.036'),
                        '${card.resaleCount}',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.037'),
                        CurrencyFormatter.ils(card.totalRedeemedValue),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.038'),
                        card.allowedUsernames.isEmpty
                            ? '-'
                            : card.allowedUsernames.join('، '),
                        spanTwo: true,
                      ),
                    ];

                    if (isCompact) {
                      return Column(
                        children: items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: item,
                              ),
                            )
                            .toList(),
                      );
                    }

                    return Wrap(spacing: 12, runSpacing: 12, children: items);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionPanel({
    required bool isUsed,
    required bool canRedeemCards,
    required bool canResellCards,
    required bool canViewCardDetails,
  }) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text(_t('الإجراءات', 'Actions'), style: AppTheme.h3),
          const SizedBox(height: 16),
          if (!isUsed && canRedeemCards) ...[
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.021'),
              icon: Icons.download_done_rounded,
              onPressed: _redeem,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 12),
          ],
          if (isUsed && canResellCards) ...[
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.011'),
              icon: Icons.autorenew_rounded,
              onPressed: _resell,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 12),
          ],
          if (!isUsed && !canRedeemCards) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.18),
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: AppTheme.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.tr('screens_scan_card_screen.022'),
                      style: AppTheme.bodyText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (canViewCardDetails)
            OutlinedButton.icon(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(
                _showDetails
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              label: Text(
                _showDetails
                    ? context.loc.tr('screens_scan_card_screen.009')
                    : context.loc.tr('screens_scan_card_screen.010'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultBadge(
    String label,
    String value,
    Color color, {
    required IconData icon,
  }) {
    return SizedBox(
      width: 182,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailTile(String label, String value, {bool spanTwo = false}) {
    return SizedBox(
      width: spanTwo ? 420 : 204,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.bodyBold),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.credit_card_off_rounded,
              size: 52,
              color: AppTheme.textTertiary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 18),
          Text(l.tr('screens_scan_card_screen.007'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_scan_card_screen.008'),
            style: AppTheme.bodyAction,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(
                icon: Icons.qr_code_scanner_rounded,
                label: _t(
                  'ابدأ بمسح الكود أو إدخال الرقم يدويًا',
                  'Start by scanning the code or entering it manually',
                ),
              ),
              _infoChip(
                icon: Icons.receipt_long_rounded,
                label: _t(
                  'ستظهر هنا نتيجة الفحص فقط عند توفرها',
                  'The result will appear here when available',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required String hint,
    required Color color,
    required IconData icon,
  }) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(hint, style: AppTheme.caption),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedItem(Map<String, dynamic> item) {
    final barcode = item['barcode']?.toString().trim();
    final message = item['message']?.toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppTheme.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barcode?.isNotEmpty == true
                      ? barcode!
                      : _t('بطاقة غير معروفة', 'Unknown card'),
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 4),
                Text(
                  message?.isNotEmpty == true
                      ? message!
                      : _t(
                          'تم رفض البطاقة بعد المزامنة وتحتاج مراجعة.',
                          'This card was rejected after sync and needs review.',
                        ),
                  style: AppTheme.bodyText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip({required IconData icon, required String label}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


