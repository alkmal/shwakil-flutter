import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
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
  final _labelC = TextEditingController();
  final _amountC = TextEditingController();
  final _codeC = TextEditingController();
  final _payCardNumberC = TextEditingController();
  final _payAmountC = TextEditingController();
  final _payMonthC = TextEditingController();
  final _payYearC = TextEditingController();
  final _payCodeC = TextEditingController();
  final _payNoteC = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isReloading = false;
  bool _isAcceptingPayment = false;
  bool _isRegisteringNfc = false;
  bool _isWritingNfc = false;
  bool _isWritingNfcPayment = false;
  bool _isReadingNfc = false;
  bool _isAcceptingNfcPayment = false;
  bool _isAuthorized = true;
  bool _canUsePrepaidCards = false;
  bool _canAcceptPrepaidPayments = false;
  bool _canUsePrepaidNfc = false;
  bool _nfcEnabled = false;
  static const List<int> _validityYearOptions = [1, 2, 3, 4, 5];
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _payments = const [];
  Map<String, dynamic> _summary = const {};
  final Set<String> _revealedCardIds = <String>{};
  int _validityYears = 1;
  String? _selectedCardId;
  String _activityFilter = 'all';
  String _cardsPane = 'list';
  String _activeSection = 'cards';
  bool _showCardTechnicalDetails = false;
  bool _didApplyInitialAction = false;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelC.dispose();
    _amountC.dispose();
    _codeC.dispose();
    _payCardNumberC.dispose();
    _payAmountC.dispose();
    _payMonthC.dispose();
    _payYearC.dispose();
    _payCodeC.dispose();
    _payNoteC.dispose();
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

      if (!permissions.canOpenPrepaidMultipayCards) {
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
        _nfcEnabled =
            ((payload['settings'] as Map?)?['nfc'] as Map?)?['enabled'] == true;
        _cards = cards;
        _payments = payments;
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
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
        if (!_canUsePrepaidCards && _canAcceptPrepaidPayments) {
          _activeSection = 'payments';
        } else if (_canUsePrepaidCards && !_canAcceptPrepaidPayments) {
          _activeSection = 'cards';
        }
      });
      _applyInitialAction();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل البطاقات',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _create() async {
    final label = _labelC.text.trim();
    final amount = double.tryParse(_amountC.text.trim()) ?? 0;
    final code = _codeC.text.trim();

    if (label.isEmpty || amount <= 0 || !RegExp(r'^\d{3}$').hasMatch(code)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات البطاقة غير مكتملة',
        message: 'أدخل اسم البطاقة، مبلغًا صحيحًا، وكود أمان من 3 أرقام.',
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final payload = await _api.createPrepaidMultipayCard(
        label: label,
        amount: amount,
        pin: code,
        validityYears: _validityYears,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _labelC.clear();
      _amountC.clear();
      _codeC.clear();
      _validityYears = 1;
      _selectedCardId = (payload['card'] as Map?)?['id']?.toString();
      _cardsPane = 'details';
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم إنشاء البطاقة',
        message:
            'تم إنشاء البطاقة وحجز الرصيد فيها، وهي الآن بانتظار موافقة الإدارة قبل التفعيل.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر إنشاء البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showReloadCardDialog(Map<String, dynamic> card) async {
    final amountC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('شحن البطاقة'),
        content: TextField(
          controller: amountC,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'مبلغ الشحن',
            prefixIcon: Icon(Icons.payments_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('شحن'),
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
        title: 'مبلغ غير صالح',
        message: 'أدخل مبلغ شحن أكبر من صفر.',
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
        title: 'تم شحن البطاقة',
        message:
            'تمت إضافة ${CurrencyFormatter.ils(amount)} إلى البطاقة المحددة.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر شحن البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  Future<void> _renewCard(Map<String, dynamic> card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تجديد البطاقة'),
        content: const Text(
          'سيتم تجديد البطاقة لمدة سنة واحدة من تاريخ اليوم وإشعار الإدارة بعملية التجديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تجديد سنة'),
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
        title: 'تم تجديد البطاقة',
        message: 'تم تمديد صلاحية البطاقة سنة واحدة وإشعار الإدارة.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تجديد البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> card, String action) async {
    final actionLabel = switch (action) {
      'freeze' => 'تجميد',
      'activate' => 'تفعيل',
      'cancel' => 'إلغاء',
      _ => 'تحديث',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$actionLabel البطاقة'),
        content: Text(
          action == 'cancel'
              ? 'سيتم إلغاء البطاقة وإرجاع الرصيد المتبقي إلى حسابك.'
              : 'هل تريد تنفيذ هذا الإجراء الآن؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
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
        title: 'تعذر تحديث البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _editCardDetails(Map<String, dynamic> card) async {
    final labelC = TextEditingController(text: card['label']?.toString() ?? '');
    var selectedValidityYears = _validityYearsFromCard(card);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('تعديل البطاقة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelC,
                decoration: const InputDecoration(
                  labelText: 'اسم البطاقة',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selectedValidityYears,
                decoration: const InputDecoration(
                  labelText: 'مدة البطاقة',
                  prefixIcon: Icon(Icons.event_available_rounded),
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
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
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
        title: 'اسم البطاقة مطلوب',
        message: 'أدخل اسمًا واضحًا للبطاقة قبل الحفظ.',
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
        title: 'تم تعديل البطاقة',
        message: 'تم حفظ اسم البطاقة ومدة الصلاحية.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تعديل البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _acceptPayment() async {
    final cardNumber = _payCardNumberC.text.trim();
    final amount = double.tryParse(_payAmountC.text.trim()) ?? 0;
    final month = _payMonthC.text.trim();
    final year = _payYearC.text.trim();
    final code = _payCodeC.text.trim();

    if (cardNumber.isEmpty ||
        amount <= 0 ||
        !RegExp(r'^\d{1,2}$').hasMatch(month) ||
        !RegExp(r'^\d{2,4}$').hasMatch(year) ||
        !RegExp(r'^\d{3}$').hasMatch(code)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات الدفع غير مكتملة',
        message:
            'أدخل رقم البطاقة ومبلغ الدفع وتاريخ الانتهاء وكود التحقق من 3 أرقام.',
      );
      return;
    }

    setState(() => _isAcceptingPayment = true);
    try {
      final payload = await _api.acceptPrepaidMultipayCardPayment(
        cardNumber: cardNumber,
        amount: amount,
        expiryMonth: month,
        expiryYear: year,
        securityCode: code,
        note: _payNoteC.text,
        idempotencyKey: _newPaymentKey(),
      );
      _payAmountC.clear();
      _payCodeC.clear();
      _payNoteC.clear();
      await _load();
      if (!mounted) {
        return;
      }
      final payment = Map<String, dynamic>.from(
        payload['payment'] as Map? ?? const {},
      );
      final remaining = (payment['remainingCardBalance'] as num?)?.toDouble();
      await AppAlertService.showSuccess(
        context,
        title: 'تم اعتماد الدفع',
        message: remaining == null
            ? 'تمت العملية بنجاح.'
            : 'تم اعتماد دفع ${CurrencyFormatter.ils(amount)} من البطاقة. المتبقي في البطاقة ${CurrencyFormatter.ils(remaining)}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر اعتماد الدفع',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isAcceptingPayment = false);
      }
    }
  }

  Future<void> _scanPaymentCard() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const BarcodeScannerDialog(
        title: 'مسح بطاقة دفع مسبق',
        description: 'وجّه الكاميرا إلى QR البطاقة أو رقمها.',
        showFrame: true,
        onCancelLabel: 'إغلاق',
      ),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) {
      return;
    }

    final cardNumber = _extractCardNumber(scanned);
    if (cardNumber.isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'رمز غير صالح',
        message: 'لم يتم العثور على رقم بطاقة مسبقة صالح داخل الرمز.',
      );
      return;
    }

    setState(() => _payCardNumberC.text = cardNumber);
  }

  void _fillPaymentFromSelectedCard() {
    final card = _selectedCard;
    if (card == null) {
      return;
    }
    setState(() {
      _payCardNumberC.text = card['rawCardNumber']?.toString() ?? '';
      _payMonthC.text = ((card['expiryMonth'] as num?)?.toInt() ?? 0)
          .toString()
          .padLeft(2, '0');
      _payYearC.text = (((card['expiryYear'] as num?)?.toInt() ?? 0) % 100)
          .toString()
          .padLeft(2, '0');
    });
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
      final barcodePayload = _prepaidCardBarcodePayload(card);
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a6,
          margin: const pw.EdgeInsets.all(18),
          theme: pw.ThemeData.withFont(
            base: _pdfRegularFont!,
            bold: _pdfBoldFont!,
          ),
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.teal700, width: 1.5),
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    'شواكل',
                    style: pw.TextStyle(
                      font: _pdfBoldFont,
                      fontSize: 18,
                      color: PdfColors.teal800,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'بطاقة دفع مسبق',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    label,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: _pdfBoldFont, fontSize: 13),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Text(
                    cardNumber,
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.ltr,
                    style: pw.TextStyle(font: _pdfBoldFont, fontSize: 15),
                  ),
                  pw.SizedBox(height: 10),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: barcodePayload,
                    width: 210,
                    height: 42,
                    drawText: false,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'باركود بطاقة دفع مسبق',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('الصلاحية: $expiry'),
                  pw.Text('الرصيد: ${CurrencyFormatter.ils(balance)}'),
                  if (ownerName.isNotEmpty) pw.Text('ملك: $ownerName'),
                  if (issuerPhone.isNotEmpty)
                    pw.Text('هاتف المصدر: $issuerPhone'),
                  pw.Spacer(),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'هذه البطاقة ملك لصاحبها وتستخدم كدفع مسبق داخل شواكل. لا تشارك كود التحقق مع أي جهة غير موثوقة.',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
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
        message: 'يمكن كتابة بطاقة NFC للبطاقات النشطة فقط.',
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
        title: const Text('كتابة NFC'),
        content: const Text(
          'قرّب وسم NFC فارغ أو قابل للكتابة من الجهاز. لن يتم تخزين الرقم السري للبطاقة داخل الوسم.',
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
        title: 'تمت كتابة NFC',
        message: 'تم حفظ بيانات البطاقة على وسم NFC بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر كتابة NFC',
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

  Future<void> _readPaymentCardFromNfc() async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _isReadingNfc = true);
    try {
      final payload = await _nfc.readCard();
      if (!mounted) {
        return;
      }
      setState(() {
        _payCardNumberC.text = payload.cardNumber;
        _payMonthC.text = payload.expiryMonth.toString().padLeft(2, '0');
        _payYearC.text = (payload.expiryYear % 100).toString().padLeft(2, '0');
      });
      await AppAlertService.showSuccess(
        context,
        title: 'تمت قراءة NFC',
        message:
            'تم تعبئة بيانات البطاقة. أدخل مبلغ الدفع وكود التحقق لإكمال الاعتماد.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر قراءة NFC',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isReadingNfc = false);
      }
    }
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
        message: 'يمكن تفعيل دفع NFC للبطاقات النشطة فقط.',
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
        title: 'NFC غير متاح',
        message: 'فعّل NFC على الجهاز ثم حاول مرة أخرى.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تفعيل دفع NFC'),
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
      await _api.registerPrepaidMultipayNfcDevice(
        cardId: cardId,
        deviceId: deviceId,
        deviceName: deviceName,
        publicKey: keys['publicKey'] ?? '',
        keyAlgorithm: 'ed25519',
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم تفعيل NFC',
        message: 'أصبح هذا الجهاز مخولًا بإنشاء أذونات دفع NFC لهذه البطاقة.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تفعيل NFC',
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
        title: const Text('إلغاء ربط NFC'),
        content: const Text(
          'سيتم منع هذا الجهاز من إنشاء أذونات دفع NFC جديدة لهذه البطاقة.',
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
        message: 'تم إيقاف NFC لهذه البطاقة على هذا الجهاز.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر إلغاء NFC',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isRegisteringNfc = false);
      }
    }
  }

  Future<void> _writeNfcPaymentAuthorization(Map<String, dynamic> card) async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
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
      final prepared = await _api.preparePrepaidMultipayNfcPayment(
        cardId: cardId,
        amount: input.amount,
        pin: input.pin,
        deviceId: deviceId,
        appVersion: appVersion,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      final authorization = await _nfc.signAuthorization(
        cardId: cardId,
        authorization: Map<String, dynamic>.from(
          prepared['authorization'] as Map? ?? const {},
        ),
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showInfo(
        context,
        title: 'قرّب وسم NFC',
        message:
            'سيتم كتابة إذن دفع صالح حتى ${_formatDateTime(authorization.expiresAt.toLocal())}.',
      );
      await _nfc.writePaymentAuthorization(authorization);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم تجهيز دفع NFC',
        message:
            'تمت كتابة إذن دفع بقيمة ${CurrencyFormatter.ils(input.amount)}. يستطيع التاجر قراءته واعتماده الآن.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تجهيز دفع NFC',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isWritingNfcPayment = false);
      }
    }
  }

  Future<void> _acceptNfcPaymentAuthorization() async {
    if (!await _ensureNfcFeatureEnabled()) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() => _isAcceptingNfcPayment = true);
    try {
      final authorization = await _nfc.readPaymentAuthorization();
      if (DateTime.now().toUtc().isAfter(authorization.expiresAt.toUtc())) {
        throw Exception(
          'انتهت صلاحية إذن NFC. اطلب من المشتري إنشاء إذن جديد.',
        );
      }

      final payload = await _api.acceptPrepaidMultipayNfcPayment(
        signedPayload: authorization.signedPayload,
        signature: authorization.signature,
        idempotencyKey: _newPaymentKey(),
        merchantDeviceId: await LocalSecurityService.getOrCreateDeviceId(),
      );
      await _load();
      if (!mounted) {
        return;
      }
      final status = payload['status']?.toString() ?? '';
      if (status == 'approved') {
        await AppAlertService.showSuccess(
          context,
          title: 'تم قبول NFC',
          message:
              'تم استلام ${CurrencyFormatter.ils(authorization.amount)} عبر NFC.',
        );
      } else {
        await AppAlertService.showError(
          context,
          title: 'لم يتم اعتماد NFC',
          message: payload['message']?.toString() ?? 'تعذر اعتماد العملية.',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر قبول NFC',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isAcceptingNfcPayment = false);
      }
    }
  }

  Future<bool> _ensureNfcFeatureEnabled() async {
    if (_nfcEnabled) {
      return true;
    }
    await AppAlertService.showError(
      context,
      title: 'NFC غير مفعل',
      message: 'دفع NFC غير مفعل حاليًا من إعدادات النظام.',
    );
    return false;
  }

  Future<_NfcPaymentInput?> _showNfcPaymentInput() async {
    final amountC = TextEditingController();
    final pinC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('دفع NFC'),
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

  static String _validityYearsLabel(int years) {
    return switch (years) {
      1 => 'سنة واحدة',
      2 => 'سنتان',
      3 => 'ثلاث سنوات',
      4 => 'أربع سنوات',
      5 => 'خمس سنوات',
      _ => '$years سنوات',
    };
  }

  int _validityYearsFromCard(Map<String, dynamic> card) {
    final expiresAt = DateTime.tryParse(card['expiresAt']?.toString() ?? '');
    if (expiresAt == null) {
      return _validityYears;
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
    setState(() => _activeSection = 'payments');
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
      _openPaymentsTab();
      if (widget.autoAcceptNfc) {
        _acceptNfcPaymentAuthorization();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAnySection = _canUsePrepaidCards || _canAcceptPrepaidPayments;
    final body = _activeSection == 'payments' && _canAcceptPrepaidPayments
        ? _buildPaymentsTab()
        : _buildCardsTab();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('بطاقات الدفع المسبق'),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
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
                  _buildSummary(),
                  const SizedBox(height: 16),
                  _buildSectionActions(),
                  const SizedBox(height: 16),
                  Expanded(child: body),
                ],
              ),
        ),
    );
  }

  Widget _buildSectionActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (_canUsePrepaidCards)
          FilledButton.icon(
            onPressed: () => setState(() => _activeSection = 'cards'),
            icon: const Icon(Icons.credit_card_rounded),
            label: const Text('البطاقات'),
            style: _activeSection == 'cards'
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.border),
                  ),
          ),
        if (_canAcceptPrepaidPayments)
          FilledButton.icon(
            onPressed: () => setState(() => _activeSection = 'payments'),
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('الدفع والحركات'),
            style: _activeSection == 'payments'
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.border),
                  ),
          ),
      ],
    );
  }

  Widget _buildCardsTab() {
    final selected = _selectedCard;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (_cardsPane == 'create')
            _buildCreateCardPane()
          else if (_cardsPane == 'details' && selected != null)
            _buildCardDetailsPane(selected)
          else
            _buildCardsListPane(),
        ],
      ),
    );
  }

  Widget _buildCardsListPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('قائمة البطاقات', style: AppTheme.h2)),
            FilledButton.icon(
              onPressed: () => setState(() => _cardsPane = 'create'),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('إضافة'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'اضغط على أي بطاقة لفتح شاشة مستقلة للتفاصيل والتعديل والحركات.',
          style: AppTheme.bodyAction,
        ),
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

  Widget _buildCreateCardPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'رجوع',
              onPressed: () => setState(() => _cardsPane = 'list'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('إضافة بطاقة', style: AppTheme.h2)),
          ],
        ),
        const SizedBox(height: 12),
        _buildCreateForm(),
      ],
    );
  }

  Widget _buildCardDetailsPane(Map<String, dynamic> card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'رجوع',
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
                card['label']?.toString() ?? 'تفاصيل البطاقة',
                style: AppTheme.h2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildVisualCard(card, isLarge: true),
        const SizedBox(height: 14),
        _buildSelectedCardDetails(card),
      ],
    );
  }

  Widget _buildPaymentsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _buildPaymentForm(),
          const SizedBox(height: 16),
          _buildRecentPayments(),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final count = (_summary['count'] as num?)?.toInt() ?? 0;
    final active = (_summary['activeCount'] as num?)?.toInt() ?? 0;
    final spent = (_summary['spentCount'] as num?)?.toInt() ?? 0;
    final total = (_summary['totalBalance'] as num?)?.toDouble() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      gradient: AppTheme.primaryGradient,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryPill(Icons.credit_card_rounded, 'البطاقات', '$count'),
          _summaryPill(Icons.check_circle_rounded, 'النشطة', '$active'),
          _summaryPill(Icons.task_alt_rounded, 'المستهلكة', '$spent'),
          _summaryPill(
            Icons.account_balance_wallet_rounded,
            'الرصيد داخل البطاقات',
            CurrencyFormatter.ils(total),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: AppTheme.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
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
    final status = card['status']?.toString() ?? 'active';
    final canManage =
        _canUsePrepaidCards &&
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

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoPill(
                'الرصيد الحالي',
                CurrencyFormatter.ils(
                  (card['balance'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill(
                'إجمالي الشحن',
                CurrencyFormatter.ils(
                  (card['loadedAmount'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill(
                'المصروف',
                CurrencyFormatter.ils(
                  (card['spentAmount'] as num?)?.toDouble() ?? 0,
                ),
              ),
              _infoPill('الحالة', _statusLabel(status)),
              _infoPill(
                'الاستخدام اليومي',
                '${CurrencyFormatter.ils(((card['dailyUsage'] as Map?)?['amount'] as num?)?.toDouble() ?? 0)} / ${CurrencyFormatter.ils(((card['dailyUsage'] as Map?)?['amountLimit'] as num?)?.toDouble() ?? 0)}',
              ),
            ],
          ),
          _buildCardWarnings(card),
          const SizedBox(height: 16),
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
                      ? 'إخفاء الرقم'
                      : 'إظهار الرقم',
                ),
              ),
              if (canShowForDirectPayment)
                OutlinedButton.icon(
                  onPressed: () => _showCardForDirectPayment(card),
                  icon: const Icon(Icons.smartphone_rounded),
                  label: const Text('مشاهدة للدفع'),
                ),
              if (canPrintCard)
                OutlinedButton.icon(
                  onPressed: () => _printPrepaidCard(card),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('طباعة البطاقة'),
                ),
              if (status == 'active' && showNfcActions)
                OutlinedButton.icon(
                  onPressed: _isWritingNfc ? null : () => _writeCardToNfc(card),
                  icon: const Icon(Icons.nfc_rounded),
                  label: Text(_isWritingNfc ? 'جاري الكتابة' : 'كتابة NFC'),
                ),
              if (status == 'active' && showNfcActions)
                OutlinedButton.icon(
                  onPressed: _isRegisteringNfc
                      ? null
                      : () => _activateNfcPayment(card),
                  icon: const Icon(Icons.phonelink_lock_rounded),
                  label: Text(_isRegisteringNfc ? 'جاري الربط' : 'تفعيل NFC'),
                ),
              if (status == 'active' && showNfcActions)
                FilledButton.icon(
                  onPressed: _isWritingNfcPayment
                      ? null
                      : () => _writeNfcPaymentAuthorization(card),
                  icon: const Icon(Icons.tap_and_play_rounded),
                  label: Text(
                    _isWritingNfcPayment ? 'جاري التجهيز' : 'دفع NFC',
                  ),
                ),
              if (showNfcActions)
                OutlinedButton.icon(
                  onPressed: _isRegisteringNfc
                      ? null
                      : () => _revokeThisNfcDevice(card),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('إلغاء NFC للجهاز'),
                ),
              if (canUseForPayment)
                OutlinedButton.icon(
                  onPressed: () {
                    _fillPaymentFromSelectedCard();
                    _openPaymentsTab();
                  },
                  icon: const Icon(Icons.point_of_sale_rounded),
                  label: const Text('استخدام في الدفع'),
                ),
              if (canReload)
                OutlinedButton.icon(
                  onPressed: _isReloading
                      ? null
                      : () => _showReloadCardDialog(card),
                  icon: const Icon(Icons.add_card_rounded),
                  label: Text(_isReloading ? 'جاري الشحن' : 'شحن البطاقة'),
                ),
              if (canRenew)
                FilledButton.icon(
                  onPressed: () => _renewCard(card),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: const Text('تجديد سنة'),
                ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'pending_approval' ||
                    status == 'active' ||
                    status == 'frozen')
                  OutlinedButton.icon(
                    onPressed: () => _editCardDetails(card),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('تعديل البيانات'),
                  ),
                if (status == 'active')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'freeze'),
                    icon: const Icon(Icons.pause_circle_rounded),
                    label: const Text('تجميد'),
                  ),
                if (status == 'frozen')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'activate'),
                    icon: const Icon(Icons.play_circle_rounded),
                    label: const Text('تفعيل'),
                  ),
                if (status == 'active' || status == 'frozen')
                  OutlinedButton.icon(
                    onPressed: () => _changeSecurityCode(card),
                    icon: const Icon(Icons.password_rounded),
                    label: const Text('تغيير الكود'),
                  ),
              ],
            ),
          ],
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
                  ? 'إخفاء تفاصيل البطاقة'
                  : 'تفاصيل البطاقة',
            ),
          ),
          if (_showCardTechnicalDetails) ...[
            const SizedBox(height: 10),
            _detailsGrid(card),
            const SizedBox(height: 18),
          ] else
            const SizedBox(height: 18),
          Text('سجل النشاط', style: AppTheme.h3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _activityChip('all', 'الكل'),
              _activityChip('payments', 'المدفوعات'),
              _activityChip('reloads', 'الشحن'),
              _activityChip('status', 'الحالة'),
              _activityChip('security', 'الأمان'),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredActivity.isEmpty)
            Text(
              'لا توجد أنشطة على هذه البطاقة حتى الآن.',
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
            Text('حركات الدفع فقط', style: AppTheme.h3),
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

  Widget _buildCreateForm() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة بطاقة جديدة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'أنشئ بطاقة جديدة برصيد مبدئي، ومدة صلاحية محددة، وكود أمان من 3 أرقام.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelC,
            decoration: const InputDecoration(
              labelText: 'اسم البطاقة',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الرصيد المبدئي',
              prefixIcon: Icon(Icons.payments_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeC,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'الرقم السري من 3 أرقام',
              prefixIcon: Icon(Icons.pin_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _validityYears,
            decoration: const InputDecoration(
              labelText: 'مدة البطاقة',
              prefixIcon: Icon(Icons.event_available_rounded),
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
              setState(() => _validityYears = value);
            },
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: 'إنشاء البطاقة',
            icon: Icons.add_card_rounded,
            isLoading: _isSubmitting,
            onPressed: _create,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentForm() {
    final showNfcActions = _nfcEnabled && _canUsePrepaidNfc;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اعتماد دفع من بطاقة مسبقة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'أدخل مبلغ الدفع وكود التحقق الخاص ببطاقة الدفع المسبق لاعتماد العملية. سيصل لصاحب البطاقة إشعار باسم التاجر وتفاصيل السحب.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _payCardNumberC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'رقم البطاقة',
              prefixIcon: Icon(Icons.credit_card_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _scanPaymentCard,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('قراءة البطاقة'),
              ),
              if (showNfcActions) ...[
                OutlinedButton.icon(
                  onPressed: _isReadingNfc ? null : _readPaymentCardFromNfc,
                  icon: const Icon(Icons.nfc_rounded),
                  label: Text(_isReadingNfc ? 'جاري القراءة' : 'قراءة NFC'),
                ),
                FilledButton.icon(
                  onPressed: _isAcceptingNfcPayment
                      ? null
                      : _acceptNfcPaymentAuthorization,
                  icon: const Icon(Icons.tap_and_play_rounded),
                  label: Text(
                    _isAcceptingNfcPayment ? 'جاري الاعتماد' : 'قبول NFC',
                  ),
                ),
              ],
              if (_selectedCard != null)
                OutlinedButton.icon(
                  onPressed: _fillPaymentFromSelectedCard,
                  icon: const Icon(Icons.file_download_done_rounded),
                  label: const Text('تعبئة من البطاقة المحددة'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payAmountC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'مبلغ الدفع',
              prefixIcon: Icon(Icons.payments_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _payMonthC,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'الشهر MM',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _payYearC,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'السنة YY',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _payCodeC,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'كود التحقق',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payNoteC,
            maxLength: 180,
            decoration: const InputDecoration(
              labelText: 'ملاحظة اختيارية',
              prefixIcon: Icon(Icons.notes_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: 'اعتماد الدفع',
            icon: Icons.point_of_sale_rounded,
            isLoading: _isAcceptingPayment,
            onPressed: _acceptPayment,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentPayments() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('آخر الحركات', style: AppTheme.h3),
          const SizedBox(height: 12),
          if (_payments.isEmpty)
            Text('لا توجد حركات بطاقات حتى الآن.', style: AppTheme.bodyAction)
          else
            ..._payments
                .take(12)
                .map(
                  (payment) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildPaymentTile(payment),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildPaymentTile(Map<String, dynamic> payment) {
    final direction = payment['direction']?.toString() ?? 'out';
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
    final note = payment['note']?.toString() ?? '';
    final isIncoming = direction == 'in';
    final color = isIncoming ? AppTheme.success : AppTheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncoming ? 'دفعة واردة' : 'دفعة صادرة',
                  style: AppTheme.bodyBold,
                ),
                Text(
                  note.isEmpty ? 'حركة بطاقة مسبقة' : note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
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
          Text(
            CurrencyFormatter.ils(amount),
            style: AppTheme.bodyBold.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualCard(Map<String, dynamic> card, {bool isLarge = false}) {
    final cardId = card['id']?.toString() ?? '';
    final isRevealed = _revealedCardIds.contains(cardId);
    final displayNumber = isRevealed
        ? card['cardNumber']?.toString() ?? ''
        : '•••• •••• •••• ••••';
    final ownerName = _cardOwnerName();
    final issuerPhone = _cardIssuerLocalPhone();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isLarge ? 22 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0F766E), Color(0xFF155E75)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.mediumShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'بطاقة دفع مسبق',
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(card['status']?.toString() ?? 'active'),
                  style: AppTheme.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            card['label']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.h3.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            ownerName.isEmpty
                ? 'هذه البطاقة ملك لصاحبها'
                : 'هذه البطاقة ملك لـ $ownerName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(color: Colors.white70),
          ),
          SizedBox(height: isLarge ? 26 : 18),
          Text(
            displayNumber,
            style: AppTheme.h2.copyWith(
              color: Colors.white,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الرصيد المتاح',
                      style: AppTheme.caption.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.ils(
                        (card['balance'] as num?)?.toDouble() ?? 0,
                      ),
                      style: AppTheme.bodyBold.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MM/YY',
                    style: AppTheme.caption.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card['expiryLabel']?.toString() ?? '-',
                    style: AppTheme.bodyBold.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          if (issuerPhone.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'هاتف مصدر البطاقة: $issuerPhone',
              textDirection: TextDirection.ltr,
              style: AppTheme.caption.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  String _cardOwnerName() {
    final fullName = AuthService.peekCurrentUser()?['fullName']?.toString() ??
        AuthService.peekCurrentUser()?['full_name']?.toString() ??
        '';
    if (fullName.trim().isNotEmpty) {
      return fullName.trim();
    }
    return AuthService.peekCurrentUser()?['username']?.toString().trim() ?? '';
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

  String _newPaymentKey() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'prepaid:$now:${identityHashCode(this)}';
  }

  String _extractCardNumber(String value) {
    final trimmed = value.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['type'] == 'prepaid_multipay_card') {
        return decoded['cardNumber']?.toString().replaceAll(
              RegExp(r'\D+'),
              '',
            ) ??
            '';
      }
    } catch (_) {
      // Fall through to plain-number parsing.
    }

    return trimmed.replaceAll(RegExp(r'\D+'), '');
  }
}

class _NfcPaymentInput {
  const _NfcPaymentInput({required this.amount, required this.pin});

  final double amount;
  final String pin;
}
