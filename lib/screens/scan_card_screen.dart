import 'dart:async';

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/barcode_scanner_dialog.dart';
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
  });

  final String? initialBarcode;
  final bool offlineMode;
  final bool autoOpenScanner;

  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> with RouteAware {
  final TextEditingController _bcC = TextEditingController();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final OfflineTransferCodeService _offlineTransferCodeService =
      OfflineTransferCodeService();

  VirtualCard? _card;
  Map<String, dynamic>? _user;
  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _routeSubscribed = false;
  bool _hasShownOfflineIntro = false;
  bool _hasShownReconnectPrompt = false;
  bool _autoScannerOpened = false;
  int _availableOfflineTransferSlots = 0;

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
    ConnectivityService.instance.isOnline.removeListener(
      _handleConnectivityChanged,
    );
    _bcC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (mounted) {
      setState(() => _user = user);
    }
    await _loadOfflineTransferSlotCount();
    await _ensureOfflineTemporaryTransferSlots();
    _maybeShowOfflineIntro();
    _maybeOpenScannerAutomatically();
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

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    if (ConnectivityService.instance.isOnline.value) {
      unawaited(_ensureOfflineTemporaryTransferSlots());
    }
    if (!widget.offlineMode) {
      return;
    }
    if (!ConnectivityService.instance.isOnline.value ||
        _hasShownReconnectPrompt) {
      return;
    }
    _hasShownReconnectPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final moveOnline = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('screens_scan_card_screen.068')),
          content: Text(_t('screens_scan_card_screen.069')),
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
      if (moveOnline == true && mounted) {
        OfflineSessionService.setOfflineMode(false);
        Navigator.pushReplacementNamed(context, '/scan-card');
      }
    });
  }

  void _maybeShowOfflineIntro() {
    if (!mounted ||
        !widget.offlineMode ||
        _hasShownOfflineIntro ||
        !_isDeviceOffline) {
      return;
    }
    _hasShownOfflineIntro = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      AppAlertService.showInfo(
        context,
        title: _t('screens_scan_card_screen.072'),
        message: _t('screens_scan_card_screen.073'),
      );
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

  Future<void> _ensureOfflineTemporaryTransferSlots() async {
    final userId = _user?['id']?.toString();
    if (userId == null || userId.isEmpty || _isDeviceOffline) {
      return;
    }
    final permissions = AppPermissions.fromUser(_user);
    if (!permissions.canTransfer ||
        (_user?['transferVerificationStatus']?.toString() != 'approved')) {
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
    if (widget.offlineMode) {
      OfflineSessionService.setOfflineMode(false);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/scan-card');
      return;
    }

    OfflineSessionService.setOfflineMode(true);
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
      OfflineSessionService.setOfflineMode(false);
      Navigator.pushReplacementNamed(context, '/scan-card');
      return true;
    }

    return false;
  }

  Future<void> _search() async {
    if (await _promptMoveOnlineIfAvailable(
      actionLabel: _t('screens_scan_card_screen.076'),
    )) {
      return;
    }

    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isSearching = true);
    final result = await _lookupCard(barcode);
    if (!mounted) return;
    setState(() {
      _card = result.card;
      _isSearching = false;
    });
    if (result.errorMessage != null) {
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
      final result = await _api.getCardByBarcode(barcode);
      if (result == null) {
        return _CardLookupResult.error(notFoundMessage);
      }
      return _CardLookupResult.success(result);
    } catch (error) {
      return _CardLookupResult.error(ErrorMessageService.sanitize(error));
    }
  }

  Future<_CardLookupResult> _lookupOfflineCard(String barcode) async {
    final l = context.loc;
    final user = _user;
    final permissions = AppPermissions.fromUser(user);
    if (!(permissions.canOfflineCardScan &&
        user != null &&
        user['id'] != null)) {
      return _CardLookupResult.error(
        l.tr('screens_scan_card_screen.078'),
      );
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
        (_user?['transferVerificationStatus']?.toString() == 'approved') &&
        (!_isDeviceOffline || _availableOfflineTransferSlots > 0);
  }

  _TemporaryTransferPayload? _tryParseTemporaryTransferPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return _TemporaryTransferPayload.fromMap(Map<String, dynamic>.from(decoded));
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
            : 'هذه الميزة متاحة فقط للحسابات الموثقة والمصرح لها بالتحويل.',
      );
      return;
    }

    final amountController = TextEditingController();
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إنشاء رمز تحويل مؤقت'),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  hintText: 'مثال: 25',
                  prefixIcon: Icon(Icons.payments_rounded),
                ),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(
                  double.tryParse(amountController.text.trim()),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                double.tryParse(amountController.text.trim()),
              ),
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
        final hasLocalSecurity = await _hasLocalTransferSecurity();
        final security = await TransferSecurityService.confirmTransfer(
          context,
          allowOtpFallback: !hasLocalSecurity,
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

  Future<bool> _hasLocalTransferSecurity() async {
    final hasPin = await LocalSecurityService.hasPin();
    if (hasPin) {
      return true;
    }

    return LocalSecurityService.isBiometricEnabled();
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

    final expiresAt =
        DateTime.tryParse(slot['expiresAt']?.toString() ?? '')?.toUtc();
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
        message: 'لا يمكنك استخدام رمز التحويل المؤقت على نفس الحساب الذي أنشأه.',
      );
    }

    return BarcodeScannerDialogResult(
      headline: 'رمز تحويل مؤقت',
      description: 'تم العثور على رمز تحويل بمبلغ محدد. راجع البيانات ثم أكد الاستلام خلال مدة الصلاحية.',
      color: AppTheme.primary,
      icon: Icons.qr_code_2_rounded,
      items: [
        BarcodeScannerDialogResultItem(
          label: 'المبلغ',
          value: CurrencyFormatter.ils(payload.amount),
          icon: Icons.payments_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'صافي الاستلام',
          value: CurrencyFormatter.ils(payload.netAmount),
          icon: Icons.account_balance_wallet_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'من الحساب',
          value: payload.senderUsername.isNotEmpty ? payload.senderUsername : 'مستخدم',
          icon: Icons.person_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'ينتهي عند',
          value: _formatDate(payload.expiresAt),
          icon: Icons.timer_outlined,
        ),
      ],
      primaryActionLabel: 'استلام الآن',
      primaryActionIcon: Icons.download_done_rounded,
      onPrimaryAction: () async => _redeemTemporaryTransferCodeFromScan(payload),
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
        await _auth.cacheCurrentUser({
          ...?_user,
          'balance': updatedBalance,
        });
        setState(() {
          _user = {
            ...?_user,
            'balance': updatedBalance,
          };
        });
      }

      return BarcodeScannerDialogResult(
        headline: 'تم الاستلام بنجاح',
        description: 'تم خصم المبلغ من رصيد المُرسل وتحويله إلى حسابك عبر الرمز المؤقت.',
        color: AppTheme.success,
        icon: Icons.check_circle_rounded,
        items: [
          BarcodeScannerDialogResultItem(
            label: 'المبلغ',
            value: CurrencyFormatter.ils(
              (response['grossAmount'] as num?)?.toDouble() ?? payload.amount,
            ),
            icon: Icons.payments_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: 'المضاف إلى حسابك',
            value: CurrencyFormatter.ils(
              (response['creditedAmount'] as num?)?.toDouble() ?? payload.netAmount,
            ),
            icon: Icons.account_balance_wallet_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: 'من الحساب',
            value:
                response['senderUsername']?.toString() ??
                (payload.senderUsername.isNotEmpty ? payload.senderUsername : 'مستخدم'),
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

  Future<void> _openScannerDialog() async {
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

  Future<BarcodeScannerDialogResult?> _resolveScannerDialogResult(
    String scannedValue,
  ) async {
    final temporaryPayload = _tryParseTemporaryTransferPayload(scannedValue);
    if (temporaryPayload != null) {
      return _resolveTemporaryTransferDialogResult(temporaryPayload);
    }

    final lookup = await _lookupCard(scannedValue);
    if (!mounted) {
      return null;
    }
    setState(() {
      _bcC.text = scannedValue;
      _card = lookup.card;
    });
    if (lookup.card == null) {
      return BarcodeScannerDialogResult.error(
        headline: _t('screens_scan_card_screen.082'),
        message:
            lookup.errorMessage ?? _t('screens_scan_card_screen.083'),
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
    final isUsed = card.status == CardStatus.used;
    final permissions = AppPermissions.fromUser(_user);
    final canRedeemCards = permissions.canRedeemCards && !isUsed;

    return BarcodeScannerDialogResult(
      headline: isUsed
          ? _t('screens_scan_card_screen.015')
          : _t('screens_scan_card_screen.084'),
      description: isUsed
          ? _t('screens_scan_card_screen.085')
          : _t('screens_scan_card_screen.086'),
      color: isUsed ? AppTheme.error : AppTheme.success,
      icon: isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
      items: [
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.023'),
          value: card.barcode,
          icon: Icons.qr_code_2_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.020'),
          value: CurrencyFormatter.ils(card.value),
          icon: Icons.payments_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.024'),
          value: _cardTypeLabel(card),
          icon: Icons.category_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: _t('screens_scan_card_screen.019'),
          value: _statusLabel(card),
          icon: isUsed
              ? Icons.cancel_schedule_send_rounded
              : Icons.verified_rounded,
        ),
      ],
      primaryActionLabel: canRedeemCards
          ? _t('screens_scan_card_screen.087')
          : null,
      primaryActionIcon: Icons.download_done_rounded,
      onPrimaryAction: canRedeemCards
          ? () async {
              final success = await _redeemCard(card, showFeedback: false);
              if (!success) {
                return _resolveScannerDialogResult(card.barcode);
              }
              return _resolveScannerDialogResult(card.barcode);
            }
          : null,
    );
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
        customerName:
            _user?['fullName'] ??
            _user?['username'] ??
            l.tr('screens_scan_card_screen.060'),
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

    final savedName = await _promptOfflineCardOwnerName();
    if (!mounted) return;
    if (savedName == null) {
      setState(() => _isSubmitting = false);
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
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.066')
        : l.tr('screens_scan_card_screen.067');
  }

  String _cardUsageNote(VirtualCard card) {
    if (card.isDelivery) {
      return context.loc.tr('shared.delivery_card_payments_note');
    }
    return '';
  }

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
    if (!_canAccessScanScreen && _user != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          automaticallyImplyLeading: !widget.offlineMode,
          title: const SizedBox.shrink(),
          actions: widget.offlineMode
              ? const []
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
                Text(
                  _t('screens_scan_card_screen.093'),
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
        automaticallyImplyLeading: !widget.offlineMode,
        title: const SizedBox.shrink(),
        actions: widget.offlineMode
            ? const []
            : [
                IconButton(
                  tooltip: _t('screens_scan_card_screen.096'),
                  onPressed: _showHelpDialog,
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                IconButton(
                  tooltip: _canCreateTemporaryTransferCode
                      ? (_isDeviceOffline
                          ? 'إنشاء رمز تحويل مؤقت أوفلاين من الرصيد المحلي الجاهز'
                          : 'إنشاء رمز تحويل مؤقت')
                      : 'يتطلب حسابًا موثقًا ورصيدًا محليًا جاهزًا عند انقطاع الإنترنت',
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

  Future<void> _showHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_scan_card_screen.097')),
        content: Text(
          widget.offlineMode
              ? _t('screens_scan_card_screen.098')
              : _t('screens_scan_card_screen.099'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_t('screens_scan_card_screen.100')),
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
          if (widget.offlineMode && _isDeviceOffline) ...[
            const Center(child: ShwakelLogo(size: 74, framed: true)),
            const SizedBox(height: 14),
            Text(
              _t('screens_scan_card_screen.101'),
              style: AppTheme.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _t('screens_scan_card_screen.102'),
              style: AppTheme.bodyAction,
              textAlign: TextAlign.center,
            ),
          ] else
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
                        'البحث عن بطاقة',
                        style: AppTheme.h3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'أدخل رقم الباركود للوصول السريع إلى البطاقة.',
                        style: AppTheme.bodyAction,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
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
                    decoration: InputDecoration(
                      labelText: 'رقم الباركود',
                      hintText: 'اكتب الرقم ثم اضغط بحث',
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
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.offlineMode
                  ? AppTheme.warning.withValues(alpha: 0.08)
                  : AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              widget.offlineMode
                  ? 'وضع الأوفلاين مفعل. يمكنك البحث ضمن البطاقات المحفوظة.'
                  : 'ابحث عن بطاقة برقم الباركود أو استخدم الكاميرا للفحص السريع.',
              style: AppTheme.bodyAction.copyWith(
                color: widget.offlineMode
                    ? AppTheme.warning
                    : AppTheme.textSecondary,
              ),
            ),
          ),
          if (widget.offlineMode && _isDeviceOffline) ...[
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
                        'screens_scan_card_screen.106',
                      ),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (widget.offlineMode) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_rounded, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(
                        'screens_scan_card_screen.107',
                      ),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.gpp_maybe_rounded, color: AppTheme.error),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(
                        'screens_scan_card_screen.108',
                      ),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.error,
                        height: 1.55,
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
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.077')
                          : l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.076')
                          : l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
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
                      onPressed: _openScannerDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: widget.offlineMode
                          ? _t('screens_scan_card_screen.076')
                          : l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ),
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
            Text(l.tr('screens_scan_card_screen.014'), style: AppTheme.h3),
          ],
        ),
      );
    }

    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards = appPermissions.canRedeemCards;
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
                          ? l.tr('screens_scan_card_screen.015')
                          : l.tr('screens_scan_card_screen.016'),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.08),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_scan_card_screen.109'),
                  style: AppTheme.caption.copyWith(color: accent),
                ),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.ils(card.value),
                  style: AppTheme.h1.copyWith(color: accent, fontSize: 30),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!isUsed && canRedeemCards)
            ShwakelButton(
              label: l.tr('screens_scan_card_screen.087'),
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
    final l = context.loc;
    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards = appPermissions.canRedeemCards;
    final canResellCards = !widget.offlineMode && appPermissions.canResellCards;
    final canViewCardDetails = _canRevealSensitiveCardData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(20),
          color: accent.withValues(alpha: 0.08),
          borderColor: accent.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(28),
          shadowLevel: ShwakelShadowLevel.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 4),
                        Text(
                          isUsed
                              ? l.tr('screens_scan_card_screen.017')
                              : l.tr('screens_scan_card_screen.018'),
                          style: AppTheme.caption.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: accent.withValues(alpha: 0.16)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_scan_card_screen.020'),
                          style: AppTheme.caption.copyWith(color: accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CurrencyFormatter.ils(card.value),
                          style: AppTheme.h2.copyWith(
                            color: accent,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
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
                  _resultBadge(
                    l.tr('screens_scan_card_screen.019'),
                    _statusLabel(card),
                    accent,
                    icon: isUsed
                        ? Icons.cancel_schedule_send_rounded
                        : Icons.verified_rounded,
                  ),
                    _resultBadge(
                      l.tr('screens_scan_card_screen.024'),
                      _cardTypeLabel(card),
                      AppTheme.primary,
                      icon: Icons.category_rounded,
                    ),
                    if (card.isDelivery)
                      _resultBadge(
                        context.loc.tr('shared.usage_label'),
                        _cardUsageNote(card),
                        AppTheme.success,
                        icon: Icons.payments_rounded,
                      ),
                    _resultBadge(
                      l.tr('screens_scan_card_screen.025'),
                      _visibilityLabel(card),
                      AppTheme.warning,
                    icon: Icons.public_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildActionPanel(
          card: card,
          isUsed: isUsed,
          canRedeemCards: canRedeemCards,
          canResellCards: canResellCards,
          canViewCardDetails: canViewCardDetails,
        ),
      ],
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
                  'screens_scan_card_screen.115',
                ),
              ),
              _infoChip(
                icon: Icons.receipt_long_rounded,
                label: _t(
                  'screens_scan_card_screen.116',
                ),
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
                      if (card.isDelivery)
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

class _CardLookupResult {
  const _CardLookupResult.success(this.card) : errorMessage = null;

  const _CardLookupResult.error(this.errorMessage) : card = null;

  final VirtualCard? card;
  final String? errorMessage;
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
                    child: Text('رمز تحويل مؤقت', style: AppTheme.h3),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'اعرض هذا الرمز للطرف المستلم. تنتهي صلاحيته تلقائيًا بعد دقيقة واحدة من وقت إنشائه.',
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
                      'العد التنازلي: ${_formatCountdown()}',
                      style: AppTheme.bodyBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ينتهي عند ${_formatExpiry(widget.payload.expiresAt)}',
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
                    label: 'الرسوم ${CurrencyFormatter.ils(widget.payload.feeAmount)}',
                  ),
                  _TempTransferInfoChip(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'الصافي ${CurrencyFormatter.ils(widget.payload.netAmount)}',
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
          Text(label, style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
