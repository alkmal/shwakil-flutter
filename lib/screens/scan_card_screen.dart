import 'dart:async';

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class ScanCardScreen extends StatefulWidget {
  const ScanCardScreen({
    super.key,
    this.initialBarcode,
    this.offlineMode = false,
    this.autoOpenScanner = false,
    this.autoReadNfc = false,
    this.openTemporaryTransferCreator = false,
  });

  final String? initialBarcode;
  final bool offlineMode;
  final bool autoOpenScanner;
  final bool autoReadNfc;
  final bool openTemporaryTransferCreator;

  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> with RouteAware {
  static const String _offlineNfcQueueKey =
      'prepaid_multipay_nfc_merchant_queue_v1';

  final TextEditingController _bcC = TextEditingController();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final OfflineTransferCodeService _offlineTransferCodeService =
      OfflineTransferCodeService();
  final PrepaidMultipayNfcService _nfc = const PrepaidMultipayNfcService();

  VirtualCard? _card;
  Map<String, dynamic>? _user;
  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _isReadingNfc = false;
  bool _routeSubscribed = false;
  bool _autoScannerOpened = false;
  bool _autoNfcReadStarted = false;
  bool _initialBarcodeHandled = false;
  int _availableOfflineTransferSlots = 0;
  int _availableOfflineCardCount = 0;
  int _offlineSyncIntervalMinutes = 60;
  DateTime? _offlineLastSyncAt;
  bool _offlineAccessExpired = false;
  bool _clearedExpiredOfflineCards = false;
  bool _isSyncingOfflineCards = false;
  bool _showUserBalance = true;
  bool _isPreparingScreen = true;
  bool _autoRedeemOnScan = false;
  bool _autoRedeemOnScanForced = false;
  bool _isUpdatingAutoRedeemOnScan = false;
  String? _lastAutoRedeemedBarcode;

  bool get _canAccessScanScreen {
    final permissions = AppPermissions.fromUser(_user);
    return permissions.canOpenCardTools || permissions.canReviewCards;
  }

  bool get _canRevealSensitiveCardData {
    final permissions = AppPermissions.fromUser(_user);
    return !widget.offlineMode &&
        (permissions.canIssueCards ||
            permissions.canManageUsers ||
            _user?['id']?.toString() == '1');
  }

  Map<String, dynamic> get _subUserOperationalLimits =>
      Map<String, dynamic>.from(
        _user?['subUserOperationalLimits'] as Map? ?? const {},
      );

  bool get _isSubUser => _user?['isSubUser'] == true;

  double? _subUserLimit(String key) =>
      (_subUserOperationalLimits[key] as num?)?.toDouble();

  String _t(String key, [Map<String, String>? params]) =>
      context.loc.tr(key, params: params);

  bool get _isDeviceOffline => !ConnectivityService.instance.isOnline.value;

  bool get _isOfflineUseBlocked => widget.offlineMode && _offlineAccessExpired;

  bool get _hasOfflineScanPermission =>
      AppPermissions.fromUser(_user).canOfflineCardScan;

  @override
  void initState() {
    super.initState();
    OfflineSessionService.setOfflineMode(widget.offlineMode);
    ConnectivityService.instance.isOnline.addListener(
      _handleConnectivityChanged,
    );
    _load();
    if (widget.initialBarcode?.isNotEmpty == true) {
      _bcC.text = widget.initialBarcode!;
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
    ConnectivityService.instance.isOnline.removeListener(
      _handleConnectivityChanged,
    );
    _bcC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = await _auth.currentUser();
      final showUserBalanceFuture = _loadBalanceVisibilityPreference(user);
      if (mounted) {
        setState(() {
          _user = user;
          _syncAutoRedeemState(user);
        });
      }
      if (widget.offlineMode &&
          !widget.autoReadNfc &&
          !await _ensureOfflinePermissionAllowed(redirectIfDenied: true)) {
        return;
      }
      final showUserBalance = await showUserBalanceFuture;
      if (mounted) {
        setState(() {
          _showUserBalance = showUserBalance;
        });
      }
      await Future.wait<void>([
        _refreshOfflineCardStatus(),
        _loadOfflineTransferSlotCount(),
        _ensureOfflineTemporaryTransferSlots(),
        _syncOfflineNfcPayments(),
      ]);
      _maybeOpenScannerAutomatically();
      if (widget.openTemporaryTransferCreator && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showTemporaryTransferCreator();
          }
        });
      }
      _maybeReadNfcAutomatically();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableOfflineTransferSlots = 0;
        _availableOfflineCardCount = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _isPreparingScreen = false);
        _maybeSearchInitialBarcode();
      }
    }
  }

  void _maybeSearchInitialBarcode() {
    if (!mounted ||
        _initialBarcodeHandled ||
        widget.initialBarcode?.trim().isNotEmpty != true) {
      return;
    }
    _initialBarcodeHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_search());
      }
    });
  }

  void _syncAutoRedeemState(Map<String, dynamic>? user) {
    final role = user?['role']?.toString() ?? '';
    final staffCanUsePublicCards =
        role == 'admin' || role == 'support' || role == 'finance';
    final unverifiedForced =
        user?['cardAutoRedeemOnScanUnverifiedForced'] == true ||
        (!staffCanUsePublicCards &&
            (user?['transferVerificationStatus']?.toString() ?? 'unverified') !=
                'approved');
    _autoRedeemOnScanForced =
        user?['cardAutoRedeemOnScanForced'] == true ||
        user?['cardAutoRedeemOnScanGlobalForced'] == true ||
        unverifiedForced;
    _autoRedeemOnScan =
        _autoRedeemOnScanForced || user?['cardAutoRedeemOnScanEnabled'] == true;
  }

  String _balanceVisibilityKey(Map<String, dynamic>? user) {
    final userId = user?['id']?.toString().trim();
    if (userId == null || userId.isEmpty) {
      return 'scan_card_show_balance';
    }
    return 'scan_card_show_balance_$userId';
  }

  Future<bool> _loadBalanceVisibilityPreference(
    Map<String, dynamic>? user,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_balanceVisibilityKey(user)) ?? true;
  }

  Future<void> _toggleBalanceVisibility() async {
    final nextValue = !_showUserBalance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_balanceVisibilityKey(_user), nextValue);
    if (!mounted) {
      return;
    }
    setState(() => _showUserBalance = nextValue);
  }

  Future<void> _toggleAutoRedeemOnScan() async {
    if (widget.offlineMode || _isUpdatingAutoRedeemOnScan) {
      return;
    }

    final nextValue = !_autoRedeemOnScan;
    if (_autoRedeemOnScanForced && !nextValue) {
      final unverifiedForced =
          _user?['cardAutoRedeemOnScanUnverifiedForced'] == true ||
          (![
                'admin',
                'support',
                'finance',
              ].contains(_user?['role']?.toString() ?? '') &&
              (_user?['transferVerificationStatus']?.toString() ??
                      'unverified') !=
                  'approved');
      await AppAlertService.showInfo(
        context,
        title: 'لا يمكن تعطيل السحب التلقائي',
        message: unverifiedForced
            ? 'لا يمكن تعطيل هذه الخاصية. تعطيل السحب التلقائي متوفر للمستخدمين الموثقين حساباتهم.'
            : 'السحب التلقائي مفعل من الإدارة ولا يمكن تعطيله إلا بعد مراجعة الإدارة.',
      );
      return;
    }

    if (nextValue) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تفعيل السحب التلقائي'),
          content: const Text(
            'بعد التفعيل سيتم استرداد أي بطاقة مباشرة بمجرد قراءتها، وستتحول إلى مستخدمة بدون خطوة تأكيد إضافية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('تأكيد بالبصمة'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      final canUseBiometrics = await LocalSecurityService.canUseBiometrics();
      if (!canUseBiometrics) {
        if (!mounted) return;
        await AppAlertService.showError(
          context,
          title: 'البصمة غير متاحة',
          message: 'يجب تفعيل البصمة على الجهاز قبل استخدام السحب التلقائي.',
        );
        return;
      }

      final authenticated =
          await LocalSecurityService.authenticateWithBiometrics();
      if (!authenticated) {
        if (!mounted) return;
        await AppAlertService.showError(
          context,
          title: 'لم يتم التفعيل',
          message: 'لم يتم تأكيد البصمة، وبقي السحب اليدوي مفعلاً.',
        );
        return;
      }
    }

    setState(() => _isUpdatingAutoRedeemOnScan = true);
    try {
      final response = await _api.updateCardAutoRedeemOnScanPreference(
        enabled: nextValue,
      );
      final rawUser = response['user'];
      final fallbackUser = rawUser is Map ? null : await _auth.currentUser();
      final updatedUser = rawUser is Map
          ? Map<String, dynamic>.from(rawUser)
          : Map<String, dynamic>.from(fallbackUser ?? const {});
      if (!mounted) return;
      setState(() {
        _user = updatedUser.isEmpty ? _user : updatedUser;
        _syncAutoRedeemState(_user);
      });
      AppAlertService.showSnack(
        context,
        message: nextValue
            ? 'تم تفعيل السحب التلقائي عند الفحص.'
            : 'تم تعطيل السحب التلقائي عند الفحص.',
        type: AppAlertType.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'تعذر تحديث السحب التلقائي',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAutoRedeemOnScan = false);
      }
    }
  }

  void _maybeOpenScannerAutomatically() {
    if (!mounted ||
        _autoScannerOpened ||
        !widget.autoOpenScanner ||
        widget.initialBarcode?.isNotEmpty == true) {
      return;
    }
    _autoScannerOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_openScannerDialog());
      }
    });
  }

  void _maybeReadNfcAutomatically() {
    if (!mounted ||
        _autoNfcReadStarted ||
        !widget.autoReadNfc ||
        widget.offlineMode ||
        widget.initialBarcode?.isNotEmpty == true) {
      return;
    }
    _autoNfcReadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_readNfcFromUnifiedScanner());
      }
    });
  }

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    final isOnline = ConnectivityService.instance.isOnline.value;
    setState(() {
      if (!isOnline) {
        _lastAutoRedeemedBarcode = null;
      }
    });
    unawaited(_refreshOfflineCardStatus());
    if (isOnline) {
      unawaited(_ensureOfflineTemporaryTransferSlots());
      unawaited(_syncOfflineCardsForCurrentUser());
      unawaited(_syncOfflineNfcPayments());
    } else {
      unawaited(_loadOfflineTransferSlotCount());
    }
  }

  Future<bool> _ensureOfflinePermissionAllowed({
    bool redirectIfDenied = false,
  }) async {
    if (!widget.offlineMode || _hasOfflineScanPermission) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    await AppAlertService.showError(
      context,
      title: 'وضع الأوفلاين غير متاح',
      message:
          'لا تملك صلاحية العمل بدون اتصال على هذا الحساب. يمكنك المتابعة فقط في وضع الأونلاين أو مراجعة الإدارة لتفعيل الصلاحية.',
    );

    if (!mounted || !redirectIfDenied) {
      return false;
    }

    _clearTransientScanState(clearBarcode: true);
    OfflineSessionService.setOfflineMode(false);
    Navigator.pushReplacementNamed(
      context,
      _isDeviceOffline ? '/home' : '/scan-card',
    );
    return false;
  }

  void _clearTransientScanState({bool clearBarcode = false}) {
    if (clearBarcode) {
      _bcC.clear();
    }
    setState(() {
      _card = null;
      _isSearching = false;
      _isSubmitting = false;
      _lastAutoRedeemedBarcode = null;
    });
  }

  Future<void> _loadOfflineTransferSlotCount() async {
    final userId = _user?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        setState(() => _availableOfflineTransferSlots = 0);
      }
      return;
    }
    final count = await _offlineTransferCodeService.countAvailableSlots(userId);
    if (!mounted) {
      return;
    }
    setState(() => _availableOfflineTransferSlots = count);
  }

  Future<void> _refreshOfflineCardStatus() async {
    final userId = _user?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        setState(() {
          _availableOfflineCardCount = 0;
          _offlineAccessExpired = false;
          _offlineLastSyncAt = null;
        });
      }
      return;
    }

    final snapshot = await _resolveOfflineStatusSnapshot(userId);

    if (!mounted) {
      return;
    }
    setState(() {
      _availableOfflineCardCount = snapshot.availableCount;
      _offlineSyncIntervalMinutes = snapshot.intervalMinutes;
      _offlineLastSyncAt = snapshot.lastSyncAt;
      _offlineAccessExpired = snapshot.expired;
    });
  }

  Future<_OfflineStatusSnapshot> _resolveOfflineStatusSnapshot(
    String userId,
  ) async {
    var overview = await _offlineCardService.offlineOverview(userId);
    var settings = Map<String, dynamic>.from(
      overview['settings'] as Map? ?? const {},
    );
    final interval =
        (((settings['syncIntervalMinutes'] as num?)?.toInt() ?? 60).clamp(
          5,
          1440,
        )).toInt();
    final lastSync = DateTime.tryParse(
      settings['lastSyncAt']?.toString() ?? '',
    )?.toLocal();
    final expired =
        widget.offlineMode &&
        (lastSync == null ||
            DateTime.now().difference(lastSync).inMinutes >= interval);

    if (expired && !_clearedExpiredOfflineCards) {
      await _offlineCardService.clearCachedCards(userId);
      _clearedExpiredOfflineCards = true;
      overview = await _offlineCardService.offlineOverview(userId);
      settings = Map<String, dynamic>.from(
        overview['settings'] as Map? ?? const {},
      );
    }

    return _OfflineStatusSnapshot(
      availableCount: (overview['availableCount'] as num?)?.toInt() ?? 0,
      intervalMinutes:
          (((settings['syncIntervalMinutes'] as num?)?.toInt() ?? interval)
                  .clamp(5, 1440))
              .toInt(),
      lastSyncAt: DateTime.tryParse(
        settings['lastSyncAt']?.toString() ?? '',
      )?.toLocal(),
      expired: expired,
    );
  }

  Future<bool> _ensureOfflineAccessReady() async {
    await _refreshOfflineCardStatus();
    if (!_isOfflineUseBlocked) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    await AppAlertService.showError(
      context,
      title: _t('screens_scan_card_screen.118'),
      message: _t('screens_scan_card_screen.119', {
        'minutes': _offlineSyncIntervalMinutes.toString(),
      }),
    );
    return false;
  }

  Future<void> _syncOfflineCardsForCurrentUser() async {
    if (_isSyncingOfflineCards || _isDeviceOffline) {
      return;
    }
    final user = _user ?? await _auth.currentUser();
    final userId = user?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      return;
    }
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      return;
    }

    _isSyncingOfflineCards = true;
    try {
      final queuedBeforeSync = await _offlineCardService.getRedeemQueue(userId);
      final payload = await _api.getOfflineCardCache();
      await _offlineCardService.cacheCards(
        userId: userId,
        cards: List<VirtualCard>.from(payload['cards'] as List? ?? const []),
        settings: Map<String, dynamic>.from(
          payload['settings'] as Map? ?? const {},
        ),
      );

      if (queuedBeforeSync.isNotEmpty) {
        final result = await _api.syncOfflineCardRedeems(
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
          historyEntries.where((item) => item['status'] == 'rejected').toList(),
        );
        await _offlineCardService.appendSyncHistory(userId, historyEntries);
        await _offlineCardService.removeCardsByBarcode(
          userId: userId,
          barcodes: acceptedBarcodes,
        );
      }

      await _offlineCardService.recordLastSync(userId, source: 'scan_screen');
      _clearedExpiredOfflineCards = false;
      await _refreshOfflineCardStatus();
    } catch (_) {
      await _refreshOfflineCardStatus();
    } finally {
      _isSyncingOfflineCards = false;
    }
  }

  Future<void> _ensureOfflineTemporaryTransferSlots() async {
    final userId = _user?['id']?.toString();
    if (userId == null || userId.isEmpty || _isDeviceOffline) {
      return;
    }
    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canTransfer) {
      return;
    }
    final existingCount = await _offlineTransferCodeService.countAvailableSlots(
      userId,
    );
    if (existingCount >= 5) {
      if (mounted && _availableOfflineTransferSlots != existingCount) {
        setState(() => _availableOfflineTransferSlots = existingCount);
      }
      return;
    }
    try {
      final deviceId = await LocalSecurityService.getOrCreateDeviceId();
      final response = await _api.prefetchTemporaryTransferCodes(
        deviceId: deviceId,
        count: 5 - existingCount,
      );
      final rawSlots = List<Map<String, dynamic>>.from(
        (response['slots'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final merged = await _offlineTransferCodeService.mergeSlots(
        userId,
        rawSlots,
      );
      if (!mounted) {
        return;
      }
      setState(() => _availableOfflineTransferSlots = merged.length);
    } catch (_) {
      await _loadOfflineTransferSlotCount();
    }
  }

  Future<void> _switchScanMode() async {
    _clearTransientScanState(clearBarcode: true);
    if (widget.offlineMode) {
      OfflineSessionService.setOfflineMode(false);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/scan-card');
      return;
    }

    if (!_hasOfflineScanPermission) {
      await AppAlertService.showError(
        context,
        title: 'وضع الأوفلاين غير متاح',
        message:
            'لا تملك صلاحية العمل بدون اتصال على هذا الحساب. يمكنك المتابعة فقط في وضع الأونلاين أو مراجعة الإدارة لتفعيل الصلاحية.',
      );
      return;
    }

    OfflineSessionService.setOfflineMode(true);
    if (!_isDeviceOffline) {
      await _syncOfflineCardsForCurrentUser();
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/scan-card-offline');
  }

  Future<bool> _promptMoveOnlineIfAvailable({
    required String actionLabel,
  }) async {
    if (!widget.offlineMode || _isDeviceOffline) {
      return false;
    }

    final moveOnline = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_scan_card_screen.074')),
        content: Text(
          context.loc.tr(
            'screens_scan_card_screen.075',
            params: {'action': actionLabel},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('screens_scan_card_screen.070')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('screens_scan_card_screen.071')),
          ),
        ],
      ),
    );

    if (!mounted) {
      return false;
    }

    if (moveOnline == true) {
      _clearTransientScanState(clearBarcode: true);
      OfflineSessionService.setOfflineMode(false);
      Navigator.pushReplacementNamed(context, '/scan-card');
      return true;
    }

    return false;
  }

  Future<void> _search() async {
    if (_isPreparingScreen) {
      return;
    }
    if (widget.offlineMode && !await _ensureOfflineAccessReady()) {
      return;
    }
    if (await _promptMoveOnlineIfAvailable(
      actionLabel: _t('screens_scan_card_screen.076'),
    )) {
      return;
    }

    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    final prepaidPayload = _tryParsePrepaidMultipayPayload(barcode);
    if (prepaidPayload != null) {
      setState(() {
        _card = null;
        _isSearching = false;
      });
      await _handlePrepaidMultipayScan(prepaidPayload);
      return;
    }

    setState(() => _isSearching = true);
    final result = await _lookupCard(barcode);
    if (!mounted) return;
    final plainPrepaidPayload = result.card == null
        ? _tryParsePlainPrepaidCardNumber(barcode)
        : null;
    if (plainPrepaidPayload != null &&
        result.errorMessage == context.loc.tr('screens_scan_card_screen.040')) {
      setState(() {
        _card = null;
        _isSearching = false;
      });
      await _handlePrepaidMultipayScan(plainPrepaidPayload);
      return;
    }
    setState(() {
      _card = result.card;
      _isSearching = false;
    });
    if (result.errorMessage != null) {
      if (ErrorMessageService.requiresFreshLogin(result.errorMessage)) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.tr('screens_scan_card_screen.039'),
        message: result.errorMessage!,
      );
    }
  }

  Future<_CardLookupResult> _lookupCard(String barcode) async {
    final notFoundMessage = context.loc.tr('screens_scan_card_screen.040');
    if (widget.offlineMode) {
      return _lookupOfflineCard(barcode);
    }
    try {
      Map<String, dynamic>? location;
      try {
        location =
            await TransactionLocationService.captureCurrentLocationIfPermitted();
      } catch (_) {
        location = null;
      }
      final result = await _api.getCardByBarcode(
        barcode,
        autoRedeem: _autoRedeemOnScan || _autoRedeemOnScanForced,
        location: location,
      );
      final autoRedeemed = _api.lastCardLookupAutoRedeemed;
      final updatedUser = await _auth.currentUser();
      if (mounted && updatedUser != null) {
        setState(() {
          _user = updatedUser;
          _syncAutoRedeemState(updatedUser);
        });
      }
      if (result == null) {
        if (mounted) {
          setState(() => _lastAutoRedeemedBarcode = null);
        }
        return _CardLookupResult.error(notFoundMessage);
      }
      if (mounted) {
        setState(() {
          _lastAutoRedeemedBarcode = autoRedeemed ? result.barcode : null;
        });
      }
      return _CardLookupResult.success(result, autoRedeemed: autoRedeemed);
    } catch (error) {
      if (mounted) {
        setState(() => _lastAutoRedeemedBarcode = null);
      }
      final message = ErrorMessageService.sanitize(error);
      if (ErrorMessageService.requiresFreshLogin(message) && mounted) {
        unawaited(
          AppAlertService.showError(
            context,
            title: context.loc.tr('screens_scan_card_screen.039'),
            message: message,
          ),
        );
      }
      return _CardLookupResult.error(message);
    }
  }

  Future<_CardLookupResult> _lookupOfflineCard(String barcode) async {
    final l = context.loc;
    final user = _user;
    final permissions = AppPermissions.fromUser(user);
    if (!(permissions.canOfflineCardScan &&
        user != null &&
        user['id'] != null)) {
      return _CardLookupResult.error(l.tr('screens_scan_card_screen.078'));
    }

    final userId = user['id'].toString();
    final cached = await _offlineCardService.findCachedCard(userId, barcode);
    if (cached != null) {
      await _offlineCardService.clearUnknownOfflineScans(userId);
      return _CardLookupResult.success(cached);
    }

    final blocked = await _offlineCardService.recordUnknownOfflineScan(
      userId,
      barcode,
    );
    await _offlineCardService.enqueueUnknownCardLookup(
      userId,
      barcode: barcode,
    );
    return _CardLookupResult.error(
      blocked
          ? l.tr('screens_scan_card_screen.079')
          : '${l.tr('screens_scan_card_screen.040')}\n${l.tr('screens_scan_card_screen.080')}',
    );
  }

  bool get _canCreateTemporaryTransferCode {
    final permissions = AppPermissions.fromUser(_user);
    return !widget.offlineMode &&
        permissions.canTransfer &&
        (!_isDeviceOffline || _availableOfflineTransferSlots > 0);
  }

  _TemporaryTransferPayload? _tryParseTemporaryTransferPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final type = decoded['type']?.toString() ?? '';
      if (type != 'temporary_transfer_code' &&
          type != 'shwakel_temp_transfer' &&
          type != 'shwakel_temp_transfer_offline') {
        return null;
      }
      return _TemporaryTransferPayload.fromMap(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _showTemporaryTransferCreator() async {
    if (!_canCreateTemporaryTransferCode) {
      await AppAlertService.showInfo(
        context,
        title: 'رمز تحويل مؤقت',
        message: _isDeviceOffline
            ? 'لا يوجد لديك رصيد محلي جاهز من الرموز المؤقتة. افتح الشاشة أثناء الاتصال لتجهيزها ثم يمكنك الإنشاء أوفلاين.'
            : 'هذه الميزة متاحة للحسابات التي تملك صلاحية تحويل الرصيد. راجع الإدارة إذا كانت الصلاحية غير مفعلة لحسابك.',
      );
      return;
    }

    final amountController = TextEditingController();
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('screens_scan_card_screen.174')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'أدخل قيمة المبلغ المطلوب استلامه. سيبقى الرمز صالحًا لمدة دقيقة واحدة فقط.',
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  hintText: 'مثال: 25',
                  prefixIcon: Icon(Icons.payments_rounded),
                ),
                onSubmitted: (_) => Navigator.of(
                  dialogContext,
                ).pop(double.tryParse(amountController.text.trim())),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(double.tryParse(amountController.text.trim())),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );

      if (!mounted || amount == null || amount <= 0) {
        return;
      }

      late final _TemporaryTransferPayload payload;
      if (_isDeviceOffline) {
        final security = await TransferSecurityService.confirmTransfer(
          context,
          requireOtpAfterLocalAuth: false,
          allowOtpFallback: false,
        );
        if (!mounted || !security.isVerified) {
          return;
        }

        final offlinePayload = await _createOfflineTemporaryTransferPayload(
          amount,
        );
        if (!mounted || offlinePayload == null) {
          return;
        }
        payload = offlinePayload;
      } else {
        final security = await TransferSecurityService.confirmTransfer(
          context,
          allowOtpFallback: false,
        );
        if (!mounted || !security.isVerified) {
          return;
        }

        final response = await _api.createTemporaryTransferCode(
          amount: amount,
          otpCode: security.otpCode,
          localAuthMethod: security.method,
        );
        if (!mounted) {
          return;
        }

        payload = _TemporaryTransferPayload.fromMap(response);
      }
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TemporaryTransferCodeDialog(payload: payload),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر إنشاء الرمز المؤقت',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      amountController.dispose();
    }
  }

  Future<_TemporaryTransferPayload?> _createOfflineTemporaryTransferPayload(
    double amount,
  ) async {
    final userId = _user?['id']?.toString();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final slot = await _offlineTransferCodeService.takeNextSlot(userId);
    if (slot == null) {
      await _loadOfflineTransferSlotCount();
      if (!mounted) {
        return null;
      }
      await AppAlertService.showInfo(
        context,
        title: 'رمز تحويل مؤقت',
        message:
            'لا يوجد لديك رصيد محلي جاهز من الرموز المؤقتة. افتح الشاشة أثناء الاتصال لتجهيز دفعة جديدة.',
      );
      return null;
    }

    final expiresAt = DateTime.tryParse(
      slot['expiresAt']?.toString() ?? '',
    )?.toUtc();
    final slotId = slot['id']?.toString() ?? '';
    final token = slot['publicToken']?.toString() ?? '';
    final signingSecret = slot['signingSecret']?.toString() ?? '';
    if (expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc()) ||
        slotId.isEmpty ||
        token.isEmpty ||
        signingSecret.isEmpty) {
      await _loadOfflineTransferSlotCount();
      return null;
    }

    final signedAt = DateTime.now().toUtc().toIso8601String();
    final expiresAtIso = expiresAt.toIso8601String();
    final signature = await _buildOfflineTemporaryTransferPayloadSignature(
      slotId: slotId,
      token: token,
      amount: amount,
      signedAt: signedAt,
      expiresAt: expiresAtIso,
      signingSecret: signingSecret,
    );

    await _loadOfflineTransferSlotCount();

    final envelope = {
      'type': 'shwakel_temp_transfer_offline',
      'version': 2,
      'slotId': slotId,
      'token': token,
      'amount': amount,
      'signedAt': signedAt,
      'expiresAt': expiresAtIso,
      'signature': signature,
      'senderId': _user?['id']?.toString(),
      'senderUsername': _user?['username']?.toString() ?? '',
    };

    return _TemporaryTransferPayload.fromMap({
      ...envelope,
      'qrPayload': jsonEncode(envelope),
      'feeAmount': 0,
      'netAmount': amount,
    });
  }

  Future<String> _buildOfflineTemporaryTransferPayloadSignature({
    required String slotId,
    required String token,
    required double amount,
    required String signedAt,
    required String expiresAt,
    required String signingSecret,
  }) async {
    final message =
        '$slotId|$token|${amount.toStringAsFixed(2)}|$signedAt|$expiresAt';
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(utf8.encode(signingSecret)),
    );
    return mac.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<BarcodeScannerDialogResult?> _resolveTemporaryTransferDialogResult(
    _TemporaryTransferPayload payload,
  ) async {
    if (!mounted) {
      return null;
    }

    final currentUserId = _user?['id']?.toString();
    if (payload.senderId != null && payload.senderId == currentUserId) {
      return const BarcodeScannerDialogResult.error(
        headline: 'رمز غير صالح لهذا الحساب',
        message:
            'لا يمكنك استخدام رمز التحويل المؤقت على نفس الحساب الذي أنشأه.',
      );
    }

    return BarcodeScannerDialogResult(
      headline: _t('screens_scan_card_screen.123'),
      description: _t('screens_scan_card_screen.124'),
      color: AppTheme.primary,
      icon: Icons.qr_code_2_rounded,
      items: [
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.125'),
          value: CurrencyFormatter.ils(payload.amount),
          icon: Icons.payments_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.126'),
          value: CurrencyFormatter.ils(payload.netAmount),
          icon: Icons.account_balance_wallet_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.127'),
          value: payload.senderUsername.isNotEmpty
              ? payload.senderUsername
              : _t('screens_scan_card_screen.128'),
          icon: Icons.person_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.129'),
          value: _formatDate(payload.expiresAt),
          icon: Icons.timer_outlined,
        ),
      ],
      primaryActionLabel: _t('screens_scan_card_screen.130'),
      primaryActionIcon: Icons.download_done_rounded,
      onPrimaryAction: () async =>
          _redeemTemporaryTransferCodeFromScan(payload),
    );
  }

  Future<BarcodeScannerDialogResult?> _redeemTemporaryTransferCodeFromScan(
    _TemporaryTransferPayload payload,
  ) async {
    try {
      Map<String, dynamic>? location;
      try {
        location = await TransactionLocationService.captureCurrentLocation();
      } catch (_) {
        location = null;
      }
      final response = await _api.redeemTemporaryTransferCode(
        payload: payload.qrPayload,
        location: location,
      );
      if (!mounted) {
        return null;
      }

      final updatedBalance = (response['balance'] as num?)?.toDouble();
      if (updatedBalance != null) {
        await _auth.cacheCurrentUser({...?_user, 'balance': updatedBalance});
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }

      return BarcodeScannerDialogResult(
        headline: _t('screens_scan_card_screen.131'),
        description: _t('screens_scan_card_screen.132'),
        color: AppTheme.success,
        icon: Icons.check_circle_rounded,
        items: [
          BarcodeScannerDialogResultItem(
            label: _t('screens_scan_card_screen.125'),
            value: CurrencyFormatter.ils(
              (response['grossAmount'] as num?)?.toDouble() ?? payload.amount,
            ),
            icon: Icons.payments_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: _t('screens_scan_card_screen.133'),
            value: CurrencyFormatter.ils(
              (response['creditedAmount'] as num?)?.toDouble() ??
                  payload.netAmount,
            ),
            icon: Icons.account_balance_wallet_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: 'من الحساب',
            value:
                response['senderUsername']?.toString() ??
                (payload.senderUsername.isNotEmpty
                    ? payload.senderUsername
                    : 'مستخدم'),
            icon: Icons.person_rounded,
          ),
        ],
      );
    } catch (error) {
      return BarcodeScannerDialogResult.error(
        headline: 'تعذر استلام التحويل',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<BarcodeScannerDialogResult?> _resolvePrepaidMultipayDialogResult(
    _PrepaidMultipayScanPayload payload,
  ) async {
    if (widget.offlineMode) {
      return BarcodeScannerDialogResult.error(
        headline: 'بطاقة دفع مسبق',
        message: 'سحب البطاقات المسبقة يحتاج اتصالًا مباشرًا بالإنترنت.',
      );
    }

    return BarcodeScannerDialogResult(
      headline: '',
      description: '',
      color: AppTheme.primary,
      icon: Icons.credit_card_rounded,
      customContent: _buildPrepaidMultipayScannerResultContent(payload),
      primaryActionLabel: 'اعتماد الدفع',
      primaryActionIcon: Icons.payments_rounded,
      onPrimaryAction: () =>
          _handlePrepaidMultipayScan(payload, showErrorAlert: false),
      hideDialogHeader: true,
      hideDialogDescription: true,
    );
  }

  Future<BarcodeScannerDialogResult?> _handlePrepaidMultipayScan(
    _PrepaidMultipayScanPayload payload, {
    bool showErrorAlert = true,
  }) async {
    if (widget.offlineMode) {
      if (showErrorAlert) {
        await AppAlertService.showError(
          context,
          title: 'بطاقة دفع مسبق',
          message: 'سحب البطاقات المسبقة يحتاج اتصالًا مباشرًا بالإنترنت.',
        );
      }
      return null;
    }

    final amountController = TextEditingController();
    final codeController = TextEditingController();
    final monthController = TextEditingController(
      text: payload.expiryMonth?.toString().padLeft(2, '0') ?? '',
    );
    final yearController = TextEditingController(
      text: payload.expiryYear == null
          ? ''
          : (payload.expiryYear! % 100).toString().padLeft(2, '0'),
    );

    try {
      final submission = await showDialog<_PrepaidPaymentSubmission>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('اعتماد دفع بطاقة مسبقة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPrepaidPaymentDialogCard(payload),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'إضافة قيمة الدفع',
                    hintText: 'مثال: 25',
                    prefixIcon: Icon(Icons.payments_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                if (!payload.hasExpiry) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: monthController,
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          decoration: const InputDecoration(
                            labelText: 'الشهر',
                            counterText: '',
                            prefixIcon: Icon(Icons.calendar_month_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: yearController,
                          keyboardType: TextInputType.number,
                          maxLength: 2,
                          decoration: const InputDecoration(
                            labelText: 'السنة',
                            counterText: '',
                            prefixIcon: Icon(Icons.event_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'كود البطاقة الثلاثي',
                    counterText: '',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'سيتم اعتماد العملية من نفس شاشة الفحص وتحديث الرصيد مباشرة.',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _PrepaidPaymentSubmission(
                  amount: double.tryParse(amountController.text.trim()) ?? 0,
                  code: codeController.text.trim(),
                  expiryMonth: monthController.text.trim(),
                  expiryYear: yearController.text.trim(),
                ),
              ),
              icon: const Icon(Icons.payments_rounded),
              label: const Text('اعتماد'),
            ),
          ],
        ),
      );

      if (!mounted || submission == null) {
        return null;
      }

      if (submission.amount <= 0 ||
          !RegExp(r'^\d{3}$').hasMatch(submission.code)) {
        await AppAlertService.showError(
          context,
          title: 'بيانات غير مكتملة',
          message: 'أدخل مبلغ الدفع وكود التحقق المكوّن من 3 أرقام.',
        );
        return null;
      }

      final month = submission.expiryMonth.trim();
      final year = submission.expiryYear.trim();
      if (!RegExp(r'^\d{1,2}$').hasMatch(month) ||
          !RegExp(r'^\d{2,4}$').hasMatch(year)) {
        await AppAlertService.showError(
          context,
          title: 'بيانات البطاقة غير مكتملة',
          message: 'تعذر تحديد شهر وسنة الانتهاء لهذه البطاقة.',
        );
        return null;
      }

      final response = await _api.acceptPrepaidMultipayCardPayment(
        cardNumber: payload.cardNumber,
        amount: submission.amount,
        expiryMonth: month,
        expiryYear: year,
        securityCode: submission.code,
        idempotencyKey: _newPrepaidPaymentKey(),
      );
      if (!mounted) {
        return null;
      }

      final merchantBalance = (response['merchantBalance'] as num?)?.toDouble();
      if (merchantBalance != null) {
        await _auth.cacheCurrentUser({...?_user, 'balance': merchantBalance});
        if (!mounted) {
          return null;
        }
        setState(() {
          _user = {...?_user, 'balance': merchantBalance};
        });
      }

      final payment = Map<String, dynamic>.from(
        response['payment'] as Map? ?? const {},
      );
      final remaining = (payment['remainingCardBalance'] as num?)?.toDouble();

      return BarcodeScannerDialogResult(
        headline: '',
        description: '',
        color: AppTheme.success,
        icon: Icons.check_circle_rounded,
        customContent: _buildPrepaidPaymentSuccessContent(
          payload: payload,
          amount: submission.amount,
          remaining: remaining,
        ),
        hideDialogHeader: true,
        hideDialogDescription: true,
      );
    } catch (error) {
      if (!mounted) {
        return null;
      }
      final message = ErrorMessageService.sanitize(error);
      if (showErrorAlert) {
        await AppAlertService.showError(
          context,
          title: _t('screens_scan_card_screen.137'),
          message: message,
        );
      }
      return BarcodeScannerDialogResult.error(
        headline: _t('screens_scan_card_screen.137'),
        message: message,
      );
    } finally {
      amountController.dispose();
      codeController.dispose();
      monthController.dispose();
      yearController.dispose();
    }
  }

  Widget _buildPrepaidMultipayScannerResultContent(
    _PrepaidMultipayScanPayload payload,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPrepaidPaymentDialogCard(payload, isLarge: true),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _resultBadge(
              'الخطوة التالية',
              'إضافة القيمة',
              AppTheme.primary,
              icon: Icons.payments_rounded,
            ),
            _resultBadge(
              'التحقق',
              'كود البطاقة الثلاثي',
              AppTheme.info,
              icon: Icons.pin_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrepaidPaymentDialogCard(
    _PrepaidMultipayScanPayload payload, {
    bool isLarge = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLarge ? 20 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0F766E), Color(0xFF155E75)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppTheme.mediumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بطاقة دفع مسبق',
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'PREPAID',
                  textDirection: TextDirection.ltr,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isLarge ? 18 : 14),
          Text(
            payload.maskedCardNumber,
            textDirection: TextDirection.ltr,
            style: AppTheme.h2.copyWith(color: Colors.white, letterSpacing: 0),
          ),
          const SizedBox(height: 10),
          Text(
            payload.label?.trim().isNotEmpty == true
                ? payload.label!.trim()
                : 'بطاقة دفع مسبق عامة',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _prepaidMiniLabel(
                  'طريقة الاعتماد',
                  'فحص موحد',
                  Icons.qr_code_scanner_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _prepaidMiniLabel(
                  'الصلاحية',
                  payload.expiryLabel.isEmpty
                      ? 'غير محددة'
                      : payload.expiryLabel,
                  Icons.event_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _prepaidMiniLabel(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.caption.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrepaidPaymentSuccessContent({
    required _PrepaidMultipayScanPayload payload,
    required double amount,
    required double? remaining,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('screens_scan_card_screen.134'),
                      style: AppTheme.h3.copyWith(color: AppTheme.success),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _resultBadge(
                    'رقم البطاقة',
                    payload.maskedCardNumber,
                    AppTheme.success,
                    icon: Icons.credit_card_rounded,
                    isFullWidth: true,
                  ),
                  _resultBadge(
                    'المبلغ المضاف',
                    CurrencyFormatter.ils(amount),
                    AppTheme.success,
                    icon: Icons.payments_rounded,
                  ),
                  if (remaining != null)
                    _resultBadge(
                      'المتبقي',
                      CurrencyFormatter.ils(remaining),
                      AppTheme.primary,
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _newPrepaidPaymentKey() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'scan-prepaid:$now:${identityHashCode(this)}';
  }

  _PrepaidMultipayScanPayload? _tryParsePrepaidMultipayPayload(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    for (final candidate in _prepaidPayloadCandidates(trimmed)) {
      final parsed = _tryParsePrepaidJsonPayload(candidate);
      if (parsed != null) {
        return parsed;
      }

      final decoded = _tryDecodeBase64Text(candidate);
      if (decoded != null) {
        final decodedParsed = _tryParsePrepaidJsonPayload(decoded);
        if (decodedParsed != null) {
          return decodedParsed;
        }
      }
    }

    return _tryParsePrepaidDelimitedPayload(trimmed);
  }

  _PrepaidMultipayScanPayload? _tryParsePlainPrepaidCardNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D+'), '');
    if (!RegExp(r'^90\d{14}$').hasMatch(digits)) {
      return null;
    }

    return _PrepaidMultipayScanPayload.fromMap({
      'type': 'prepaid_multipay_card',
      'cardNumber': digits,
    });
  }

  List<String> _prepaidPayloadCandidates(String value) {
    final candidates = <String>[value];
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return candidates;
    }

    for (final key in const ['payload', 'data', 'p', 'card', 'qr', 'prepaid']) {
      final queryValue = uri.queryParameters[key]?.trim() ?? '';
      if (queryValue.isNotEmpty) {
        candidates.add(queryValue);
      }
    }

    if (uri.queryParameters.containsKey('cardNumber') ||
        uri.queryParameters.containsKey('card_number') ||
        uri.queryParameters.containsKey('rawCardNumber')) {
      candidates.add(
        jsonEncode({'type': 'prepaid_multipay_card', ...uri.queryParameters}),
      );
    }

    return candidates;
  }

  _PrepaidMultipayScanPayload? _tryParsePrepaidJsonPayload(String value) {
    try {
      final decoded = jsonDecode(value.trim());
      if (decoded is! Map) {
        return null;
      }
      return _prepaidPayloadFromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  _PrepaidMultipayScanPayload? _prepaidPayloadFromMap(
    Map<String, dynamic> map,
  ) {
    final type = map['type']?.toString().trim().toLowerCase() ?? '';
    const supportedTypes = {
      'prepaid_multipay_card',
      'shwakil_prepaid_multipay_card',
      'shwakel_prepaid_multipay_card',
      'prepaid_card',
      'shwakil_prepaid_card',
      'shwakel_prepaid_card',
    };
    final hasPrepaidCardNumber =
        map.containsKey('cardNumber') ||
        map.containsKey('card_number') ||
        map.containsKey('rawCardNumber') ||
        map.containsKey('raw_card_number');
    if (!supportedTypes.contains(type) && !hasPrepaidCardNumber) {
      return null;
    }

    final payload = _PrepaidMultipayScanPayload.fromMap(map);
    return payload.cardNumber.isEmpty ? null : payload;
  }

  String? _tryDecodeBase64Text(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.contains('{')) {
      return null;
    }

    try {
      var padded = normalized.replaceAll('-', '+').replaceAll('_', '/');
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      return utf8.decode(base64Decode(padded));
    } catch (_) {
      return null;
    }
  }

  _PrepaidMultipayScanPayload? _tryParsePrepaidDelimitedPayload(String value) {
    final parts = value.split('|').map((item) => item.trim()).toList();
    if (parts.length < 2) {
      return null;
    }
    final type = parts.first.toLowerCase();
    if (type != 'prepaid_multipay_card' &&
        type != 'shwakil_prepaid_card' &&
        type != 'shwakel_prepaid_card' &&
        type != 'prepaid_card') {
      return null;
    }

    final payload = _PrepaidMultipayScanPayload.fromMap({
      'type': 'prepaid_multipay_card',
      'cardNumber': parts.length > 1 ? parts[1] : '',
      'expiryMonth': parts.length > 2 ? parts[2] : null,
      'expiryYear': parts.length > 3 ? parts[3] : null,
      'label': parts.length > 4 ? parts.sublist(4).join(' ') : null,
    });
    return payload.cardNumber.isEmpty ? null : payload;
  }

  Future<void> _openScannerDialog() async {
    if (widget.offlineMode && !await _ensureOfflineAccessReady()) {
      return;
    }
    if (await _promptMoveOnlineIfAvailable(
      actionLabel: _t('screens_scan_card_screen.077'),
    )) {
      return;
    }
    if (!mounted) {
      return;
    }

    final l = context.loc;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BarcodeScannerDialog(
        title: l.tr('screens_scan_card_screen.001'),
        description: l.tr('screens_scan_card_screen.041'),
        resultTitle: l.tr('screens_scan_card_screen.081'),
        height: 360,
        showFrame: true,
        backgroundColor: Colors.transparent,
        onScanResolved: _resolveScannerDialogResult,
      ),
    );
  }

  Future<void> _readNfcFromUnifiedScanner() async {
    if (_isReadingNfc || _isPreparingScreen) {
      return;
    }
    if (!await _nfc.isAvailable()) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'الدفع بدون تلامس غير متاح',
        message: 'فعّل الاتصال القريب على الجهاز ثم حاول القراءة مرة أخرى.',
        includeSupportGuidance: false,
        reportVisibleError: false,
      );
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _isReadingNfc = true);
    try {
      final result = await _nfc.readAny();
      if (!mounted) {
        return;
      }

      if (result is PrepaidMultipayNfcCardReadResult) {
        final payload = jsonEncode(result.payload.toJson());
        setState(() => _bcC.text = payload);
        await _search();
        return;
      }

      if (result is PrepaidMultipayNfcPaymentReadResult) {
        await _acceptNfcPaymentAuthorizationFromScan(result.authorization);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر قراءة الدفع بدون تلامس',
        message: ErrorMessageService.sanitize(error),
        includeSupportGuidance: false,
        reportVisibleError: false,
      );
    } finally {
      if (mounted) {
        setState(() => _isReadingNfc = false);
      }
    }
  }

  Future<void> _acceptNfcPaymentAuthorizationFromScan(
    PrepaidMultipayNfcPaymentAuthorization authorization,
  ) async {
    if (DateTime.now().toUtc().isAfter(authorization.expiresAt.toUtc())) {
      throw Exception(
        'انتهت صلاحية إذن الدفع بدون تلامس. اطلب من المشتري إنشاء إذن جديد.',
      );
    }

    if (widget.offlineMode || _isDeviceOffline) {
      await _enqueueOfflineNfcPayment(authorization);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم حفظ الدفع',
        message:
            'تم حفظ ${CurrencyFormatter.ils(authorization.amount)} محليًا وسيتم اعتماده تلقائيًا عند توفر الإنترنت.',
      );
      return;
    }

    final response = await _api.acceptPrepaidMultipayNfcPayment(
      signedPayload: authorization.signedPayload,
      signature: authorization.signature,
      idempotencyKey: _newPrepaidPaymentKey(),
      merchantDeviceId: await LocalSecurityService.getOrCreateDeviceId(),
    );
    if (!mounted) {
      return;
    }

    final merchantBalance = (response['merchantBalance'] as num?)?.toDouble();
    if (merchantBalance != null) {
      await _auth.cacheCurrentUser({...?_user, 'balance': merchantBalance});
      if (!mounted) {
        return;
      }
      setState(() {
        _user = {...?_user, 'balance': merchantBalance};
      });
    }

    final status = response['status']?.toString() ?? '';
    if (status == 'approved') {
      await AppAlertService.showSuccess(
        context,
        title: 'تم قبول الدفع بدون تلامس',
        message:
            'تم استلام ${CurrencyFormatter.ils(authorization.amount)} من شاشة الفحص الموحدة.',
      );
      return;
    }

    throw Exception(response['message']?.toString() ?? 'تعذر اعتماد العملية.');
  }

  Future<void> _enqueueOfflineNfcPayment(
    PrepaidMultipayNfcPaymentAuthorization authorization,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _decodeOfflineNfcQueue(
      prefs.getString(_offlineNfcQueueKey),
    );
    existing.add({
      'signedPayload': authorization.signedPayload,
      'signature': authorization.signature,
      'idempotencyKey': _newPrepaidPaymentKey(),
      'merchantDeviceId': await LocalSecurityService.getOrCreateDeviceId(),
      'amount': authorization.amount,
      'acceptedAt': DateTime.now().toUtc().toIso8601String(),
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await prefs.setString(_offlineNfcQueueKey, jsonEncode(existing));
  }

  Future<void> _syncOfflineNfcPayments() async {
    if (_isDeviceOffline) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final queue = _decodeOfflineNfcQueue(prefs.getString(_offlineNfcQueueKey));
    if (queue.isEmpty) {
      return;
    }

    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final item in queue) {
      try {
        await _api.acceptPrepaidMultipayNfcPayment(
          signedPayload: item['signedPayload']?.toString() ?? '',
          signature: item['signature']?.toString() ?? '',
          idempotencyKey: item['idempotencyKey']?.toString() ?? '',
          merchantDeviceId: item['merchantDeviceId']?.toString(),
          acceptedAt: item['acceptedAt']?.toString(),
          offlineAccepted: true,
        );
        synced++;
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setString(_offlineNfcQueueKey, jsonEncode(remaining));
    if (!mounted || synced == 0) {
      return;
    }
    await AppAlertService.showSuccess(
      context,
      title: 'تمت مزامنة الدفع',
      message: 'تم اعتماد $synced عملية دفع بدون تلامس محفوظة.',
    );
  }

  List<Map<String, dynamic>> _decodeOfflineNfcQueue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<BarcodeScannerDialogResult?> _resolveScannerDialogResult(
    String scannedValue,
  ) async {
    final prepaidPayload = _tryParsePrepaidMultipayPayload(scannedValue);
    if (prepaidPayload != null) {
      return _resolvePrepaidMultipayDialogResult(prepaidPayload);
    }

    final temporaryPayload = _tryParseTemporaryTransferPayload(scannedValue);
    if (temporaryPayload != null) {
      return _resolveTemporaryTransferDialogResult(temporaryPayload);
    }

    final lookup = await _lookupCard(scannedValue);
    if (!mounted) {
      return null;
    }
    final plainPrepaidPayload = lookup.card == null
        ? _tryParsePlainPrepaidCardNumber(scannedValue)
        : null;
    if (plainPrepaidPayload != null &&
        lookup.errorMessage == _t('screens_scan_card_screen.040')) {
      setState(() {
        _bcC.text = scannedValue;
        _card = null;
      });
      return _resolvePrepaidMultipayDialogResult(plainPrepaidPayload);
    }
    setState(() {
      _bcC.text = scannedValue;
      _card = lookup.card;
    });
    if (lookup.card == null) {
      return BarcodeScannerDialogResult.error(
        headline: _t('screens_scan_card_screen.082'),
        message: lookup.errorMessage ?? _t('screens_scan_card_screen.083'),
        items: [
          BarcodeScannerDialogResultItem(
            label: _t('screens_scan_card_screen.023'),
            value: scannedValue,
            icon: Icons.qr_code_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: _t('screens_scan_card_screen.019'),
            value: _t('screens_scan_card_screen.039'),
            icon: Icons.error_outline_rounded,
          ),
        ],
      );
    }

    final card = lookup.card!;
    final isAutoRedeemed = lookup.autoRedeemed;
    final isUsed = card.status == CardStatus.used;
    final isRejected = isUsed && !isAutoRedeemed;
    final permissions = AppPermissions.fromUser(_user);
    final canRedeemCards =
        permissions.canRedeemCards &&
        !isUsed &&
        !_isInformationalCard(card) &&
        _canCurrentUserRedeemCard(card, permissions);
    final canResellCards =
        !widget.offlineMode && permissions.canResellCards && isUsed;

    return BarcodeScannerDialogResult(
      headline: '',
      description: '',
      color: _cardAccent(card, forceSuccess: isAutoRedeemed),
      icon: isRejected ? Icons.cancel_rounded : Icons.verified_rounded,
      customContent: _buildCardScannerResultContent(
        card,
        forceSuccess: isAutoRedeemed,
      ),
      primaryActionLabel: canRedeemCards
          ? _t('screens_scan_card_screen.087')
          : (canResellCards ? _t('screens_scan_card_screen.011') : null),
      primaryActionIcon: canRedeemCards
          ? Icons.download_done_rounded
          : (canResellCards ? Icons.autorenew_rounded : null),
      onPrimaryAction: canRedeemCards
          ? () async {
              await _redeemCard(card, showFeedback: false);
              return _resolveScannerDialogResult(card.barcode);
            }
          : (canResellCards
                ? () async {
                    await _resellCardFromScannerResult(card);
                    return _resolveScannerDialogResult(card.barcode);
                  }
                : null),
      hideDialogHeader: true,
      hideDialogDescription: true,
    );
  }

  bool _canCurrentUserRedeemCard(VirtualCard card, AppPermissions permissions) {
    if (!permissions.canReadOwnPrivateCardsOnly) {
      return true;
    }

    if (!card.isPrivate) {
      return false;
    }

    final userId = _user?['id']?.toString().trim() ?? '';
    final username = _user?['username']?.toString().trim() ?? '';

    if (userId.isNotEmpty) {
      if (card.ownerId?.trim() == userId || card.issuedById?.trim() == userId) {
        return true;
      }
      if (card.allowedUserIds.contains(userId)) {
        return true;
      }
    }

    if (username.isNotEmpty && card.allowedUsernames.contains(username)) {
      return true;
    }

    return false;
  }

  Future<bool> _redeemCard(VirtualCard card, {bool showFeedback = true}) async {
    final l = context.loc;
    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canRedeemCards) {
      if (showFeedback) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_scan_card_screen.043'),
          message: l.tr('screens_scan_card_screen.022'),
        );
      }
      return false;
    }

    if (!_canCurrentUserRedeemCard(card, permissions)) {
      if (showFeedback) {
        await AppAlertService.showError(
          context,
          title: 'لا يمكن استرداد هذه البطاقة',
          message: 'هذا الحساب مقيّد لبطاقاته الخاصة فقط.',
        );
      }
      return false;
    }

    setState(() => _isSubmitting = true);
    if (widget.offlineMode) {
      await _redeemOffline(l);
      return true;
    }

    Map<String, dynamic>? location;
    try {
      try {
        location = await TransactionLocationService.captureCurrentLocation();
      } catch (_) {
        location = null;
      }
      final response = await _api.redeemCard(
        cardId: card.id,
        customerName: UserDisplayName.fromMap(
          _user,
          fallback: l.tr('screens_scan_card_screen.060'),
        ),
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      final refreshed = await _lookupCard(card.barcode);
      if (!mounted) return false;
      setState(() {
        _card = refreshed.card;
        if (updatedBalance != null) {
          _user = {...?_user, 'balance': updatedBalance};
        }
      });
      if (showFeedback) {
        AppAlertService.showSuccess(
          context,
          title: l.tr('screens_scan_card_screen.044'),
          message: l.tr('screens_scan_card_screen.045'),
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (showFeedback) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_scan_card_screen.046'),
          message: ErrorMessageService.sanitize(error),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _redeem() async {
    if (_card == null) return;
    await _redeemCard(_card!);
  }

  Future<void> _renewSubscriptionCard(VirtualCard card) async {
    final controller = TextEditingController(text: '30');
    try {
      final days = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تجديد الاشتراك'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'حدد مدة التجديد بالأيام. سيتم احتساب تكلفة التجديد من إعدادات الإدارة الحالية.',
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مدة التجديد',
                  suffixText: 'يوم',
                  prefixIcon: Icon(Icons.event_repeat_rounded),
                ),
                onSubmitted: (_) => Navigator.of(
                  dialogContext,
                ).pop(int.tryParse(controller.text.trim())),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(int.tryParse(controller.text.trim())),
              icon: const Icon(Icons.check_rounded),
              label: const Text('تجديد'),
            ),
          ],
        ),
      );

      if (!mounted || days == null || days < 1) {
        return;
      }

      final security = await TransferSecurityService.confirmTransfer(context);
      if (!mounted || !security.isVerified) {
        return;
      }

      setState(() => _isSubmitting = true);
      final response = await _api.renewSubscriptionCard(
        cardId: card.id,
        durationDays: days,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      final renewed = response['card'];
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        if (renewed is VirtualCard) {
          _card = renewed;
        } else if (renewed is Map) {
          _card = VirtualCard.fromMap(Map<String, dynamic>.from(renewed));
        }
        if (updatedBalance != null) {
          _user = {...?_user, 'balance': updatedBalance};
        }
      });
      await AppAlertService.showSuccess(
        context,
        title: 'تم تجديد الاشتراك',
        message:
            response['message']?.toString() ?? 'تم تحديث مدة الاشتراك بنجاح.',
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر تجديد الاشتراك',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _redeemOffline(AppLocalizer l) async {
    if (!await _ensureOfflineAccessReady()) {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      return;
    }
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

    final savedName = await _promptOfflineCardOwnerName();
    if (!mounted) return;
    if (savedName == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final customerName = UserDisplayName.fromMap(
      _user,
      fallback: l.tr('screens_scan_card_screen.060'),
    );
    await _offlineCardService.enqueueRedeem(userId, {
      'barcode': _card!.barcode,
      'cardId': _card!.id,
      'value': _card!.value,
      'sourceOwnerId': _card!.ownerId,
      'sourceOwnerUsername': _card!.ownerUsername,
      'sourceIssuedById': _card!.issuedById,
      'sourceIssuedByUsername': _card!.issuedByUsername,
      'customerName': customerName,
      'offlineCardOwnerName': savedName,
      'queuedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
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
    if (!mounted) return;
    AppAlertService.showSuccess(
      context,
      title: l.tr('screens_scan_card_screen.063'),
      message:
          '${l.tr('screens_scan_card_screen.064')}\n${l.tr('screens_scan_card_screen.088', params: {'name': savedName})}',
    );
  }

  Future<String?> _promptOfflineCardOwnerName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_scan_card_screen.089')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _t('screens_scan_card_screen.090'),
            hintText: _t('screens_scan_card_screen.091'),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            final value = controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.of(dialogContext).pop(value);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_t('screens_scan_card_screen.050')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: Text(_t('screens_scan_card_screen.092')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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

  Future<void> _resellCardFromScannerResult(VirtualCard card) async {
    final l = context.loc;
    final permissions = AppPermissions.fromUser(_user);
    if (widget.offlineMode || !permissions.canResellCards) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _api.resellCard(
        cardId: card.id,
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      final refreshed = await _lookupCard(card.barcode);
      if (!mounted) return;
      setState(() {
        _card = refreshed.card;
        if (updatedBalance != null) {
          _user = {...?_user, 'balance': updatedBalance};
        }
      });
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
        card.isDelivery ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (card.isDelivery) {
      return context.loc.tr('shared.delivery_card_label');
    }
    if (card.isAppointment) {
      return 'تذكرة موعد';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور';
    }
    if (card.isSubscription) {
      return 'بطاقة اشتراك';
    }
    if (card.isAttendance) {
      return 'بطاقة حضور وانصراف';
    }
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.066')
        : l.tr('screens_scan_card_screen.067');
  }

  bool _isBalanceCard(VirtualCard card) =>
      !card.isSingleUse && !card.isAppointment && !card.isQueueTicket;

  String _rawCardTypeLabel(String type) {
    switch (type.trim().toLowerCase()) {
      case 'delivery':
        return context.loc.tr('shared.delivery_card_label');
      case 'appointment':
        return 'تذكرة موعد';
      case 'queue':
        return 'تذكرة طابور';
      case 'subscription':
        return 'بطاقة اشتراك';
      case 'attendance':
        return 'بطاقة حضور وانصراف';
      case 'single_use':
        return 'بطاقة دخول';
      default:
        return context.loc.tr('shared.balance_card_label');
    }
  }

  String _driverDeliveryProxyNote(VirtualCard card) {
    if (!card.isLoadedAsDeliveryForDriver) {
      return '';
    }
    return context.loc.tr(
      'shared.driver_delivery_proxy_note',
      params: {'type': _rawCardTypeLabel(card.resolvedOriginalCardType)},
    );
  }

  String _cardUsageNote(VirtualCard card) {
    final proxyNote = _driverDeliveryProxyNote(card);
    if (card.isDelivery) {
      final paymentNote = context.loc.tr('shared.delivery_card_payments_note');
      if (proxyNote.isEmpty) {
        return paymentNote;
      }
      return '$paymentNote\n$proxyNote';
    }
    if (card.isAppointment && card.title?.trim().isNotEmpty == true) {
      return card.title!.trim();
    }
    if (card.isQueueTicket && card.title?.trim().isNotEmpty == true) {
      return card.title!.trim();
    }
    if (card.isSubscription) {
      final details = card.subscriptionDetails?.trim() ?? '';
      if (details.isNotEmpty) return details;
      return card.subscriptionName?.trim() ?? '';
    }
    if (card.isAttendance) {
      final parts = [
        if (card.employeeName?.trim().isNotEmpty == true)
          card.employeeName!.trim(),
        if (card.employeeCode?.trim().isNotEmpty == true)
          'رقم: ${card.employeeCode!.trim()}',
        if (card.department?.trim().isNotEmpty == true) card.department!.trim(),
        if (card.attendanceSystem?.trim().isNotEmpty == true)
          card.attendanceSystem!.trim(),
      ];
      return parts.join(' - ');
    }
    return '';
  }

  Map<String, dynamic>? _attendanceScanInfo(VirtualCard card) {
    if (!card.isAttendance) {
      return null;
    }
    final value = card.details['attendanceScan'];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  bool _isInformationalCard(VirtualCard card) =>
      card.isSubscription || card.isAttendance;

  String _visibilityLabel(VirtualCard card) {
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        card.isDelivery ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (card.isDelivery) {
      return l.tr('shared.delivery_card_badge');
    }
    if (card.isAppointment) {
      return 'موعد';
    }
    if (card.isQueueTicket) {
      return 'طابور';
    }
    if (card.isSubscription) {
      return 'اشتراك';
    }
    if (card.isAttendance) {
      return 'حضور';
    }
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.058')
        : l.tr('screens_scan_card_screen.059');
  }

  String _cardAmountLabel(VirtualCard card) {
    if ((card.isSingleUse ||
            card.isAppointment ||
            card.isQueueTicket ||
            card.isSubscription ||
            card.isAttendance) &&
        card.value <= 0) {
      return _cardTypeLabel(card);
    }
    return CurrencyFormatter.ils(card.value);
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
    if (!_canAccessScanScreen && _user != null && !widget.autoReadNfc) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          automaticallyImplyLeading: !widget.offlineMode,
          title: const SizedBox.shrink(),
          actions: widget.offlineMode
              ? [
                  _buildOfflineStatusAction(),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: _t('screens_scan_card_screen.175'),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('screens_scan_card_screen.117'),
                    onPressed: () => Navigator.pushNamed(context, '/debt-book'),
                    icon: const Icon(Icons.menu_book_rounded),
                  ),
                ]
              : const [AppNotificationAction(), QuickLogoutAction()],
        ),
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
                Text(_t('screens_scan_card_screen.093'), style: AppTheme.h3),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.offlineMode,
        title: const SizedBox.shrink(),
        actions: widget.offlineMode
            ? [
                _buildOfflineStatusAction(),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: _t('screens_scan_card_screen.175'),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded),
                  ),
                ),
                IconButton(
                  tooltip: _t('screens_scan_card_screen.117'),
                  onPressed: () => Navigator.pushNamed(context, '/debt-book'),
                  icon: const Icon(Icons.menu_book_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: _canCreateTemporaryTransferCode
                      ? (_isDeviceOffline
                            ? _t('screens_scan_card_screen.176')
                            : _t('screens_scan_card_screen.174'))
                      : _t('screens_scan_card_screen.177'),
                  onPressed: _showTemporaryTransferCreator,
                  icon: Icon(
                    Icons.qr_code_2_rounded,
                    color: _canCreateTemporaryTransferCode
                        ? AppTheme.success
                        : AppTheme.textTertiary,
                  ),
                ),
                IconButton(
                  tooltip: _t('screens_scan_card_screen.104'),
                  onPressed: _switchScanMode,
                  icon: const Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const AppNotificationAction(),
                const QuickLogoutAction(),
              ],
      ),
      drawer: widget.offlineMode ? const AppSidebar() : null,
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: AppTheme.pagePadding(context, top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_buildScannerPanel()],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineStatusAction() {
    final color = _offlineAccessExpired ? AppTheme.error : AppTheme.success;
    return TextButton.icon(
      onPressed: _showOfflineStatusSheet,
      icon: Icon(Icons.inventory_2_rounded, color: color, size: 18),
      label: Text(
        '$_availableOfflineCardCount',
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> _showOfflineStatusSheet() async {
    final lastSync = _offlineLastSyncAt == null
        ? _t('screens_scan_card_screen.122')
        : _formatDate(_offlineLastSyncAt);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('screens_scan_card_screen.154'), style: AppTheme.h3),
              const SizedBox(height: 14),
              _statusSheetRow(
                _t('screens_scan_card_screen.155'),
                '$_availableOfflineCardCount',
              ),
              _statusSheetRow(_t('screens_scan_card_screen.156'), lastSync),
              _statusSheetRow(
                _t('screens_scan_card_screen.157'),
                _t('screens_scan_card_screen.158', {
                  'minutes': '$_offlineSyncIntervalMinutes',
                }),
              ),
              _statusSheetRow(
                _t('screens_scan_card_screen.159'),
                _offlineAccessExpired
                    ? _t('screens_scan_card_screen.160')
                    : _t('screens_scan_card_screen.161'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSyncingOfflineCards || _isDeviceOffline
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          unawaited(_syncOfflineCardsForCurrentUser());
                        },
                  icon: const Icon(Icons.cloud_sync_rounded),
                  label: Text(_t('screens_scan_card_screen.162')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusSheetRow(String label, String value) {
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
                child: Text(
                  _t('screens_scan_card_screen.178'),
                  style: AppTheme.h3,
                ),
              ),
            ],
          ),
          if (widget.offlineMode) ...[
            const SizedBox(height: 14),
            _buildOfflineModeBanner(),
          ],
          const SizedBox(height: 14),
          _buildUserBalanceCard(),
          if (!widget.offlineMode) ...[
            const SizedBox(height: 12),
            _buildAutoRedeemControl(),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bcC,
                    enabled: !_isPreparingScreen,
                    decoration: InputDecoration(
                      labelText: 'رقم الباركود',
                      hintText: _isPreparingScreen
                          ? 'جارٍ تجهيز الشاشة...'
                          : 'اكتب الرقم ثم اضغط بحث',
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
                ),
              ],
            ),
          ),
          if (_isPreparingScreen) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (widget.offlineMode) ...[
            const SizedBox(height: 14),
            _offlineInventoryStatusCard(),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;
              if (isCompact) {
                return Column(
                  children: [
                    ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.077')
                          : l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _isOfflineUseBlocked
                          ? null
                          : _openScannerDialog,
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.076')
                          : l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _isOfflineUseBlocked ? null : _search,
                    ),
                    if (!widget.offlineMode) ...[
                      const SizedBox(height: 12),
                      ShwakelButton(
                        label: _isReadingNfc
                            ? 'جاري قراءة الدفع'
                            : 'قبول دفع بدون تلامس',
                        icon: Icons.contactless_rounded,
                        isSecondary: true,
                        onPressed: _isReadingNfc
                            ? null
                            : _readNfcFromUnifiedScanner,
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.077')
                          : l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _isOfflineUseBlocked
                          ? null
                          : _openScannerDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.076')
                          : l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _isOfflineUseBlocked ? null : _search,
                    ),
                  ),
                  if (!widget.offlineMode) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ShwakelButton(
                        label: _isReadingNfc
                            ? 'جاري قراءة الدفع'
                            : 'قبول دفع بدون تلامس',
                        icon: Icons.contactless_rounded,
                        isSecondary: true,
                        onPressed: _isReadingNfc
                            ? null
                            : _readNfcFromUnifiedScanner,
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

  Widget _buildOfflineModeBanner() {
    final color = _offlineAccessExpired ? AppTheme.error : AppTheme.warning;
    final message = _offlineAccessExpired
        ? 'أنت في وضع الأوفلاين. يلزم تحديث البيانات قبل المتابعة.'
        : 'أنت الآن في وضع الأوفلاين.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodyBold.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlineInventoryStatusCard() {
    final needsRefresh =
        _isOfflineUseBlocked ||
        _isSyncingOfflineCards ||
        _availableOfflineCardCount == 0;
    final color = _isOfflineUseBlocked
        ? AppTheme.error
        : needsRefresh
        ? AppTheme.warning
        : AppTheme.success;
    final statusLabel = _isOfflineUseBlocked
        ? 'يحتاج تحديث'
        : _isSyncingOfflineCards
        ? 'جاري التحديث'
        : _availableOfflineCardCount == 0
        ? 'غير محدث'
        : 'جاهز';
    final lastSyncLabel = _offlineLastSyncAt == null
        ? _t('screens_scan_card_screen.122')
        : _formatDate(_offlineLastSyncAt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.inventory_2_rounded, color: color),
              ),
              Positioned(
                top: -4,
                left: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.24)),
                  ),
                  child: Icon(
                    _isOfflineUseBlocked
                        ? Icons.priority_high_rounded
                        : _isSyncingOfflineCards
                        ? Icons.sync_rounded
                        : _availableOfflineCardCount == 0
                        ? Icons.sync_problem_rounded
                        : Icons.check_rounded,
                    size: 14,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الأوفلاين: $statusLabel',
                  style: AppTheme.bodyBold.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'آخر تحديث: $lastSyncLabel',
                  style: AppTheme.bodyAction.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserBalanceCard() {
    final rawBalance = (_user?['balance'] as num?)?.toDouble() ?? 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رصيدك الحالي',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _showUserBalance
                      ? CurrencyFormatter.ils(rawBalance)
                      : '••••••',
                  style: AppTheme.h3.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _showUserBalance
                ? _t('screens_scan_card_screen.179')
                : _t('screens_scan_card_screen.180'),
            onPressed: _toggleBalanceVisibility,
            icon: Icon(
              _showUserBalance
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRedeemControl() {
    final active = _autoRedeemOnScan || _autoRedeemOnScanForced;
    final unverifiedForced =
        _user?['cardAutoRedeemOnScanUnverifiedForced'] == true ||
        (![
              'admin',
              'support',
              'finance',
            ].contains(_user?['role']?.toString() ?? '') &&
            (_user?['transferVerificationStatus']?.toString() ??
                    'unverified') !=
                'approved');
    final color = _autoRedeemOnScanForced
        ? AppTheme.warning
        : active
        ? AppTheme.success
        : AppTheme.textSecondary;
    final title = _autoRedeemOnScanForced
        ? (unverifiedForced
              ? 'السحب التلقائي مفعل للحساب غير الموثق'
              : 'السحب التلقائي مفروض من الإدارة')
        : active
        ? 'السحب التلقائي مفعل'
        : 'السحب اليدوي مفعل';
    final subtitle = active
        ? 'أي بطاقة تقرأها سيتم استردادها مباشرة وتحويلها إلى مستخدمة.'
        : 'سيتم عرض البطاقة أولاً، ثم تختار السحب يدوياً.';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _isUpdatingAutoRedeemOnScan ? null : _toggleAutoRedeemOnScan,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _isUpdatingAutoRedeemOnScan
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Icon(
                        active
                            ? Icons.download_done_rounded
                            : Icons.fingerprint_rounded,
                        color: color,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyBold.copyWith(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: active,
                onChanged: _isUpdatingAutoRedeemOnScan
                    ? null
                    : (_) => _toggleAutoRedeemOnScan(),
              ),
            ],
          ),
        ),
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
            Text(l.tr('screens_scan_card_screen.014'), style: AppTheme.h3),
          ],
        ),
      );
    }

    final card = _card!;
    final isAutoRedeemSuccess = _lastAutoRedeemedBarcode == card.barcode;
    final actualUsed = card.status == CardStatus.used;
    final isUsed = actualUsed && !isAutoRedeemSuccess;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards =
        appPermissions.canRedeemCards && !_isInformationalCard(card);
    final canResellCards = !widget.offlineMode && appPermissions.canResellCards;

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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;

              final identityBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        isUsed ? Icons.close_rounded : Icons.verified_rounded,
                        color: accent,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isUsed
                              ? l.tr('screens_scan_card_screen.015')
                              : l.tr('screens_scan_card_screen.016'),
                          style: AppTheme.h3.copyWith(color: accent),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.barcode,
                    style: AppTheme.bodyBold.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              );

              final valueHero = Container(
                width: compact ? double.infinity : 270,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isUsed
                        ? const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)]
                        : const [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.payments_rounded, color: accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.tr('screens_scan_card_screen.109'),
                            style: AppTheme.bodyBold.copyWith(color: accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _cardAmountLabel(card),
                      style: AppTheme.h1.copyWith(
                        color: accent,
                        fontSize: compact ? 34 : 42,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isUsed
                          ? l.tr('screens_scan_card_screen.110')
                          : l.tr('screens_scan_card_screen.087'),
                      style: AppTheme.caption.copyWith(
                        color: accent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identityBlock,
                    const SizedBox(height: 14),
                    valueHero,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identityBlock),
                  const SizedBox(width: 14),
                  valueHero,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(
                icon: Icons.category_rounded,
                label: _cardTypeLabel(card),
              ),
              if (card.isDelivery)
                _infoChip(
                  icon: Icons.payments_rounded,
                  label: _cardUsageNote(card),
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
          if (!actualUsed && canRedeemCards)
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.087'),
              icon: Icons.download_done_rounded,
              onPressed: _isOfflineUseBlocked ? null : _redeem,
              isLoading: _isSubmitting,
            )
          else if (actualUsed && !isAutoRedeemSuccess && canResellCards)
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.011'),
              icon: Icons.autorenew_rounded,
              onPressed: _resell,
              isLoading: _isSubmitting,
            )
          else
            Text(
              actualUsed
                  ? l.tr('screens_scan_card_screen.110')
                  : l.tr('screens_scan_card_screen.111'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildResultPanel() {
    return _card == null ? _buildEmptyPreview() : _buildDetails();
  }

  Widget _buildDetails() {
    final card = _card!;
    final isAutoRedeemSuccess = _lastAutoRedeemedBarcode == card.barcode;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards =
        appPermissions.canRedeemCards && !_isInformationalCard(card);
    final canResellCards = !widget.offlineMode && appPermissions.canResellCards;
    final canViewCardDetails = _canRevealSensitiveCardData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(20),
          color: _cardAccent(
            card,
            forceSuccess: isAutoRedeemSuccess,
          ).withValues(alpha: 0.08),
          borderColor: _cardAccent(
            card,
            forceSuccess: isAutoRedeemSuccess,
          ).withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(28),
          shadowLevel: ShwakelShadowLevel.medium,
          child: _buildCardScannerResultContent(
            card,
            forceSuccess: isAutoRedeemSuccess,
          ),
        ),
        const SizedBox(height: 16),
        _buildActionPanel(
          card: card,
          isUsed: card.status == CardStatus.used,
          canRedeemCards: canRedeemCards,
          canResellCards: canResellCards,
          canViewCardDetails: canViewCardDetails,
        ),
      ],
    );
  }

  Widget _buildCardScannerResultContent(
    VirtualCard card, {
    bool forceSuccess = false,
  }) {
    final isFailed = card.status == CardStatus.used && !forceSuccess;
    final temporal = _cardTemporalStatus(card);
    final attendanceScan = _attendanceScanInfo(card);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCardSummaryPanel(card, forceSuccess: forceSuccess),
        const SizedBox(height: 14),
        _resultBadge(
          context.loc.tr('screens_scan_card_screen.024'),
          _cardTypeLabel(card),
          isFailed ? AppTheme.error : AppTheme.primary,
          icon: Icons.category_rounded,
          isFullWidth: isFailed,
        ),
        if (temporal != null) ...[
          const SizedBox(height: 10),
          _resultBadge(
            temporal.label,
            temporal.message,
            temporal.color,
            icon: temporal.icon,
            isFullWidth: true,
          ),
        ],
        if (attendanceScan != null) ...[
          const SizedBox(height: 10),
          _resultBadge(
            'نتيجة الحضور والانصراف',
            attendanceScan['label']?.toString() ?? 'تم تسجيل القراءة',
            attendanceScan['action'] == 'check_out'
                ? AppTheme.accent
                : AppTheme.success,
            icon: attendanceScan['action'] == 'check_out'
                ? Icons.logout_rounded
                : Icons.login_rounded,
            isFullWidth: true,
          ),
        ],
        if (_cardUsageNote(card).trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _resultBadge(
            card.isAttendance ? 'بيانات الربط' : 'التفاصيل',
            _cardUsageNote(card),
            AppTheme.info,
            icon: card.isAttendance
                ? Icons.badge_rounded
                : Icons.description_rounded,
            isFullWidth: true,
          ),
        ],
      ],
    );
  }

  Widget _buildCardSummaryPanel(VirtualCard card, {bool forceSuccess = false}) {
    final l = context.loc;
    final isUsed = card.status == CardStatus.used && !forceSuccess;
    final accent = _cardAccent(card, forceSuccess: forceSuccess);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final hero = Container(
          width: compact ? double.infinity : 270,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isUsed
                  ? const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)]
                  : const [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.payments_rounded, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.tr('screens_scan_card_screen.109'),
                      style: AppTheme.bodyBold.copyWith(color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _cardAmountLabel(card),
                style: AppTheme.h1.copyWith(
                  color: accent,
                  fontSize: compact ? 34 : 42,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _cardTypeLabel(card),
                style: AppTheme.caption.copyWith(
                  color: accent.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_driverDeliveryProxyNote(card).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _driverDeliveryProxyNote(card),
                  style: AppTheme.caption.copyWith(
                    color: accent.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        );

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUsed ? Icons.close_rounded : Icons.verified_rounded,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isUsed
                        ? l.tr('screens_scan_card_screen.015')
                        : l.tr('screens_scan_card_screen.016'),
                    style: AppTheme.h3.copyWith(color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              card.barcode,
              style: AppTheme.bodyBold.copyWith(color: AppTheme.textPrimary),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, const SizedBox(height: 14), hero],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: header),
            const SizedBox(width: 14),
            hero,
          ],
        );
      },
    );
  }

  Color _cardAccent(VirtualCard card, {bool forceSuccess = false}) {
    final temporal = _cardTemporalStatus(card);
    if (temporal != null && !temporal.isActive) {
      return temporal.color;
    }
    return card.status == CardStatus.used && !forceSuccess
        ? AppTheme.error
        : AppTheme.success;
  }

  _CardTemporalStatus? _cardTemporalStatus(VirtualCard card) {
    if (!card.isSubscription && !card.isAttendance) {
      return null;
    }

    final now = DateTime.now();
    final validFrom = card.validFrom?.toLocal();
    final validUntil = card.validUntil?.toLocal();
    if (validFrom != null && now.isBefore(validFrom)) {
      return _CardTemporalStatus(
        label: card.isSubscription ? 'الاشتراك لم يبدأ' : 'لم يبدأ الدوام',
        message: 'يبدأ في ${_formatDate(validFrom)}',
        color: AppTheme.warning,
        icon: Icons.schedule_rounded,
        isActive: false,
      );
    }
    if (validUntil != null && now.isAfter(validUntil)) {
      return _CardTemporalStatus(
        label: card.isSubscription ? 'الاشتراك منتهي' : 'خارج فترة الصلاحية',
        message: 'انتهى في ${_formatDate(validUntil)}',
        color: AppTheme.error,
        icon: Icons.event_busy_rounded,
        isActive: false,
      );
    }

    final range = [
      if (validFrom != null) 'من ${_formatDate(validFrom)}',
      if (validUntil != null) 'حتى ${_formatDate(validUntil)}',
    ].join(' - ');
    return _CardTemporalStatus(
      label: card.isSubscription ? 'اشتراك فعال' : 'بطاقة حضور فعالة',
      message: range.isEmpty ? 'لا توجد نافذة زمنية محددة.' : range,
      color: AppTheme.success,
      icon: Icons.verified_rounded,
      isActive: true,
    );
  }

  Widget _buildActionPanel({
    required VirtualCard card,
    required bool isUsed,
    required bool canRedeemCards,
    required bool canResellCards,
    required bool canViewCardDetails,
  }) {
    final l = context.loc;
    final permissions = AppPermissions.fromUser(_user);
    final canRenewSubscription =
        !widget.offlineMode &&
        card.isSubscription &&
        permissions.canIssueCards &&
        (card.ownerId == null ||
            card.ownerId == _user?['id']?.toString() ||
            permissions.canManageUsers ||
            _user?['id']?.toString() == '1');
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.tr('screens_scan_card_screen.112'), style: AppTheme.h3),
          const SizedBox(height: 16),
          if (_isSubUser && !isUsed) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                canRedeemCards
                    ? l.tr(
                        'screens_scan_card_screen.113',
                        params: {
                          'limit': CurrencyFormatter.ils(
                            _subUserLimit('redeemCardMaxValue') ?? 0,
                          ),
                        },
                      )
                    : l.tr(
                        'screens_scan_card_screen.114',
                        params: {
                          'limit': CurrencyFormatter.ils(
                            _subUserLimit('redeemCardMaxValue') ?? 0,
                          ),
                        },
                      ),
                style: AppTheme.caption.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!isUsed && canRedeemCards) ...[
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.087'),
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
          if (canRenewSubscription) ...[
            OutlinedButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () => _renewSubscriptionCard(card),
              icon: const Icon(Icons.event_repeat_rounded),
              label: const Text('تجديد الاشتراك'),
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
              onPressed: () => _showCardDetailsSheet(card),
              icon: const Icon(Icons.visibility_rounded),
              label: Text(context.loc.tr('screens_scan_card_screen.010')),
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
    bool isFullWidth = false,
  }) {
    return SizedBox(
      width: isFullWidth ? double.infinity : 182,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
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
                      color: color.withValues(alpha: 0.92),
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
                label: _t('screens_scan_card_screen.115'),
              ),
              _infoChip(
                icon: Icons.receipt_long_rounded,
                label: _t('screens_scan_card_screen.116'),
              ),
            ],
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

  Future<void> _showCardDetailsSheet(VirtualCard card) async {
    final l = context.loc;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isUsed
                          ? const [Color(0xFFFFE4E6), Color(0xFFFFF1F2)]
                          : const [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.14),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 560;
                      final titleBlock = Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.payments_rounded, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.tr('screens_scan_card_screen.109'),
                                  style: AppTheme.bodyBold.copyWith(
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isUsed
                                      ? l.tr('screens_scan_card_screen.015')
                                      : l.tr('screens_scan_card_screen.016'),
                                  style: AppTheme.caption.copyWith(
                                    color: accent.withValues(alpha: 0.92),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      final priceBlock = Column(
                        crossAxisAlignment: compact
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.end,
                        children: [
                          Text(
                            _cardAmountLabel(card),
                            style: AppTheme.h1.copyWith(
                              color: accent,
                              fontSize: compact ? 38 : 44,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isUsed
                                      ? Icons.cancel_schedule_send_rounded
                                      : Icons.verified_rounded,
                                  size: 16,
                                  color: accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _statusLabel(card),
                                  style: AppTheme.caption.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleBlock,
                            const SizedBox(height: 18),
                            priceBlock,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: titleBlock),
                          const SizedBox(width: 14),
                          priceBlock,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 620;
                    final items = <Widget>[
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
                      if (_cardUsageNote(card).trim().isNotEmpty)
                        _detailTile(
                          context.loc.tr('shared.usage_label'),
                          _cardUsageNote(card),
                        ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.025'),
                        _visibilityLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.026'),
                        _cardAmountLabel(card),
                      ),
                      _detailTile(
                        _isBalanceCard(card)
                            ? 'رسوم عند الاستخدام'
                            : l.tr('screens_scan_card_screen.027'),
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
                      if (card.validFrom != null || card.validUntil != null)
                        _detailTile(
                          'الصلاحية',
                          '${card.validFrom != null ? _formatDate(card.validFrom) : 'غير محدد'}'
                              '${card.validUntil != null ? ' -> ${_formatDate(card.validUntil)}' : ''}',
                          spanTwo: true,
                        ),
                      if (card.isAppointment &&
                          card.appointmentStartsAt != null)
                        _detailTile(
                          'الموعد',
                          '${_formatDate(card.appointmentStartsAt)}'
                              '${card.appointmentEndsAt != null ? ' -> ${_formatDate(card.appointmentEndsAt)}' : ''}',
                          spanTwo: true,
                        ),
                      if (card.location?.trim().isNotEmpty == true)
                        _detailTile(
                          'الموقع',
                          card.location!.trim(),
                          spanTwo: true,
                        ),
                      if (card.description?.trim().isNotEmpty == true)
                        _detailTile(
                          'ملاحظات',
                          card.description!.trim(),
                          spanTwo: true,
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
                            .toList(growable: false),
                      );
                    }

                    return Wrap(spacing: 12, runSpacing: 12, children: items);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineStatusSnapshot {
  const _OfflineStatusSnapshot({
    required this.availableCount,
    required this.intervalMinutes,
    required this.lastSyncAt,
    required this.expired,
  });

  final int availableCount;
  final int intervalMinutes;
  final DateTime? lastSyncAt;
  final bool expired;
}

class _CardLookupResult {
  const _CardLookupResult.success(this.card, {this.autoRedeemed = false})
    : errorMessage = null;

  const _CardLookupResult.error(this.errorMessage)
    : card = null,
      autoRedeemed = false;

  final VirtualCard? card;
  final String? errorMessage;
  final bool autoRedeemed;
}

class _CardTemporalStatus {
  const _CardTemporalStatus({
    required this.label,
    required this.message,
    required this.color,
    required this.icon,
    required this.isActive,
  });

  final String label;
  final String message;
  final Color color;
  final IconData icon;
  final bool isActive;
}

class _PrepaidPaymentSubmission {
  const _PrepaidPaymentSubmission({
    required this.amount,
    required this.code,
    required this.expiryMonth,
    required this.expiryYear,
  });

  final double amount;
  final String code;
  final String expiryMonth;
  final String expiryYear;
}

class _PrepaidMultipayScanPayload {
  const _PrepaidMultipayScanPayload({
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.label,
  });

  factory _PrepaidMultipayScanPayload.fromMap(Map<String, dynamic> map) {
    final cardNumber = _firstString(map, const [
      'cardNumber',
      'card_number',
      'rawCardNumber',
      'raw_card_number',
      'number',
    ]).replaceAll(RegExp(r'\D+'), '');
    final expiryMonth = _firstInt(map, const [
      'expiryMonth',
      'expiry_month',
      'month',
    ]);
    final expiryYear = _firstInt(map, const [
      'expiryYear',
      'expiry_year',
      'year',
    ]);

    return _PrepaidMultipayScanPayload(
      cardNumber: cardNumber,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      label: _firstString(map, const ['label', 'name', 'title']),
    );
  }

  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static int? _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) {
        return value.toInt();
      }
      final parsed = int.tryParse(value?.toString().trim() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  final String cardNumber;
  final int? expiryMonth;
  final int? expiryYear;
  final String? label;

  bool get hasExpiry => expiryMonth != null && expiryYear != null;

  String get maskedCardNumber {
    if (cardNumber.length < 4) {
      return cardNumber;
    }
    final visible = cardNumber.substring(cardNumber.length - 4);
    return '**** **** **** $visible';
  }

  String get expiryLabel {
    if (!hasExpiry) {
      return '';
    }
    return '${expiryMonth.toString().padLeft(2, '0')}/${(expiryYear! % 100).toString().padLeft(2, '0')}';
  }
}

class _TemporaryTransferPayload {
  const _TemporaryTransferPayload({
    required this.qrPayload,
    required this.amount,
    required this.feeAmount,
    required this.netAmount,
    required this.expiresAt,
    required this.senderUsername,
    this.senderId,
  });

  factory _TemporaryTransferPayload.fromMap(Map<String, dynamic> map) {
    final expiresAt =
        DateTime.tryParse(map['expiresAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now().toLocal().add(const Duration(minutes: 1));
    return _TemporaryTransferPayload(
      qrPayload:
          map['qrPayload']?.toString() ??
          jsonEncode(Map<String, dynamic>.from(map)),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      feeAmount: (map['feeAmount'] as num?)?.toDouble() ?? 0,
      netAmount: (map['netAmount'] as num?)?.toDouble() ?? 0,
      expiresAt: expiresAt,
      senderUsername: map['senderUsername']?.toString() ?? '',
      senderId: map['senderId']?.toString(),
    );
  }

  final String qrPayload;
  final double amount;
  final double feeAmount;
  final double netAmount;
  final DateTime expiresAt;
  final String senderUsername;
  final String? senderId;
}

class _TemporaryTransferCodeDialog extends StatefulWidget {
  const _TemporaryTransferCodeDialog({required this.payload});

  final _TemporaryTransferPayload payload;

  @override
  State<_TemporaryTransferCodeDialog> createState() =>
      _TemporaryTransferCodeDialogState();
}

class _TemporaryTransferCodeDialogState
    extends State<_TemporaryTransferCodeDialog> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _computeRemainingSeconds();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final next = _computeRemainingSeconds();
      if (next <= 0) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _remainingSeconds = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _computeRemainingSeconds() {
    final diff = widget.payload.expiresAt.difference(DateTime.now().toLocal());
    return diff.inSeconds < 0 ? 0 : diff.inSeconds;
  }

  String _formatCountdown() {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatExpiry(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ShwakelCard(
          padding: const EdgeInsets.all(24),
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.loc.tr('screens_scan_card_screen.174'),
                      style: AppTheme.h3,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.loc.tr('screens_scan_card_screen.181'),
                textAlign: TextAlign.center,
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border),
                ),
                child: QrImageView(
                  data: widget.payload.qrPayload,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      CurrencyFormatter.ils(widget.payload.amount),
                      style: AppTheme.h2.copyWith(color: AppTheme.success),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.loc.tr(
                        'screens_scan_card_screen.138',
                        params: {'countdown': _formatCountdown()},
                      ),
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.loc.tr(
                        'screens_scan_card_screen.139',
                        params: {
                          'time': _formatExpiry(widget.payload.expiresAt),
                        },
                      ),
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _TempTransferInfoChip(
                    icon: Icons.payments_rounded,
                    label: context.loc.tr(
                      'screens_scan_card_screen.140',
                      params: {
                        'amount': CurrencyFormatter.ils(
                          widget.payload.feeAmount,
                        ),
                      },
                    ),
                  ),
                  _TempTransferInfoChip(
                    icon: Icons.account_balance_wallet_rounded,
                    label: context.loc.tr(
                      'screens_scan_card_screen.141',
                      params: {
                        'amount': CurrencyFormatter.ils(
                          widget.payload.netAmount,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TempTransferInfoChip extends StatelessWidget {
  const _TempTransferInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            label,
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
