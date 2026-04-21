import 'dart:async';

import 'package:flutter/material.dart';

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
import '../widgets/tool_toggle_hint.dart';

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
  bool _showDetails = false;
  bool _showManualSearch = false;
  bool _routeSubscribed = false;
  bool _hasShownOfflineIntro = false;
  bool _hasShownReconnectPrompt = false;

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

  String _t(String ar, String en) => context.loc.text(ar, en);

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
    _maybeShowOfflineIntro();
  }

  void _handleConnectivityChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
          title: const Text('عاد الإنترنت'),
          content: const Text(
            'تم اكتشاف اتصال بالإنترنت. هل تريد الانتقال الآن إلى شاشة القراءة الأونلاين لمزامنة العمل ومتابعة التنفيذ؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('الاستمرار أوف لاين'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('الانتقال للأونلاين'),
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
        title: 'أنت داخل مساحة الأوف لاين',
        message:
            'استخدم هذه الشاشة لقراءة البطاقة فقط، ثم اعتمدها من نفس النتيجة. ستتم المزامنة لاحقًا عند عودة الإنترنت.',
      );
    });
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
        title: const Text('الأون لاين متوفر'),
        content: Text(
          'أنت الآن في وضع الأوف لاين لكن الإنترنت متوفر. الأولوية في التطبيق للعمل أون لاين، والأوف لاين مخصص للطوارئ فقط. هل تريد الانتقال الآن إلى الأون لاين قبل $actionLabel؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('الاستمرار أوف لاين'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('الانتقال للأونلاين'),
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
    if (await _promptMoveOnlineIfAvailable(actionLabel: 'قراءة البطاقة')) {
      return;
    }

    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isSearching = true);
    final result = await _lookupCard(barcode);
    if (!mounted) return;
    setState(() {
      _card = result.card;
      _showDetails = false;
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
        'لا تتوفر صلاحية الفحص الأوف لاين على هذا الجهاز.',
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
    return _CardLookupResult.error(
      blocked
          ? 'تم إيقاف الفحص مؤقتًا بسبب محاولات كثيرة لبطاقات غير موجودة في ذاكرة الأوف لاين.'
          : l.tr('screens_scan_card_screen.040'),
    );
  }

  Future<void> _openScannerDialog() async {
    if (await _promptMoveOnlineIfAvailable(actionLabel: 'فتح الكاميرا')) {
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
        title: 'فحص الباركود',
        description: l.tr('screens_scan_card_screen.041'),
        resultTitle: 'نتائج الفحص',
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
    final lookup = await _lookupCard(scannedValue);
    if (!mounted) {
      return null;
    }
    setState(() {
      _bcC.text = scannedValue;
      _card = lookup.card;
      _showDetails = false;
    });
    if (lookup.card == null) {
      return BarcodeScannerDialogResult.error(
        headline: 'خطأ في الفحص',
        message: lookup.errorMessage ?? 'تعذر العثور على بيانات هذه البطاقة.',
        items: [
          BarcodeScannerDialogResultItem(
            label: 'الباركود',
            value: scannedValue,
            icon: Icons.qr_code_rounded,
          ),
          BarcodeScannerDialogResultItem(
            label: 'الحالة',
            value: 'فشل الفحص',
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
      headline: isUsed ? 'البطاقة مستخدمة' : 'تم العثور على البطاقة',
      description: isUsed
          ? 'تم فحص البطاقة بنجاح، لكنها مستخدمة بالفعل ولا يمكن سحبها مرة أخرى من هنا.'
          : 'تم فحص البطاقة بنجاح. راجع البيانات الأساسية ثم نفّذ السحب والاعتماد مباشرة.',
      color: isUsed ? AppTheme.error : AppTheme.success,
      icon: isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
      items: [
        BarcodeScannerDialogResultItem(
          label: 'الباركود',
          value: card.barcode,
          icon: Icons.qr_code_2_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'القيمة',
          value: CurrencyFormatter.ils(card.value),
          icon: Icons.payments_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'النوع',
          value: _cardTypeLabel(card),
          icon: Icons.category_rounded,
        ),
        BarcodeScannerDialogResultItem(
          label: 'الحالة',
          value: _statusLabel(card),
          icon: isUsed
              ? Icons.cancel_schedule_send_rounded
              : Icons.verified_rounded,
        ),
      ],
      primaryActionLabel: canRedeemCards ? 'سحب واعتماد' : null,
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
        _showDetails = false;
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
          '${l.tr('screens_scan_card_screen.064')}\nتم حفظ الاسم المرتبط بالبطاقة: $savedName',
    );
  }

  Future<String?> _promptOfflineCardOwnerName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اسم صاحب البطاقة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'أدخل اسمًا لتعريف هذه البطاقة',
            hintText: 'مثال: أحمد - بطاقة رقم 1',
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
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('حفظ'),
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
        appBar: AppBar(
          title: Text(l.tr('screens_scan_card_screen.001')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
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
            tooltip: _showManualSearch
                ? _t('إخفاء البحث اليدوي', 'Hide manual search')
                : _t('إظهار البحث اليدوي', 'Show manual search'),
            onPressed: () =>
                setState(() => _showManualSearch = !_showManualSearch),
            icon: Icon(
              _showManualSearch
                  ? Icons.search_off_rounded
                  : Icons.manage_search_rounded,
            ),
          ),
          IconButton(
            tooltip: _t('مساعدة', 'Help'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
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
          if (widget.offlineMode && _isDeviceOffline) ...[
            const Center(child: ShwakelLogo(size: 74, framed: true)),
            const SizedBox(height: 14),
            Text(
              'قراءة البطاقة أوف لاين',
              style: AppTheme.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'العمل أوف لاين. امسح الباركود أو أدخل الرقم يدويًا ثم اعتمد البطاقة مباشرة.',
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
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _switchScanMode,
            icon: Icon(
              widget.offlineMode
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_off_rounded,
            ),
            label: Text(
              widget.offlineMode
                  ? _t('الانتقال إلى الأون لاين', 'Switch to online')
                  : _t('الانتقال إلى الأوف لاين', 'Switch to offline'),
            ),
          ),
          if (_showManualSearch) ...[
            const SizedBox(height: 18),
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
          ] else ...[
            const SizedBox(height: 18),
            ToolToggleHint(
              message: _t(
                'يمكنك فتح البحث اليدوي من أيقونة البحث بالأعلى عند الحاجة.',
                'Open manual search from the top search icon when needed.',
              ),
              icon: Icons.manage_search_rounded,
            ),
          ],
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
                        'سيتم الفحص من البيانات المحلية فقط، وعند رجوع الإنترنت ستظهر لك رسالة للانتقال إلى الأونلاين.',
                        'Local data only will be used. You will be prompted to move online when connectivity returns.',
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
                        'الإنترنت متوفر الآن. يفضّل الانتقال إلى الأون لاين، وسيتم تذكيرك بذلك عند استخدام القراءة أو الكاميرا.',
                        'Internet is available now. Online mode is preferred, and you will be reminded when using scan actions.',
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
                        'إخلاء طرف: التطبيق غير مسؤول عن حالات التعارض، أو البطاقات غير الموجودة في النظام، أو أي بطاقة تمت إضافتها واعتمادها أثناء وضع الأوف لاين ثم تعذر تأكيدها لاحقًا. المسؤولية تقع على من قام بإدخال البطاقة واعتمادها في وضع الأوف لاين.',
                        'Disclaimer: the app is not responsible for conflicts, cards not found in the system, or any card added and approved in offline mode then not confirmed later. Responsibility remains with the user who entered and approved it offline.',
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
                          ? 'فتح الكاميرا'
                          : l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: widget.offlineMode
                          ? 'قراءة البطاقة'
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
                          ? 'فتح الكاميرا'
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
                          ? 'قراءة البطاقة'
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
                  'قيمة البطاقة',
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
              label: 'سحب واعتماد',
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
                  ? _t(
                      'هذه البطاقة مستعملة بالفعل.',
                      'This card is already used.',
                    )
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
                    ? 'سقف اعتماد البطاقة لهذا التابع هو ${CurrencyFormatter.ils(_subUserLimit('redeemCardMaxValue') ?? 0)}. إذا تجاوزت البطاقة هذا الحد فلن يتم اعتمادها من هذا الحساب.'
                    : 'هذا الحساب تابع، والاعتماد يحتاج صلاحية مفعلة. عند التفعيل سيطبّق عليه سقف ${CurrencyFormatter.ils(_subUserLimit('redeemCardMaxValue') ?? 0)} للبطاقة الواحدة.',
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
              label: 'سحب واعتماد',
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

class _CardLookupResult {
  const _CardLookupResult.success(this.card) : errorMessage = null;

  const _CardLookupResult.error(this.errorMessage) : card = null;

  final VirtualCard? card;
  final String? errorMessage;
}
