import 'dart:convert';

import 'package:barcode/barcode.dart' as barcode;
import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class PrepaidMultipayCardsScreen extends StatefulWidget {
  const PrepaidMultipayCardsScreen({
    super.key,
    this.openPaymentsTab = false,
    this.autoAcceptNfc = false,
  });

  final bool openPaymentsTab;
  final bool autoAcceptNfc;

  @override
  State<PrepaidMultipayCardsScreen> createState() =>
      _PrepaidMultipayCardsScreenState();
}

class _PrepaidMultipayCardsScreenState
    extends State<PrepaidMultipayCardsScreen> {
  final ApiService _api = ApiService();
  final PrepaidMultipayNfcService _nfc = const PrepaidMultipayNfcService();
  final PrepaidMultipayOfflineCacheService _offlineCache =
      const PrepaidMultipayOfflineCacheService();

  bool _isLoading = true;
  bool _isReloading = false;
  bool _isRegisteringNfc = false;
  bool _isWritingNfc = false;
  bool _isWritingNfcPayment = false;
  bool _isAuthorized = true;
  bool _canUsePrepaidCards = false;
  bool _canAcceptPrepaidPayments = false;
  bool _canUsePrepaidNfc = false;
  bool _canManagePrepaidCards = false;
  bool _nfcEnabled = false;
  bool _isShowingOfflineCards = false;
  bool _selfServiceCanCreateCard = true;
  bool _selfServiceLimitReached = false;
  int _selfServiceMaxCards = 1;
  static const List<int> _validityYearOptions = [1, 2, 3, 4, 5];
  List<Map<String, dynamic>> _cards = const [];
  final Set<String> _revealedCardIds = <String>{};
  String? _selectedCardId;
  String _activityFilter = 'all';
  String _cardsPane = 'list';
  bool _showCardTechnicalDetails = false;
  bool _didApplyInitialAction = false;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;
  pw.MemoryImage? _pdfLogoImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Map<String, dynamic>? get _selectedCard {
    for (final card in _cards) {
      if (card['id']?.toString() == _selectedCardId) {
        return card;
      }
    }
    return _cards.isEmpty ? null : _cards.first;
  }

  Future<void> _load() async {
    try {
      final currentUser =
          AuthService.peekCurrentUser() ?? await AuthService().currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      final canUsePrepaidCards = permissions.canUsePrepaidMultipayCards;
      final canAcceptPrepaidPayments =
          permissions.canAcceptPrepaidMultipayPayments;
      final canUsePrepaidNfc = permissions.canUsePrepaidMultipayNfc;
      final canManagePrepaidCards =
          permissions.canManageUsers ||
          permissions.canManageSystemSettings ||
          permissions.isAdminRole;

      if (!permissions.canOpenPrepaidMultipayCards) {
        if (await _loadOfflinePrepaidCards()) {
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _canUsePrepaidCards = false;
          _canAcceptPrepaidPayments = false;
          _canUsePrepaidNfc = false;
          _isLoading = false;
        });
        return;
      }

      final payload = await _api.getPrepaidMultipayCards();
      if (!mounted) {
        return;
      }

      final cards = List<Map<String, dynamic>>.from(
        (payload['cards'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final payments = List<Map<String, dynamic>>.from(
        (payload['payments'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      setState(() {
        _isAuthorized = true;
        _canUsePrepaidCards = canUsePrepaidCards;
        _canAcceptPrepaidPayments = canAcceptPrepaidPayments;
        _canUsePrepaidNfc = canUsePrepaidNfc;
        _canManagePrepaidCards = canManagePrepaidCards;
        _isShowingOfflineCards = false;
        _nfcEnabled =
            ((payload['settings'] as Map?)?['nfc'] as Map?)?['enabled'] == true;
        _selfServiceMaxCards =
            ((payload['selfService'] as Map?)?['maxActiveCards'] as num?)
                ?.toInt() ??
            1;
        _selfServiceLimitReached =
            ((payload['selfService'] as Map?)?['limitReached']) == true;
        _selfServiceCanCreateCard =
            canManagePrepaidCards ||
            ((payload['selfService'] as Map?)?['canCreate']) == true;
        _cards = cards;
        _revealedCardIds.removeWhere(
          (id) => !_cards.any((card) => card['id']?.toString() == id),
        );
        if (_selectedCardId == null ||
            !_cards.any((card) => card['id']?.toString() == _selectedCardId)) {
          _selectedCardId = _cards.isEmpty
              ? null
              : _cards.first['id']?.toString();
        }
        _isLoading = false;
      });
      await _cachePrepaidCardsForOffline(
        cards: cards,
        payments: payments,
        nfcEnabled: _nfcEnabled,
        canUsePrepaidCards: canUsePrepaidCards,
        canAcceptPrepaidPayments: canAcceptPrepaidPayments,
        canUsePrepaidNfc: canUsePrepaidNfc,
      );
      _applyInitialAction();
    } catch (error) {
      if (await _loadOfflinePrepaidCards()) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_prepaid_multipay_cards_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _cachePrepaidCardsForOffline({
    required List<Map<String, dynamic>> cards,
    required List<Map<String, dynamic>> payments,
    required bool nfcEnabled,
    required bool canUsePrepaidCards,
    required bool canAcceptPrepaidPayments,
    required bool canUsePrepaidNfc,
  }) async {
    if (cards.isEmpty || !canUsePrepaidCards) {
      return;
    }

    await _offlineCache.save(
      cards: cards,
      payments: payments,
      nfcEnabled: nfcEnabled,
      canUsePrepaidCards: canUsePrepaidCards,
      canAcceptPrepaidPayments: canAcceptPrepaidPayments,
      canUsePrepaidNfc: canUsePrepaidNfc,
    );
  }

  Future<bool> _loadOfflinePrepaidCards() async {
    final cached = await _offlineCache.load();
    if (cached == null) {
      return false;
    }

    final cards = List<Map<String, dynamic>>.from(cached['cards'] as List);
    if (cards.isEmpty || !mounted) {
      return false;
    }

    setState(() {
      _isAuthorized = true;
      _canUsePrepaidCards = true;
      _canAcceptPrepaidPayments = cached['canAcceptPrepaidPayments'] == true;
      _canUsePrepaidNfc = cached['canUsePrepaidNfc'] == true;
      _canManagePrepaidCards = false;
      _nfcEnabled = cached['nfcEnabled'] == true;
      _isShowingOfflineCards = true;
      _selfServiceMaxCards = 1;
      _selfServiceLimitReached = cards.isNotEmpty;
      _selfServiceCanCreateCard = cards.isEmpty;
      _cards = cards;
      if (_selectedCardId == null ||
          !_cards.any((card) => card['id']?.toString() == _selectedCardId)) {
        _selectedCardId = _cards.first['id']?.toString();
      }
      _isLoading = false;
    });
    return true;
  }

  Future<void> _showReloadCardDialog(Map<String, dynamic> card) async {
    final l = context.loc;
    final amountC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_prepaid_multipay_cards_screen.002')),
        content: TextField(
          controller: amountC,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l.tr('screens_prepaid_multipay_cards_screen.003'),
            prefixIcon: const Icon(Icons.payments_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('shared.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.tr('screens_prepaid_multipay_cards_screen.004')),
          ),
        ],
      ),
    );

    final amount = double.tryParse(amountC.text.trim()) ?? 0;
    amountC.dispose();

    if (confirmed != true || !mounted) {
      return;
    }
    if (amount <= 0) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.005'),
        message: l.tr('screens_prepaid_multipay_cards_screen.006'),
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isReloading = true);
    try {
      final payload = await _api.reloadPrepaidMultipayCard(
        cardId: card['id']?.toString() ?? '',
        amount: amount,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _selectedCardId =
          (payload['card'] as Map?)?['id']?.toString() ??
          card['id']?.toString();
      _cardsPane = 'details';
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.007'),
        message: l.tr(
          'screens_prepaid_multipay_cards_screen.008',
          params: {'amount': CurrencyFormatter.ils(amount)},
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.009'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  Future<void> _showCreateCardDialog() async {
    final l = context.loc;
    if (!_canManagePrepaidCards && !_selfServiceCanCreateCard) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.010'),
        message: l.tr('screens_prepaid_multipay_cards_screen.011'),
      );
      return;
    }

    final labelC = TextEditingController();
    final amountC = TextEditingController();
    final pinC = TextEditingController();
    var selectedValidityYears = 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.tr('screens_prepaid_multipay_cards_screen.012')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelC,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_prepaid_multipay_cards_screen.013',
                    ),
                    prefixIcon: const Icon(Icons.badge_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_prepaid_multipay_cards_screen.014',
                    ),
                    prefixIcon: const Icon(Icons.payments_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinC,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_prepaid_multipay_cards_screen.015',
                    ),
                    prefixIcon: const Icon(Icons.pin_rounded),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selectedValidityYears,
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_prepaid_multipay_cards_screen.016',
                    ),
                    prefixIcon: const Icon(Icons.event_available_rounded),
                  ),
                  items: _validityYearOptions
                      .map(
                        (years) => DropdownMenuItem<int>(
                          value: years,
                          child: Text(_validityYearsLabel(years)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => selectedValidityYears = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l.tr('shared.cancel')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.add_card_rounded),
              label: Text(l.tr('screens_prepaid_multipay_cards_screen.017')),
            ),
          ],
        ),
      ),
    );

    final label = labelC.text.trim();
    final amount = double.tryParse(amountC.text.trim()) ?? 0;
    final pin = pinC.text.trim();
    labelC.dispose();
    amountC.dispose();
    pinC.dispose();

    if (confirmed != true || !mounted) {
      return;
    }

    if (label.isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.018'),
        message: l.tr('screens_prepaid_multipay_cards_screen.019'),
      );
      return;
    }

    if (amount <= 0 || !RegExp(r'^\d{3}$').hasMatch(pin)) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.020'),
        message: l.tr('screens_prepaid_multipay_cards_screen.021'),
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      final payload = await _api.createPrepaidMultipayCard(
        label: label,
        amount: amount,
        pin: pin,
        validityYears: selectedValidityYears,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _selectedCardId = (payload['card'] as Map?)?['id']?.toString();
      _cardsPane = 'details';
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.022'),
        message: l.tr('screens_prepaid_multipay_cards_screen.023'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.024'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _renewCard(Map<String, dynamic> card) async {
    final l = context.loc;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_prepaid_multipay_cards_screen.025')),
        content: Text(l.tr('screens_prepaid_multipay_cards_screen.026')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('shared.back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.tr('screens_prepaid_multipay_cards_screen.027')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      final payload = await _api.renewPrepaidMultipayCard(
        cardId: card['id']?.toString() ?? '',
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _selectedCardId =
          (payload['card'] as Map?)?['id']?.toString() ??
          card['id']?.toString();
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.028'),
        message: l.tr('screens_prepaid_multipay_cards_screen.029'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.030'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> card, String action) async {
    final l = context.loc;
    final actionLabel = switch (action) {
      'freeze' => l.tr('screens_prepaid_multipay_cards_screen.031'),
      'activate' => l.tr('screens_prepaid_multipay_cards_screen.032'),
      'cancel' => l.tr('screens_prepaid_multipay_cards_screen.033'),
      _ => l.tr('screens_prepaid_multipay_cards_screen.034'),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          l.tr(
            'screens_prepaid_multipay_cards_screen.035',
            params: {'action': actionLabel},
          ),
        ),
        content: Text(
          action == 'cancel'
              ? l.tr('screens_prepaid_multipay_cards_screen.036')
              : l.tr('screens_prepaid_multipay_cards_screen.037'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('shared.back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
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

    try {
      final cardId = card['id']?.toString() ?? '';
      if (action == 'cancel') {
        final security = await TransferSecurityService.confirmTransfer(context);
        if (!mounted || !security.isVerified) {
          return;
        }
        await _api.deletePrepaidMultipayCard(
          cardId: cardId,
          otpCode: security.otpCode,
          localAuthMethod: security.method,
        );
      } else {
        await _api.updatePrepaidMultipayCardStatus(
          cardId: cardId,
          action: action,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.038'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _editCardDetails(Map<String, dynamic> card) async {
    final l = context.loc;
    final labelC = TextEditingController(text: card['label']?.toString() ?? '');
    var selectedValidityYears = _validityYearsFromCard(card);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.tr('screens_prepaid_multipay_cards_screen.039')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelC,
                decoration: InputDecoration(
                  labelText: l.tr('screens_prepaid_multipay_cards_screen.013'),
                  prefixIcon: const Icon(Icons.badge_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selectedValidityYears,
                decoration: InputDecoration(
                  labelText: l.tr('screens_prepaid_multipay_cards_screen.016'),
                  prefixIcon: const Icon(Icons.event_available_rounded),
                ),
                items: _validityYearOptions
                    .map(
                      (years) => DropdownMenuItem<int>(
                        value: years,
                        child: Text(_validityYearsLabel(years)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() => selectedValidityYears = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l.tr('shared.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l.tr('shared.save')),
            ),
          ],
        ),
      ),
    );

    final label = labelC.text.trim();
    labelC.dispose();

    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (label.isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.018'),
        message: l.tr('screens_prepaid_multipay_cards_screen.040'),
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      final payload = await _api.updatePrepaidMultipayCard(
        cardId: card['id']?.toString() ?? '',
        label: label,
        validityYears: selectedValidityYears,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _selectedCardId =
          (payload['card'] as Map?)?['id']?.toString() ?? _selectedCardId;
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.041'),
        message: l.tr('screens_prepaid_multipay_cards_screen.042'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_prepaid_multipay_cards_screen.043'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  String _prepaidCardBarcodePayload(Map<String, dynamic> card) {
    final rawNumber = _resolvedRawCardNumber(card);
    return jsonEncode({
      'type': 'prepaid_multipay_card',
      'cardNumber': rawNumber,
      'expiryMonth': (card['expiryMonth'] as num?)?.toInt(),
      'expiryYear': (card['expiryYear'] as num?)?.toInt(),
      'label': card['label']?.toString(),
    });
  }

  Future<void> _ensurePdfFonts() async {
    _pdfRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _pdfBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
    if (_pdfLogoImage == null) {
      final logoBytes = await rootBundle.load(
        'assets/images/shwakel_app_icon.png',
      );
      _pdfLogoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    }
  }

  Future<void> _showCardForDirectPayment(Map<String, dynamic> card) async {
    final canReveal = await _ensureCardRevealed(card);
    if (!canReveal || !mounted) {
      return;
    }

    final rawNumber = _resolvedRawCardNumber(card);
    if (rawNumber.isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'بيانات البطاقة غير متاحة',
        message:
            'تعذر تحميل رقم البطاقة الكامل لهذه البطاقة حاليًا. حدّث الصفحة ثم حاول مرة أخرى.',
      );
      return;
    }

    final balance = (card['balance'] as num?)?.toDouble() ?? 0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بطاقة دفع مسبق جاهزة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVisualCard(card, isLarge: true),
              const SizedBox(height: 12),
              Text(
                'هذه بطاقة دفع مسبق داخل شواكل، مملوكة لصاحبها، ويمكن للتاجر إدخال رقمها مع المبلغ وكود التحقق لاعتماد الدفع.',
                textAlign: TextAlign.center,
                style: AppTheme.caption,
              ),
              const SizedBox(height: 8),
              SelectableText(
                'الرصيد المتاح: ${CurrencyFormatter.ils(balance)}',
                textAlign: TextAlign.center,
                style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openUnifiedScanner(
                initialBarcode: _prepaidCardBarcodePayload(card),
              );
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('فتح شاشة الفحص'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _printPrepaidCard(Map<String, dynamic> card) async {
    final canReveal = await _ensureCardRevealed(card);
    if (!canReveal || !mounted) {
      return;
    }

    final rawNumber = _resolvedRawCardNumber(card);
    if (rawNumber.isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'بيانات البطاقة غير متاحة',
        message:
            'تعذر تحميل رقم البطاقة الكامل للطباعة. حدّث الصفحة ثم حاول مرة أخرى.',
      );
      return;
    }

    try {
      await _ensurePdfFonts();
      final balance = (card['balance'] as num?)?.toDouble() ?? 0;
      final cardNumber = _resolvedDisplayCardNumber(card);
      final label = card['label']?.toString() ?? 'بطاقة دفع مسبق';
      final expiry = card['expiryLabel']?.toString() ?? '-';
      final ownerName = _cardOwnerName();
      final issuerPhone = _cardIssuerLocalPhone();
      final checkUrl = AppConfig.prepaidMultipayCheckUri(rawNumber).toString();
      final logoImage = _pdfLogoImage;
      final pdf = pw.Document();
      final cardWidth = 85.6 * PdfPageFormat.mm;
      final cardHeight = 53.98 * PdfPageFormat.mm;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(8 * PdfPageFormat.mm),
          theme: pw.ThemeData.withFont(
            base: _pdfRegularFont!,
            bold: _pdfBoldFont!,
          ),
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Center(
              child: _buildPrepaidPdfCard(
                width: cardWidth,
                height: cardHeight,
                logoImage: logoImage,
                cardNumber: cardNumber,
                rawNumber: rawNumber,
                label: label,
                balance: balance,
                expiry: expiry,
                ownerName: ownerName,
                issuerPhone: issuerPhone,
                checkUrl: checkUrl,
              ),
            ),
          ),
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'prepaid_multipay_card_${card['id'] ?? ''}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر طباعة البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  pw.Widget _buildPrepaidPdfCard({
    required double width,
    required double height,
    required pw.MemoryImage? logoImage,
    required String cardNumber,
    required String rawNumber,
    required String label,
    required double balance,
    required String expiry,
    required String ownerName,
    required String issuerPhone,
    required String checkUrl,
  }) {
    final labelDirection = _pdfTextDirection(label);
    final ownerDirection = _pdfTextDirection(ownerName);
    final ownerAlignment = ownerDirection == pw.TextDirection.ltr
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;
    final balanceLabel = CurrencyFormatter.ils(balance);
    final normalizedLabel = label.trim().isEmpty ? 'Shwakil Prepaid' : label.trim();

    return pw.Container(
      width: width,
      height: height,
      padding: pw.EdgeInsets.all(5.2 * PdfPageFormat.mm),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF8EC),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFF5EEAD4),
          width: 2,
        ),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            top: -10,
            right: -8,
            child: pw.Container(
              width: 48,
              height: 48,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: const PdfColor.fromInt(0x1A0F766E),
              ),
            ),
          ),
          pw.Positioned(
            bottom: 14,
            right: 16,
            child: pw.Row(
              children: [
                pw.Container(
                  width: 22,
                  height: 22,
                  decoration: const pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: PdfColor.fromInt(0x220F766E),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  width: 22,
                  height: 22,
                  decoration: const pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: PdfColor.fromInt(0x2214B8A6),
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'شواكل',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            font: _pdfBoldFont,
                            fontSize: 12.6,
                            color: const PdfColor.fromInt(0xFF0F766E),
                          ),
                        ),
                        pw.Text(
                          'بطاقة دفع مسبق',
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            font: _pdfBoldFont,
                            fontSize: 7.2,
                            color: const PdfColor.fromInt(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (logoImage != null)
                    pw.Container(
                      width: 24,
                      height: 24,
                      padding: const pw.EdgeInsets.all(2),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(7),
                      ),
                      child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Container(
                    width: 25,
                    height: 18,
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(4),
                      gradient: const pw.LinearGradient(
                        colors: [
                          PdfColor(0.96, 0.84, 0.49),
                          PdfColor(0.78, 0.58, 0.19),
                        ],
                      ),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFFFE4E6),
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFFFB7185),
                        width: 0.5,
                      ),
                    ),
                    child: pw.Text(
                      'بطاقة دفع مسبق',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: _pdfBoldFont,
                        fontSize: 6,
                        color: const PdfColor.fromInt(0xFFBE123C),
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Text(
                  cardNumber,
                  maxLines: 1,
                  style: pw.TextStyle(
                    font: _pdfBoldFont,
                    fontSize: 11.8,
                    color: const PdfColor.fromInt(0xFF047857),
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Directionality(
                textDirection: labelDirection,
                child: pw.Text(
                  normalizedLabel,
                  maxLines: 1,
                  style: pw.TextStyle(
                    font: _pdfBoldFont,
                    fontSize: 7.1,
                    color: const PdfColor.fromInt(0xFF16302B),
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Directionality(
                textDirection: ownerDirection,
                child: pw.Text(
                  ownerName.isEmpty ? 'صاحب البطاقة' : ownerName,
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 6.2,
                    color: PdfColor.fromInt(0xFF64748B),
                  ),
                ),
              ),
              pw.SizedBox(height: 9),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildPrepaidPdfInfoPill(
                      title: 'الرصيد المتاح',
                      value: balanceLabel,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: _buildPrepaidPdfInfoPill(
                      title: 'تاريخ الانتهاء',
                      value: expiry,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 13 * PdfPageFormat.mm,
                    height: 13 * PdfPageFormat.mm,
                    padding: const pw.EdgeInsets.all(2),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: checkUrl,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Container(
                      height: 19 * PdfPageFormat.mm,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(
                          color: const PdfColor.fromInt(0xFF5EEAD4),
                          width: 0.7,
                        ),
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Expanded(
                            child: pw.SvgImage(
                              svg: _prepaidPdfBarcodeSvg(rawNumber),
                            ),
                          ),
                          if (rawNumber.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 1.2),
                            pw.Text(
                              rawNumber.trim(),
                              textDirection: pw.TextDirection.ltr,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                fontSize: 5.0,
                                color: const PdfColor.fromInt(0xFF16302B),
                                font: pw.Font.courierBold(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: ownerAlignment,
                      children: [
                        pw.Text(
                          'شواكل بطاقتك الرقمية الموثقة',
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                          style: pw.TextStyle(
                            font: _pdfBoldFont,
                            fontSize: 6.1,
                            color: const PdfColor.fromInt(0xFF0F766E),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'shwakil.alkmal.com',
                          textDirection: pw.TextDirection.ltr,
                          style: pw.TextStyle(
                            font: pw.Font.helveticaBold(),
                            fontSize: 5.5,
                            color: const PdfColor.fromInt(0xFF16302B),
                          ),
                        ),
                        if (issuerPhone.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'هاتف المصدر: $issuerPhone',
                            textDirection: pw.TextDirection.ltr,
                            style: const pw.TextStyle(
                              fontSize: 5.3,
                              color: PdfColor.fromInt(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    'SH',
                    textDirection: pw.TextDirection.ltr,
                    style: pw.TextStyle(
                      font: _pdfBoldFont,
                      fontSize: 10,
                      color: const PdfColor.fromInt(0xFF0F766E),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPrepaidPdfInfoPill({
    required String title,
    required String value,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFDDF7F1),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFF5EEAD4),
          width: 0.6,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            textDirection: pw.TextDirection.rtl,
            style: const pw.TextStyle(
              fontSize: 5.2,
              color: PdfColor.fromInt(0xFF64748B),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            maxLines: 1,
            textDirection: _pdfTextDirection(value),
            style: pw.TextStyle(
              font: _pdfBoldFont,
              fontSize: 6.7,
              color: const PdfColor.fromInt(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _writeCardToNfc(Map<String, dynamic> card) async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final status = card['status']?.toString() ?? '';
    if (status != 'active') {
      await AppAlertService.showError(
        context,
        title: 'بطاقة غير نشطة',
        message: 'يمكن حفظ البطاقة على وسم للبطاقات النشطة فقط.',
      );
      return;
    }

    final canReveal = await _ensureCardRevealed(card);
    if (!canReveal || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حفظ البطاقة على وسم'),
        content: const Text(
          'قرّب وسمًا فارغًا أو قابلًا للكتابة من الجهاز. لن يتم تخزين الرقم السري للبطاقة داخل الوسم.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('بدء الكتابة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isWritingNfc = true);
    try {
      await _nfc.writeCard(PrepaidMultipayNfcPayload.fromCard(card));
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم حفظ البطاقة',
        message: 'تم حفظ بيانات البطاقة على الوسم بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر حفظ البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isWritingNfc = false);
      }
    }
  }

  String _resolvedRawCardNumber(Map<String, dynamic> card) {
    final rawNumber = card['rawCardNumber']?.toString().trim() ?? '';
    if (rawNumber.isNotEmpty) {
      return rawNumber;
    }

    final formatted = card['cardNumber']?.toString() ?? '';
    return formatted.replaceAll(RegExp(r'\D+'), '');
  }

  String _resolvedDisplayCardNumber(Map<String, dynamic> card) {
    final display = card['cardNumber']?.toString().trim() ?? '';
    if (display.isNotEmpty) {
      return display;
    }

    final raw = _resolvedRawCardNumber(card);
    if (raw.length != 16) {
      return raw;
    }

    return '${raw.substring(0, 4)} ${raw.substring(4, 8)} ${raw.substring(8, 12)} ${raw.substring(12)}';
  }

  Future<void> _activateNfcPayment(Map<String, dynamic> card) async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final status = card['status']?.toString() ?? '';
    if (status != 'active') {
      await AppAlertService.showError(
        context,
        title: 'بطاقة غير نشطة',
        message: 'يمكن تجهيز الدفع بدون تلامس للبطاقات النشطة فقط.',
      );
      return;
    }

    final available = await _nfc.isAvailable();
    if (!mounted) {
      return;
    }
    if (!available) {
      await AppAlertService.showError(
        context,
        title: 'الاتصال القريب غير متاح',
        message: 'فعّل الاتصال القريب على الجهاز ثم حاول مرة أخرى.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تجهيز الدفع بدون تلامس'),
        content: const Text(
          'سيتم ربط هذه البطاقة بهذا الجهاز وإنشاء مفتاح توقيع محفوظ محليًا. البطاقة داخلية لشواكل وليست بطاقة دولية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isRegisteringNfc = true);
    try {
      final cardId = card['id']?.toString() ?? '';
      final keys = await _nfc.getOrCreateSigningKeyPair(cardId);
      final deviceId = await LocalSecurityService.getOrCreateDeviceId();
      final deviceName = await LocalSecurityService.currentDeviceDisplayName();
      final registerResponse = await _api.registerPrepaidMultipayNfcDevice(
        cardId: cardId,
        deviceId: deviceId,
        deviceName: deviceName,
        publicKey: keys['publicKey'] ?? '',
        keyAlgorithm: 'ed25519',
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      final device = Map<String, dynamic>.from(
        registerResponse['device'] as Map? ?? const {},
      );
      final cardRef =
          registerResponse['cardRef']?.toString() ??
          device['cardRef']?.toString() ??
          '';
      if (cardRef.isNotEmpty) {
        await _nfc.savePaymentBinding(
          cardId: cardId,
          deviceId: deviceId,
          cardRef: cardRef,
          lastSequence: (device['lastSequence'] as num?)?.toInt() ?? 0,
        );
      }
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم تجهيز الجهاز',
        message:
            'أصبح هذا الجهاز مخولًا بإنشاء أذونات دفع بدون تلامس لهذه البطاقة.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تجهيز الجهاز',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegisteringNfc = false);
      }
    }
  }

  Future<void> _revokeThisNfcDevice(Map<String, dynamic> card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء ربط الجهاز'),
        content: const Text(
          'سيتم منع هذا الجهاز من إنشاء أذونات دفع بدون تلامس جديدة لهذه البطاقة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء الربط'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isRegisteringNfc = true);
    try {
      final cardId = card['id']?.toString() ?? '';
      final deviceId = await LocalSecurityService.getOrCreateDeviceId();
      await _api.revokePrepaidMultipayNfcDevice(
        cardId: cardId,
        deviceId: deviceId,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      await _nfc.deleteSigningKeyPair(cardId);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم إلغاء الربط',
        message: 'تم إيقاف الدفع بدون تلامس لهذه البطاقة على هذا الجهاز.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر إلغاء ربط الجهاز',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegisteringNfc = false);
      }
    }
  }

  Future<void> _publishHcePaymentAuthorization(
    Map<String, dynamic> card,
  ) async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final status = card['status']?.toString() ?? '';
    if (status != 'active') {
      await AppAlertService.showError(
        context,
        title: 'بطاقة غير نشطة',
        message: 'يمكن تجهيز الدفع بدون تلامس للبطاقات النشطة فقط.',
      );
      return;
    }

    final input = await _showNfcPaymentInput();
    if (!mounted || input == null) {
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isWritingNfcPayment = true);
    try {
      final cardId = card['id']?.toString() ?? '';
      final deviceId = await LocalSecurityService.getOrCreateDeviceId();
      final appVersion = await AppVersionService.currentVersion();
      PrepaidMultipayNfcPaymentAuthorization authorization;
      var preparedOffline = false;
      if (!ConnectivityService.instance.isOnline.value) {
        authorization = await _nfc.buildOfflinePaymentAuthorization(
          cardId: cardId,
          amount: input.amount,
          appVersion: appVersion,
        );
        preparedOffline = true;
      } else {
        try {
          final prepared = await _api.preparePrepaidMultipayNfcPayment(
            cardId: cardId,
            amount: input.amount,
            pin: input.pin,
            deviceId: deviceId,
            appVersion: appVersion,
            otpCode: security.otpCode,
            localAuthMethod: security.method,
          );
          final authorizationPayload = Map<String, dynamic>.from(
            prepared['authorization'] as Map? ?? const {},
          );
          authorization = await _nfc.signAuthorization(
            cardId: cardId,
            authorization: authorizationPayload,
          );
          await _nfc.savePaymentBinding(
            cardId: cardId,
            deviceId: deviceId,
            cardRef: authorizationPayload['cardRef']?.toString() ?? '',
            lastSequence:
                (authorizationPayload['sequence'] as num?)?.toInt() ?? 0,
          );
        } catch (_) {
          if (ConnectivityService.instance.isOnline.value) {
            rethrow;
          }
          authorization = await _nfc.buildOfflinePaymentAuthorization(
            cardId: cardId,
            amount: input.amount,
            appVersion: appVersion,
          );
          preparedOffline = true;
        }
      }
      await _nfc.publishHcePaymentAuthorization(authorization);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: preparedOffline
            ? 'تم تجهيز دفع محفوظ محليًا'
            : 'تم تجهيز دفع بدون تلامس',
        message:
            'قرّب هذا الهاتف من هاتف التاجر قبل ${_formatDateTime(authorization.expiresAt.toLocal())}. يستخدم التاجر اختصار قبول الدفع بدون تلامس.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تجهيز دفع بدون وسم',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isWritingNfcPayment = false);
      }
    }
  }

  Future<bool> _ensureNfcFeatureEnabled() async {
    if (_nfcEnabled) {
      return true;
    }
    await AppAlertService.showError(
      context,
      title: 'الدفع بدون تلامس غير مفعل',
      message: 'الدفع بدون تلامس غير مفعل حاليًا من إعدادات النظام.',
    );
    return false;
  }

  Future<_NfcPaymentInput?> _showNfcPaymentInput() async {
    final amountC = TextEditingController();
    final pinC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('الدفع بدون تلامس'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                prefixIcon: Icon(Icons.payments_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinC,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'كود البطاقة',
                counterText: '',
                prefixIcon: Icon(Icons.pin_rounded),
              ),
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
            child: const Text('تجهيز'),
          ),
        ],
      ),
    );

    final amount = double.tryParse(amountC.text.trim()) ?? 0;
    final pin = pinC.text.trim();
    amountC.dispose();
    pinC.dispose();

    if (confirmed != true) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    if (amount <= 0 || !RegExp(r'^\d{3}$').hasMatch(pin)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات غير مكتملة',
        message: 'أدخل مبلغًا صحيحًا وكود البطاقة من 3 أرقام.',
      );
      return null;
    }
    return _NfcPaymentInput(amount: amount, pin: pin);
  }

  Future<void> _changeSecurityCode(Map<String, dynamic> card) async {
    final currentCodeC = TextEditingController();
    final newCodeC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير الرقم السري'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCodeC,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'الكود الحالي',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCodeC,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'الكود الجديد',
                counterText: '',
              ),
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
            child: const Text('تحديث'),
          ),
        ],
      ),
    );

    final currentCode = currentCodeC.text.trim();
    final newCode = newCodeC.text.trim();
    currentCodeC.dispose();
    newCodeC.dispose();

    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    if (!RegExp(r'^\d{3}$').hasMatch(currentCode) ||
        !RegExp(r'^\d{3}$').hasMatch(newCode)) {
      await AppAlertService.showError(
        context,
        title: 'كود غير صالح',
        message: 'أدخل الكود الحالي والجديد من 3 أرقام.',
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    try {
      await _api.changePrepaidMultipayCardPin(
        cardId: card['id']?.toString() ?? '',
        currentPin: currentCode,
        newPin: newCode,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم تحديث الكود',
        message: 'تم تغيير الرقم السري الخاص بالبطاقة.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تحديث الكود',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<bool> _ensureCardRevealed(Map<String, dynamic> card) async {
    final cardId = card['id']?.toString() ?? '';
    if (cardId.isEmpty) {
      return false;
    }
    if (_revealedCardIds.contains(cardId)) {
      return true;
    }

    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      return false;
    }

    setState(() => _revealedCardIds.add(cardId));
    return true;
  }

  Future<void> _toggleCardNumber(Map<String, dynamic> card) async {
    final cardId = card['id']?.toString() ?? '';
    if (cardId.isEmpty) {
      return;
    }
    if (_revealedCardIds.contains(cardId)) {
      setState(() => _revealedCardIds.remove(cardId));
      return;
    }
    await _ensureCardRevealed(card);
  }

  String _validityYearsLabel(int years) {
    final l = context.loc;
    return switch (years) {
      1 => l.tr('screens_prepaid_multipay_cards_screen.044'),
      2 => l.tr('screens_prepaid_multipay_cards_screen.045'),
      3 => l.tr('screens_prepaid_multipay_cards_screen.046'),
      4 => l.tr('screens_prepaid_multipay_cards_screen.047'),
      5 => l.tr('screens_prepaid_multipay_cards_screen.048'),
      _ => l.tr(
        'screens_prepaid_multipay_cards_screen.049',
        params: {'years': years.toString()},
      ),
    };
  }

  int _validityYearsFromCard(Map<String, dynamic> card) {
    final expiresAt = DateTime.tryParse(card['expiresAt']?.toString() ?? '');
    if (expiresAt == null) {
      return 1;
    }

    final now = DateTime.now();
    var years = expiresAt.year - now.year;
    final anniversary = DateTime(now.year + years, now.month, now.day);
    if (expiresAt.isAfter(anniversary)) {
      years += 1;
    }

    return years.clamp(1, 5).toInt();
  }

  void _openPaymentsTab() {
    if (!_canAcceptPrepaidPayments) {
      return;
    }
    _openUnifiedScanner(openCamera: false);
  }

  void _openUnifiedScanner({bool openCamera = true, String? initialBarcode}) {
    final normalizedInitial = initialBarcode?.trim() ?? '';
    if (normalizedInitial.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/scan-card',
        arguments: {'initialBarcode': normalizedInitial},
      );
      return;
    }

    if (openCamera) {
      Navigator.pushNamed(context, '/scan-card-camera');
      return;
    }

    Navigator.pushNamed(
      context,
      '/scan-card',
      arguments: const {'autoReadNfc': true},
    );
  }

  void _applyInitialAction() {
    if (_didApplyInitialAction || !mounted) {
      return;
    }
    _didApplyInitialAction = true;
    if (!widget.openPaymentsTab && !widget.autoAcceptNfc) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canAcceptPrepaidPayments) {
        return;
      }
      if (widget.autoAcceptNfc) {
        _openUnifiedScanner(openCamera: false);
        return;
      }
      _openPaymentsTab();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAnySection = _canUsePrepaidCards || _canAcceptPrepaidPayments;
    final l = context.loc;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_prepaid_multipay_cards_screen.050')),
        actions: [
          if (_canUsePrepaidCards &&
              !_isLoading &&
              !_isShowingOfflineCards &&
              _selfServiceCanCreateCard)
            IconButton(
              onPressed: _showCreateCardDialog,
              tooltip: l.tr('screens_prepaid_multipay_cards_screen.017'),
              icon: const Icon(Icons.add_card_rounded),
            ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: ResponsiveScaffoldContainer(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !_isAuthorized || !hasAnySection
            ? _buildUnauthorized()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isShowingOfflineCards) ...[
                    _offlineAccessBanner(),
                    const SizedBox(height: 16),
                  ],
                  Expanded(child: _buildCardsTab()),
                ],
              ),
      ),
    );
  }

  Widget _buildCardsTab() {
    final selected = _selectedCard;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_cardsPane == 'details' && selected != null)
            _buildCardDetailsPane(selected)
          else
            _buildCardsListPane(),
        ],
      ),
    );
  }

  Widget _buildCardsListPane() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.tr('screens_prepaid_multipay_cards_screen.051'),
                style: AppTheme.h2,
              ),
            ),
            if (_canUsePrepaidCards &&
                !_isShowingOfflineCards &&
                _selfServiceCanCreateCard)
              FilledButton.icon(
                onPressed: _showCreateCardDialog,
                icon: const Icon(Icons.add_card_rounded),
                label: Text(l.tr('screens_prepaid_multipay_cards_screen.017')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l.tr('screens_prepaid_multipay_cards_screen.052'),
          style: AppTheme.bodyAction,
        ),
        if (!_canManagePrepaidCards && _selfServiceLimitReached) ...[
          const SizedBox(height: 8),
          Text(
            l.tr(
              'screens_prepaid_multipay_cards_screen.053',
              params: {
                'limit': _selfServiceMaxCards == 1
                    ? l.tr('screens_prepaid_multipay_cards_screen.054')
                    : l.tr('screens_prepaid_multipay_cards_screen.055'),
              },
            ),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        if (_cards.isEmpty)
          _buildEmpty()
        else
          ..._cards.map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCardListItem(card),
            ),
          ),
      ],
    );
  }

  Widget _buildCardDetailsPane(Map<String, dynamic> card) {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.tr('shared.back'),
              onPressed: () => setState(() {
                _cardsPane = 'list';
                _activityFilter = 'all';
                _showCardTechnicalDetails = false;
              }),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card['label']?.toString() ??
                    l.tr('screens_prepaid_multipay_cards_screen.056'),
                style: AppTheme.h2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSelectedCardDetails(card),
      ],
    );
  }

  Widget _offlineAccessBanner() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.warning.withValues(alpha: 0.08),
      borderColor: AppTheme.warning.withValues(alpha: 0.22),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_rounded, color: AppTheme.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.tr('screens_prepaid_multipay_cards_screen.057'),
              style: AppTheme.bodyAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardListItem(Map<String, dynamic> card) {
    final isSelected = card['id']?.toString() == _selectedCardId;
    final status = card['status']?.toString() ?? 'active';

    return ShwakelCard(
      onTap: () => setState(() {
        _selectedCardId = card['id']?.toString();
        _activityFilter = 'all';
        _showCardTechnicalDetails = false;
        _cardsPane = 'details';
      }),
      color: isSelected ? AppTheme.surfaceMuted : Colors.white,
      borderColor: isSelected ? AppTheme.primary : AppTheme.border,
      borderWidth: isSelected ? 1.4 : 0.8,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.credit_card_rounded, color: _statusColor(status)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card['label']?.toString() ?? '', style: AppTheme.bodyBold),
                const SizedBox(height: 4),
                Text(
                  '${card['cardNumber'] ?? '-'}  |  ${card['expiryLabel'] ?? '-'}',
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _cardChip(
                      Icons.account_balance_wallet_rounded,
                      CurrencyFormatter.ils(
                        (card['balance'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    _cardChip(
                      Icons.info_rounded,
                      _statusLabel(status),
                      color: _statusColor(status),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_left_rounded, color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _buildSelectedCardDetails(Map<String, dynamic> card) {
    final l = context.loc;
    final status = card['status']?.toString() ?? 'active';
    final canEditCard =
        _canUsePrepaidCards &&
        (status == 'pending_approval' ||
            status == 'active' ||
            status == 'frozen');
    final canManageLifecycle =
        _canManagePrepaidCards &&
        status != 'cancelled' &&
        status != 'expired' &&
        status != 'rejected';
    final canShowForDirectPayment = _canUsePrepaidCards && status == 'active';
    final canPrintCard =
        _canUsePrepaidCards && (status == 'active' || status == 'frozen');
    final canUseForPayment = _canAcceptPrepaidPayments && status == 'active';
    final canReload =
        _canUsePrepaidCards && (status == 'active' || status == 'frozen');
    final canRenew = _canUsePrepaidCards && status == 'expired';
    final payments = List<Map<String, dynamic>>.from(
      (card['payments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final activity = List<Map<String, dynamic>>.from(
      (card['activity'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final filteredActivity = activity.where(_matchesActivityFilter).toList();
    final showNfcActions = _nfcEnabled && _canUsePrepaidNfc;
    final showActivationGuide = status == 'active' && showNfcActions;
    final showAdvancedNfcTools = _canManagePrepaidCards && showNfcActions;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canUsePrepaidCards &&
              (status == 'active' || status == 'frozen')) ...[
            _buildVisualCard(card),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoPill(
                l.tr('screens_prepaid_multipay_cards_screen.058'),
                CurrencyFormatter.ils(
                  (card['balance'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill(
                l.tr('screens_prepaid_multipay_cards_screen.059'),
                CurrencyFormatter.ils(
                  (card['loadedAmount'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill(
                l.tr('screens_prepaid_multipay_cards_screen.060'),
                CurrencyFormatter.ils(
                  (card['spentAmount'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill(
                l.tr('screens_prepaid_multipay_cards_screen.061'),
                _statusLabel(status),
              ),
              _infoPill(
                l.tr('screens_prepaid_multipay_cards_screen.062'),
                '${CurrencyFormatter.ils(((card['dailyUsage'] as Map?)?['amount'] as num?)?.toDouble() ?? 0)} / ${CurrencyFormatter.ils(((card['dailyUsage'] as Map?)?['amountLimit'] as num?)?.toDouble() ?? 0)}',
              ),
            ],
          ),
          _buildCardWarnings(card),
          const SizedBox(height: 16),
          if (showActivationGuide) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.infoLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tr('screens_prepaid_multipay_cards_screen.063'),
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.tr('screens_prepaid_multipay_cards_screen.064'),
                    style: AppTheme.bodyAction,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isRegisteringNfc
                        ? null
                        : () => _activateNfcPayment(card),
                    icon: const Icon(Icons.phonelink_lock_rounded),
                    label: Text(
                      _isRegisteringNfc
                          ? l.tr('screens_prepaid_multipay_cards_screen.065')
                          : l.tr('screens_prepaid_multipay_cards_screen.063'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _toggleCardNumber(card),
                icon: Icon(
                  _revealedCardIds.contains(card['id']?.toString() ?? '')
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                label: Text(
                  _revealedCardIds.contains(card['id']?.toString() ?? '')
                      ? l.tr('screens_prepaid_multipay_cards_screen.066')
                      : l.tr('screens_prepaid_multipay_cards_screen.067'),
                ),
              ),
              if (canShowForDirectPayment)
                OutlinedButton.icon(
                  onPressed: () => _showCardForDirectPayment(card),
                  icon: const Icon(Icons.smartphone_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.068')),
                ),
              if (canPrintCard)
                OutlinedButton.icon(
                  onPressed: () => _printPrepaidCard(card),
                  icon: const Icon(Icons.print_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.069')),
                ),
              if (status == 'active' && showNfcActions)
                FilledButton.icon(
                  onPressed: _isWritingNfcPayment
                      ? null
                      : () => _publishHcePaymentAuthorization(card),
                  icon: const Icon(Icons.contactless_rounded),
                  label: Text(
                    _isWritingNfcPayment
                        ? l.tr('screens_prepaid_multipay_cards_screen.070')
                        : l.tr('screens_prepaid_multipay_cards_screen.071'),
                  ),
                ),
              if (status == 'active' && showAdvancedNfcTools)
                OutlinedButton.icon(
                  onPressed: _isWritingNfc ? null : () => _writeCardToNfc(card),
                  icon: const Icon(Icons.sensors_rounded),
                  label: Text(
                    _isWritingNfc
                        ? l.tr('screens_prepaid_multipay_cards_screen.072')
                        : l.tr('screens_prepaid_multipay_cards_screen.073'),
                  ),
                ),
              if (showAdvancedNfcTools)
                OutlinedButton.icon(
                  onPressed: _isRegisteringNfc
                      ? null
                      : () => _revokeThisNfcDevice(card),
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.074')),
                ),
              if (canUseForPayment)
                FilledButton.icon(
                  onPressed: () => _openUnifiedScanner(openCamera: false),
                  icon: const Icon(Icons.contactless_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.075')),
                ),
              if (canUseForPayment)
                OutlinedButton.icon(
                  onPressed: () => _openUnifiedScanner(),
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.076')),
                ),
              if (canReload)
                OutlinedButton.icon(
                  onPressed: _isReloading
                      ? null
                      : () => _showReloadCardDialog(card),
                  icon: const Icon(Icons.add_card_rounded),
                  label: Text(
                    _isReloading
                        ? l.tr('screens_prepaid_multipay_cards_screen.077')
                        : l.tr('screens_prepaid_multipay_cards_screen.002'),
                  ),
                ),
              if (canRenew)
                FilledButton.icon(
                  onPressed: () => _renewCard(card),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.027')),
                ),
              if (canEditCard)
                OutlinedButton.icon(
                  onPressed: () => _editCardDetails(card),
                  icon: const Icon(Icons.edit_rounded),
                  label: Text(l.tr('screens_prepaid_multipay_cards_screen.039')),
                ),
            ],
          ),
          if (canManageLifecycle) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'active')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'freeze'),
                    icon: const Icon(Icons.pause_circle_rounded),
                    label: Text(l.tr('screens_prepaid_multipay_cards_screen.031')),
                  ),
                if (status == 'frozen')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'activate'),
                    icon: const Icon(Icons.play_circle_rounded),
                    label: Text(l.tr('screens_prepaid_multipay_cards_screen.032')),
                  ),
                if (status == 'active' || status == 'frozen')
                  OutlinedButton.icon(
                    onPressed: () => _changeSecurityCode(card),
                    icon: const Icon(Icons.password_rounded),
                    label: Text(l.tr('screens_prepaid_multipay_cards_screen.078')),
                  ),
              ],
            ),
          ],
          if (_canManagePrepaidCards) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => setState(
                () => _showCardTechnicalDetails = !_showCardTechnicalDetails,
              ),
              icon: Icon(
                _showCardTechnicalDetails
                    ? Icons.expand_less_rounded
                    : Icons.info_outline_rounded,
              ),
              label: Text(
                _showCardTechnicalDetails
                    ? l.tr('screens_prepaid_multipay_cards_screen.079')
                    : l.tr('screens_prepaid_multipay_cards_screen.056'),
              ),
            ),
            if (_showCardTechnicalDetails) ...[
              const SizedBox(height: 10),
              _detailsGrid(card),
              const SizedBox(height: 18),
            ] else
              const SizedBox(height: 18),
          ] else
            const SizedBox(height: 18),
          Text(l.tr('screens_prepaid_multipay_cards_screen.080'), style: AppTheme.h3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _activityChip('all', l.tr('screens_prepaid_multipay_cards_screen.081')),
              _activityChip('payments', l.tr('screens_prepaid_multipay_cards_screen.082')),
              _activityChip('reloads', l.tr('screens_prepaid_multipay_cards_screen.004')),
              _activityChip('status', l.tr('screens_prepaid_multipay_cards_screen.061')),
              _activityChip('security', l.tr('screens_prepaid_multipay_cards_screen.083')),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredActivity.isEmpty)
            Text(
              l.tr('screens_prepaid_multipay_cards_screen.084'),
              style: AppTheme.bodyAction,
            )
          else
            ...filteredActivity.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCardActivityRow(item),
              ),
            ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(l.tr('screens_prepaid_multipay_cards_screen.085'), style: AppTheme.h3),
            const SizedBox(height: 12),
            ...payments.map(
              (payment) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCardPaymentRow(payment),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailsGrid(Map<String, dynamic> card) {
    final details = <MapEntry<String, String>>[
      MapEntry('رقم البطاقة', card['cardNumber']?.toString() ?? '-'),
      MapEntry('الانتهاء', card['expiryLabel']?.toString() ?? '-'),
      MapEntry(
        'تاريخ الإنشاء',
        _formatDateTime(DateTime.tryParse(card['createdAt']?.toString() ?? '')),
      ),
      MapEntry(
        'حد العدد اليومي',
        '${((card['dailyUsage'] as Map?)?['count'] as num?)?.toInt() ?? 0} / ${((card['dailyUsage'] as Map?)?['countLimit'] as num?)?.toInt() ?? 0}',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: details
          .map(
            (detail) => SizedBox(
              width: 220,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.key, style: AppTheme.caption),
                    const SizedBox(height: 6),
                    Text(detail.value, style: AppTheme.bodyBold),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildVisualCard(Map<String, dynamic> card, {bool isLarge = false}) {
    final cardId = card['id']?.toString() ?? '';
    final isRevealed = _revealedCardIds.contains(cardId);
    final rawNumber = _resolvedRawCardNumber(card);
    final displayNumber = isRevealed
        ? card['cardNumber']?.toString() ?? ''
        : '•••• •••• •••• ••••';
    final ownerName = _cardOwnerName();
    final issuerPhone = _cardIssuerLocalPhone();
    final label = card['label']?.toString().trim() ?? '';
    final expiry = card['expiryLabel']?.toString().trim() ?? '-';
    final balanceLabel = CurrencyFormatter.ils(
      (card['balance'] as num?)?.toDouble() ?? 0,
    );
    final barcodeData = rawNumber.isNotEmpty
        ? rawNumber
        : _prepaidCardBarcodePayload(card);
    final normalizedLabel = label.isEmpty ? 'Shwakil Prepaid' : label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _toggleCardNumber(card),
        child: Ink(
          width: double.infinity,
          padding: EdgeInsets.all(isLarge ? 22 : 18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EC),
            border: Border.all(color: const Color(0xFF5EEAD4), width: 2),
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.mediumShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                top: -20,
                right: -12,
                child: Container(
                  width: isLarge ? 92 : 76,
                  height: isLarge ? 92 : 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                right: 14,
                child: Row(
                  children: [
                    Container(
                      width: isLarge ? 30 : 24,
                      height: isLarge ? 30 : 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF97316),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: isLarge ? 30 : 24,
                      height: isLarge ? 30 : 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFBBF24),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                              'شواكل',
                              style: AppTheme.h3.copyWith(
                                color: const Color(0xFF0F766E),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'بطاقة دفع مسبق',
                              style: AppTheme.caption.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: isLarge ? 46 : 38,
                        height: isLarge ? 46 : 38,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/images/shwakel_app_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: isLarge ? 34 : 28,
                        height: isLarge ? 24 : 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEFD79F), Color(0xFFAF8736)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE4E6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFFFB7185),
                          ),
                        ),
                        child: Text(
                          _statusLabel(card['status']?.toString() ?? 'active'),
                          style: AppTheme.caption.copyWith(
                            color: const Color(0xFFBE123C),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isLarge ? 18 : 14),
                  Text(
                    displayNumber,
                    textDirection: TextDirection.ltr,
                    style: AppTheme.h2.copyWith(
                      color: const Color(0xFF047857),
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    normalizedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyBold.copyWith(
                      color: const Color(0xFF16302B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ownerName.isEmpty ? 'صاحب البطاقة' : ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(height: isLarge ? 20 : 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPrepaidInfoPill(
                          title: 'الرصيد المتاح',
                          value: balanceLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildPrepaidInfoPill(
                          title: 'تاريخ الانتهاء',
                          value: expiry,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: isLarge ? 96 : 82,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF5EEAD4)),
                    ),
                    child: isRevealed
                        ? bw.BarcodeWidget(
                            barcode: bw.Barcode.code128(),
                            data: barcodeData,
                            drawText: false,
                          )
                        : Icon(
                            Icons.barcode_reader,
                            color: AppTheme.textTertiary.withValues(alpha: 0.45),
                            size: isLarge ? 58 : 46,
                          ),
                  ),
                  if (!isRevealed) ...[
                    const SizedBox(height: 8),
                    Text(
                        rawNumber.isNotEmpty
                          ? 'اضغط على البطاقة لإظهار الباركود'
                          : 'اضغط على البطاقة لإظهار بيانات الدفع',
                      style: AppTheme.caption.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ] else if (rawNumber.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      rawNumber,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(
                        color: const Color(0xFF16302B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'شواكل بطاقتك الرقمية الموثقة',
                              style: AppTheme.caption.copyWith(
                                color: const Color(0xFF0F766E),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'shwakil.alkmal.com',
                              textDirection: TextDirection.ltr,
                              style: AppTheme.caption.copyWith(
                                color: const Color(0xFF16302B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (issuerPhone.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'هاتف المصدر: $issuerPhone',
                                textDirection: TextDirection.ltr,
                                style: AppTheme.caption.copyWith(
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        'SH',
                        style: AppTheme.bodyBold.copyWith(
                          color: const Color(0xFF0F766E),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrepaidInfoPill({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDDF7F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5EEAD4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.caption.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyBold.copyWith(color: const Color(0xFF0F766E)),
          ),
        ],
      ),
    );
  }

  String _cardOwnerName() {
    return UserDisplayName.fromMap(AuthService.peekCurrentUser());
  }

  String _cardIssuerLocalPhone() {
    final raw = AuthService.peekCurrentUser()?['whatsapp']?.toString() ?? '';
    var digits = raw.replaceAll(RegExp(r'\D+'), '');
    if (digits.startsWith('970') && digits.length > 9) {
      digits = digits.substring(3);
    } else if (digits.startsWith('972') && digits.length > 9) {
      digits = '0${digits.substring(3)}';
    }
    if (digits.length == 9 && digits.startsWith('5')) {
      digits = '0$digits';
    }
    return digits;
  }

  pw.TextDirection _pdfTextDirection(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value)
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;
  }

  String _prepaidPdfBarcodeSvg(String rawNumber) {
    final normalized = rawNumber.replaceAll(RegExp(r'\D+'), '');
    final generator = barcode.Barcode.code128();
    return generator.toSvg(normalized, width: 180, height: 54, drawText: false);
  }

  Widget _buildCardWarnings(Map<String, dynamic> card) {
    final warnings = List<String>.from(
      (card['warnings'] as List? ?? const []).map((item) => item.toString()),
    );
    if (warnings.isEmpty) {
      return const SizedBox.shrink();
    }

    final labels = warnings.map((warning) {
      return switch (warning) {
        'awaiting_admin_approval' => 'بانتظار موافقة الإدارة',
        'expiring_soon' => 'قرب انتهاء البطاقة',
        'daily_amount_near_limit' => 'قرب حد المبلغ اليومي',
        'daily_count_near_limit' => 'قرب حد عدد العمليات',
        _ => warning,
      };
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: labels
            .map(
              (label) => _cardChip(
                Icons.warning_amber_rounded,
                label,
                color: AppTheme.warning,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCardPaymentRow(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
    final note = payment['note']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.isEmpty ? 'دفع بطاقة مسبقة' : note,
                  style: AppTheme.bodyBold,
                ),
                Text(
                  _formatDateTime(
                    DateTime.tryParse(payment['createdAt']?.toString() ?? ''),
                  ),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          Text(CurrencyFormatter.ils(amount), style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _buildCardActivityRow(Map<String, dynamic> item) {
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final label = item['label']?.toString() ?? item['type']?.toString() ?? '-';
    final note = item['note']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    final color = switch (type) {
      'prepaid_multipay_approve' => AppTheme.info,
      'prepaid_multipay_reload' => AppTheme.success,
      'prepaid_multipay_update' => AppTheme.info,
      'prepaid_multipay_renew' => AppTheme.success,
      'prepaid_multipay_reject_refund' => AppTheme.error,
      'prepaid_multipay_refund' => AppTheme.warning,
      'prepaid_multipay_freeze' => AppTheme.warning,
      'prepaid_multipay_activate' => AppTheme.info,
      'prepaid_multipay_cancel' => AppTheme.error,
      'prepaid_multipay_payment_out' => AppTheme.primary,
      _ => AppTheme.textPrimary,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.timeline_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodyBold),
                if (note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                Text(
                  _formatDateTime(
                    DateTime.tryParse(item['createdAt']?.toString() ?? ''),
                  ),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          Text(
            amount == 0 ? '-' : CurrencyFormatter.ils(amount),
            style: AppTheme.bodyBold.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _activityChip(String value, String label) {
    final selected = _activityFilter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _activityFilter = value),
      selectedColor: AppTheme.primary.withValues(alpha: 0.16),
      labelStyle: AppTheme.caption.copyWith(
        color: selected ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  bool _matchesActivityFilter(Map<String, dynamic> item) {
    if (_activityFilter == 'all') {
      return true;
    }

    final type = item['type']?.toString() ?? '';

    return switch (_activityFilter) {
      'payments' => type.contains('payment'),
      'reloads' =>
        type == 'prepaid_multipay_reload' ||
            type == 'prepaid_multipay_create' ||
            type == 'prepaid_multipay_reject_refund' ||
            type == 'prepaid_multipay_refund',
      'status' =>
        type == 'prepaid_multipay_approve' ||
            type == 'prepaid_multipay_update' ||
            type == 'prepaid_multipay_renew' ||
            type == 'prepaid_multipay_freeze' ||
            type == 'prepaid_multipay_activate' ||
            type == 'prepaid_multipay_cancel',
      'security' => type == 'prepaid_multipay_pin_change',
      _ => true,
    };
  }

  Widget _infoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _cardChip(IconData icon, String label, {Color? color}) {
    final resolvedColor = color ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: resolvedColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: resolvedColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'لا توجد بطاقات مسبقة حتى الآن.',
          style: AppTheme.bodyAction,
        ),
      ),
    );
  }

  Widget _buildUnauthorized() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'بطاقات الدفع المسبق غير مفعلة لحسابك.',
          style: AppTheme.bodyAction,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'pending_approval' => AppTheme.warning,
      'active' => AppTheme.success,
      'frozen' => AppTheme.warning,
      'spent' => AppTheme.primary,
      'cancelled' => AppTheme.error,
      'rejected' => AppTheme.error,
      'expired' => AppTheme.textTertiary,
      _ => AppTheme.primary,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending_approval' => 'بانتظار الموافقة',
      'active' => 'نشطة',
      'frozen' => 'مجمدة',
      'spent' => 'مستهلكة',
      'cancelled' => 'ملغاة',
      'rejected' => 'مرفوضة',
      'expired' => 'منتهية',
      _ => status,
    };
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _NfcPaymentInput {
  const _NfcPaymentInput({required this.amount, required this.pin});

  final double amount;
  final String pin;
}
