import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/print_card_preview.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/thermal_card_ticket.dart';

class CreateCardScreen extends StatefulWidget {
  const CreateCardScreen({super.key});

  @override
  State<CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends State<CreateCardScreen> {
  static const int _cardsPerA4Page = 30;
  static const double _trialCardsLimit = 10;

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final PDFService _pdfService = PDFService();
  final ThermalPrinterService _thermalPrinterService = ThermalPrinterService();
  final ScreenshotController _thermalTicketScreenshot = ScreenshotController();
  final TextEditingController _amountC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController(
    text: '$_cardsPerA4Page',
  );
  final TextEditingController _titleC = TextEditingController();
  final TextEditingController _stampC = TextEditingController();
  final TextEditingController _detailsTitleC = TextEditingController();
  final TextEditingController _detailsDescriptionC = TextEditingController();
  final TextEditingController _appointmentLocationC = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingUser = true;
  bool _isAuthorized = false;
  bool _showLogo = true;
  bool _showStamp = true;
  bool _useAccountLogo = true;
  bool _isThermalPrinting = false;
  String _cardType = 'standard';
  String _visibilityScope = 'general';
  DateTime? _validFrom;
  DateTime? _validUntil;
  DateTime? _appointmentStartsAt;
  DateTime? _appointmentEndsAt;
  Map<String, dynamic>? _user;
  List<VirtualCard> _recent = [];
  List<Map<String, dynamic>> _selectedUsers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountC.dispose();
    _qtyC.dispose();
    _titleC.dispose();
    _stampC.dispose();
    _detailsTitleC.dispose();
    _detailsDescriptionC.dispose();
    _appointmentLocationC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = context.loc;
    try {
      final user = await _authService.currentUser();
      if (!mounted) {
        return;
      }
      final permissions = AppPermissions.fromUser(user);
      setState(() {
        _user = user;
        _isAuthorized = permissions.canIssueCards;
        final isTrialMode =
            (user?['transferVerificationStatus']?.toString() ?? 'unverified') !=
            'approved';
        final accountName =
            user?['fullName']?.toString().trim().isNotEmpty == true
            ? user!['fullName'].toString().trim()
            : l.tr('screens_create_card_screen.001');
        if (_titleC.text.trim().isEmpty ||
            _titleC.text.trim() == l.tr('screens_create_card_screen.001')) {
          _titleC.text = accountName;
        }
        _useAccountLogo =
            user?['printLogoUrl']?.toString().trim().isNotEmpty == true;
        final issuableCardTypes = _issuableCardTypesFromUser(user);
        if (!issuableCardTypes.contains(_cardType) &&
            issuableCardTypes.isNotEmpty) {
          _cardType = issuableCardTypes.first;
        }
        if (isTrialMode) {
          _cardType = 'standard';
          _visibilityScope = 'restricted';
          if ((_qtyC.text.trim()).isEmpty ||
              (int.tryParse(_qtyC.text.trim()) ?? 0) % _cardsPerA4Page == 0) {
            _qtyC.text = '1';
          }
        }
        _isLoadingUser = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  AppPermissions get _appPermissions => AppPermissions.fromUser(_user);

  bool get _canIssuePrivateCards => _appPermissions.canIssuePrivateCards;

  bool get _canRequestCardPrinting => _appPermissions.canRequestCardPrinting;

  bool get _hasAccountLogo =>
      _user?['printLogoUrl']?.toString().trim().isNotEmpty == true;

  bool get _canUseThermalPrinting =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isAppointmentCard => _cardType == 'appointment';
  bool get _isQueueCard => _cardType == 'queue';

  bool get _isBalanceCard => _cardType == 'standard' || _cardType == 'delivery';
  bool get _needsTypeDetails => _isAppointmentCard || _isQueueCard;
  bool get _isTrialMode =>
      (_user?['transferVerificationStatus']?.toString() ?? 'unverified') !=
      'approved';
  double get _trialCardsRemainingAmount =>
      ((_user?['trialCardsAvailableAmount'] as num?)?.toDouble() ??
              _trialCardsLimit)
          .clamp(0, _trialCardsLimit)
          .toDouble();
  double get _trialCardsOutstandingAmount =>
      ((_user?['trialCardsOutstandingAmount'] as num?)?.toDouble() ?? 0)
          .clamp(0, _trialCardsLimit)
          .toDouble();

  List<String> get _issuableCardTypes => _issuableCardTypesFromUser(_user);

  List<String> _issuableCardTypesFromUser(Map<String, dynamic>? user) {
    final raw = user?['cardIssuanceOptions'];
    if (raw is List) {
      final values = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) {
        return values;
      }
    }
    if (user?['role']?.toString() == 'driver') {
      return const ['delivery'];
    }
    return const ['standard', 'single_use', 'appointment', 'queue'];
  }

  List<DropdownMenuItem<String>> _cardTypeItems(AppLocalizer l) =>
      _issuableCardTypes.map((type) {
        return DropdownMenuItem(
          value: type,
          child: Text(_cardTypeLabel(l, type)),
        );
      }).toList();

  String _cardTypeLabel(AppLocalizer l, String type) {
    switch (type) {
      case 'single_use':
        return l.tr('screens_create_card_screen.003');
      case 'delivery':
        return l.tr('shared.delivery_card_label');
      case 'appointment':
        return 'تذكرة موعد';
      case 'queue':
        return 'تذكرة طابور';
      default:
        return l.tr('screens_create_card_screen.002');
    }
  }

  String? _validateAmountForCardType(double amount) {
    if (_isBalanceCard) {
      return amount > 0 ? null : 'أدخل قيمة بطاقة صحيحة أكبر من صفر.';
    }

    if (_isAppointmentCard && amount < 0) {
      return 'قيمة تذكرة الموعد لا يمكن أن تكون سالبة.';
    }

    return null;
  }

  Future<void> _create() async {
    final l = context.loc;
    if (!_isAuthorized) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.004'),
        message: l.tr('screens_create_card_screen.050'),
      );
      return;
    }
    final amount = double.tryParse(_amountC.text) ?? 0;
    final quantity = int.tryParse(_qtyC.text) ?? 0;
    final isPrivate = _isTrialMode || _visibilityScope == 'restricted';

    if (quantity <= 0) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.004'),
        message: 'أدخل عدد بطاقات صحيح.',
      );
      return;
    }

    final amountValidationMessage = _validateAmountForCardType(amount);
    if (amountValidationMessage != null) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.004'),
        message: amountValidationMessage,
      );
      return;
    }

    if (!_isTrialMode && quantity % _cardsPerA4Page != 0) {
      await AppAlertService.showError(
        context,
        title: 'عدد البطاقات غير صالح',
        message:
            'عدد البطاقات يجب أن يكون من مضاعفات $_cardsPerA4Page لأن صفحة A4 تطبع $_cardsPerA4Page بطاقة.',
      );
      return;
    }

    if (_isTrialMode) {
      final totalAmount = amount * quantity;
      if (totalAmount > _trialCardsRemainingAmount) {
        await AppAlertService.showError(
          context,
          title: 'تجاوزت الحد التجريبي',
          message:
              'يمكنك إنشاء بطاقات تجريبية بمجموع متبقٍ ${CurrencyFormatter.ils(_trialCardsRemainingAmount)} فقط.',
        );
        return;
      }
    }

    if (_isAppointmentCard) {
      if (_detailsTitleC.text.trim().isEmpty || _appointmentStartsAt == null) {
        await AppAlertService.showError(
          context,
          title: 'بيانات الموعد ناقصة',
          message: 'أدخل عنوان الموعد وحدد وقت البداية على الأقل.',
        );
        return;
      }

      if (_appointmentEndsAt != null &&
          !_appointmentEndsAt!.isAfter(_appointmentStartsAt!)) {
        await AppAlertService.showError(
          context,
          title: 'وقت الموعد غير صحيح',
          message: 'وقت نهاية الموعد يجب أن يكون بعد وقت البداية.',
        );
        return;
      }
    }

    if (_isQueueCard && _detailsTitleC.text.trim().isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'بيانات الطابور ناقصة',
        message: 'أدخل عنوان أو اسم خدمة الطابور.',
      );
      return;
    }

    if (_validFrom != null &&
        _validUntil != null &&
        !_validUntil!.isAfter(_validFrom!)) {
      await AppAlertService.showError(
        context,
        title: 'نافذة الصلاحية غير صحيحة',
        message: 'وقت انتهاء الصلاحية يجب أن يكون بعد وقت البداية.',
      );
      return;
    }

    if (!_isTrialMode && isPrivate && _selectedUsers.isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.006'),
        message: l.tr('screens_create_card_screen.007'),
      );
      return;
    }

    final typeLabel = _cardTypeLabel(l, _cardType);
    final visibilityLabel = isPrivate
        ? l.tr('screens_create_card_screen.010')
        : l.tr('screens_create_card_screen.011');
    final valueLabel = _cardValueLabel(l, amount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_create_card_screen.013')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.tr(
                'screens_create_card_screen.014',
                params: {
                  'quantity': '$quantity',
                  'type': typeLabel,
                  'visibility': visibilityLabel,
                  'value': valueLabel,
                  'privateLine': isPrivate
                      ? l.tr(
                          'screens_create_card_screen.015',
                          params: {'count': '${_selectedUsers.length}'},
                        )
                      : '',
                },
              ),
              textDirection: TextDirection.rtl,
            ),
            if (_detailsTitleC.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('العنوان: ${_detailsTitleC.text.trim()}'),
            ],
            if (_formatValidityWindow().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('الصلاحية: ${_formatValidityWindow()}'),
            ],
            if (_isAppointmentCard && _appointmentStartsAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'الموعد: ${_formatDateTime(_appointmentStartsAt)}${_appointmentEndsAt != null ? ' - ${_formatDateTime(_appointmentEndsAt)}' : ''}',
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l.tr('screens_create_card_screen.016')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShwakelButton(
                    label: l.tr('screens_create_card_screen.017'),
                    onPressed: () => Navigator.pop(dialogContext, true),
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

    final cards = await (_isTrialMode
        ? _issueTrialCardsAfterSecurity(amount, quantity)
        : _issueCardsAfterSecurity(amount, quantity));
    if (cards == null || !mounted) {
      return;
    }

    setState(() {
      _recent = cards;
      _isLoading = false;
    });
    await _load();
    if (mounted) {
      _showSuccess(cards);
    }
  }

  Future<List<VirtualCard>?> _issueCardsAfterSecurity(
    double amount,
    int quantity,
  ) async {
    final l = context.loc;
    var securityResult = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !securityResult.isVerified) {
      return null;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      setState(() => _isLoading = true);
      try {
        final cards = await _apiService.issueCards(
          value: amount,
          quantity: quantity,
          cardType: _cardType,
          visibilityScope: _visibilityScope,
          printDesign: _currentPrintDesign(),
          validFrom: _validFrom?.toUtc().toIso8601String(),
          validUntil: _validUntil?.toUtc().toIso8601String(),
          cardDetails: _currentCardDetails(),
          otpCode: securityResult.otpCode,
          localAuthMethod: securityResult.method,
          allowedUserIds: _selectedAllowedUserIds(),
        );
        final userId = _user?['id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          await _cacheIssuedCards(userId: userId, cards: cards);
        }
        return cards;
      } catch (error) {
        if (!mounted) {
          return null;
        }
        final message = ErrorMessageService.sanitize(error);
        setState(() => _isLoading = false);

        if (attempt == 0 && _isLocalSecurityRequiredMessage(message)) {
          securityResult = await TransferSecurityService.confirmTransfer(
            context,
          );
          if (!mounted || !securityResult.isVerified) {
            return null;
          }
          continue;
        }

        await AppAlertService.showError(
          context,
          title: l.tr('screens_create_card_screen.018'),
          message: message,
        );
        return null;
      }
    }

    return null;
  }

  Future<List<VirtualCard>?> _issueTrialCardsAfterSecurity(
    double amount,
    int quantity,
  ) async {
    var securityResult = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !securityResult.isVerified) {
      return null;
    }

    final baseTitle = _detailsTitleC.text.trim();
    final items = List.generate(quantity, (index) {
      return <String, dynamic>{
        'value': amount,
        if (baseTitle.isNotEmpty)
          'title': quantity == 1 ? baseTitle : '$baseTitle ${index + 1}',
      };
    });

    for (var attempt = 0; attempt < 2; attempt++) {
      setState(() => _isLoading = true);
      try {
        final cards = await _apiService.issueTrialCards(
          items: items,
          otpCode: securityResult.otpCode,
          localAuthMethod: securityResult.method,
        );
        final userId = _user?['id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          await _cacheIssuedCards(userId: userId, cards: cards);
        }
        return cards;
      } catch (error) {
        if (!mounted) {
          return null;
        }
        final message = ErrorMessageService.sanitize(error);
        setState(() => _isLoading = false);

        if (attempt == 0 && _isLocalSecurityRequiredMessage(message)) {
          securityResult = await TransferSecurityService.confirmTransfer(
            context,
          );
          if (!mounted || !securityResult.isVerified) {
            return null;
          }
          continue;
        }

        await AppAlertService.showError(
          context,
          title: 'تعذر إنشاء البطاقات التجريبية',
          message: message,
        );
        return null;
      }
    }

    return null;
  }

  Future<void> _cacheIssuedCards({
    required String userId,
    required List<VirtualCard> cards,
  }) async {
    try {
      await _offlineCardService.cacheCards(userId: userId, cards: cards);
    } catch (_) {
      // Offline cache should never make a successful card issue look failed.
    }
  }

  Map<String, dynamic> _currentPrintDesign() {
    final l = context.loc;
    return {
      'logoText': _titleC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.001')
          : _titleC.text.trim(),
      'stampText': _stampC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.019')
          : _stampC.text.trim(),
      'logoUrl': (_showLogo && _useAccountLogo)
          ? (_user?['printLogoUrl'])?.toString()
          : null,
      'showStamp': _showStamp,
    };
  }

  Map<String, dynamic>? _currentCardDetails() {
    final details = <String, dynamic>{};
    if (_detailsTitleC.text.trim().isNotEmpty) {
      details['title'] = _detailsTitleC.text.trim();
    }
    if (_detailsDescriptionC.text.trim().isNotEmpty) {
      details['description'] = _detailsDescriptionC.text.trim();
    }
    if (_appointmentLocationC.text.trim().isNotEmpty) {
      details['location'] = _appointmentLocationC.text.trim();
    }
    if (_appointmentStartsAt != null) {
      details['startsAt'] = _appointmentStartsAt!.toUtc().toIso8601String();
    }
    if (_appointmentEndsAt != null) {
      details['endsAt'] = _appointmentEndsAt!.toUtc().toIso8601String();
    }
    if (_isAppointmentCard) {
      details['ticketKind'] = 'appointment';
    } else if (_isQueueCard) {
      details['ticketKind'] = 'queue';
    }
    return details.isEmpty ? null : details;
  }

  String _cardValueLabel(AppLocalizer l, double amount) {
    if (_cardType == 'single_use' || _isQueueCard) {
      return amount <= 0
          ? 'تذكرة استخدام تنظيمي'
          : CurrencyFormatter.ils(amount);
    }
    if (_isAppointmentCard && amount <= 0) {
      return 'بدون قيمة مالية';
    }
    return CurrencyFormatter.ils(amount);
  }

  String _formatValidityWindow() {
    if (_validFrom == null && _validUntil == null) {
      return '';
    }
    if (_validFrom != null && _validUntil != null) {
      return '${_formatDateTime(_validFrom)} - ${_formatDateTime(_validUntil)}';
    }
    if (_validFrom != null) {
      return 'من ${_formatDateTime(_validFrom)}';
    }
    return 'حتى ${_formatDateTime(_validUntil)}';
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

  Widget _buildDateTimeField({
    required String label,
    required DateTime? value,
    required IconData icon,
    required Future<void> Function() onPick,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: value == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    setState(() {
                      if (label == 'فعالة من') {
                        _validFrom = null;
                      } else if (label == 'تنتهي في') {
                        _validUntil = null;
                      } else if (label == 'بداية الموعد') {
                        _appointmentStartsAt = null;
                      } else if (label == 'نهاية الموعد') {
                        _appointmentEndsAt = null;
                      }
                    });
                  },
                ),
        ),
        child: Text(
          value == null ? 'اختر التاريخ والوقت' : _formatDateTime(value),
          style: value == null
              ? AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary)
              : AppTheme.bodyBold,
        ),
      ),
    );
  }

  Future<void> _pickDateTime({
    required DateTime? initialValue,
    required void Function(DateTime value) onChanged,
  }) async {
    final now = DateTime.now();
    final start = initialValue?.toLocal() ?? now;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (pickedTime == null || !mounted) {
      return;
    }

    onChanged(
      DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ),
    );
  }

  List<String> _selectedAllowedUserIds() {
    return _selectedUsers
        .map((user) => user['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  bool _isLocalSecurityRequiredMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('pin') &&
        (normalized.contains('البصمة') ||
            normalized.contains('biometric') ||
            normalized.contains('otp')) &&
        (normalized.contains('تأكيد') || normalized.contains('confirm'));
  }

  Future<bool> _confirmCardOutputSecurity() async {
    final security = await TransferSecurityService.confirmTransfer(context);
    return mounted && security.isVerified;
  }

  Future<void> _printCards(
    List<VirtualCard> cards, {
    bool requireSecurity = true,
  }) async {
    if (requireSecurity && !await _confirmCardOutputSecurity()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final l = context.loc;
    final printedBy = _user?['fullName']?.toString().trim().isNotEmpty == true
        ? _user!['fullName'].toString().trim()
        : _user?['username']?.toString();

    final settings = CardDesignSettings(
      showLogo: _showLogo,
      showStamp: _showStamp,
      logoText: _titleC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.001')
          : _titleC.text.trim(),
      stampText: _stampC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.019')
          : _stampC.text.trim(),
    );
    settings.logoUrl = (_showLogo && _useAccountLogo)
        ? (_user?['printLogoUrl'])?.toString()
        : null;
    _pdfService.setDesignSettings(settings);
    try {
      await _pdfService.printCards(cards, printedBy: printedBy);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.print_failed_title',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _quickThermalPrintCards(
    List<VirtualCard> cards, {
    bool requireSecurity = true,
  }) async {
    final l = context.loc;
    if (!_canUseThermalPrinting) {
      await AppAlertService.showInfo(
        context,
        title: 'الطباعة الحرارية غير متاحة',
        message: 'الطباعة الحرارية السريعة مدعومة حاليًا على الأجهزة المحمولة.',
      );
      return;
    }
    if (cards.isEmpty) {
      return;
    }
    if (requireSecurity && !await _confirmCardOutputSecurity()) {
      return;
    }

    setState(() => _isThermalPrinting = true);
    try {
      final printer = await _resolveThermalPrinter();
      if (printer == null || !mounted) {
        return;
      }

      final connected = await _thermalPrinterService.ensureConnected(printer);
      if (!connected) {
        if (!mounted) {
          return;
        }
        await AppAlertService.showError(
          context,
          title: 'تعذر الاتصال بالطابعة',
          message:
              'تأكد من تشغيل البلوتوث وأن الطابعة الحرارية مقترنة بالجهاز.',
        );
        return;
      }

      final issuerName = _resolvedIssuerName(l);
      for (var index = 0; index < cards.length; index++) {
        final card = cards[index];
        final ticketBytes = await _captureThermalTicketBytes(card, issuerName);
        final printed = await _thermalPrinterService.printCardTicket(
          card: card,
          ticketPngBytes: ticketBytes,
          issuerName: issuerName,
          cutPaper: index == cards.length - 1,
        );
        if (!printed) {
          if (!mounted) {
            return;
          }
          await AppAlertService.showError(
            context,
            title: 'فشل الطباعة الحرارية',
            message: 'تعذر إرسال البطاقة إلى الطابعة الحرارية.',
          );
          return;
        }
      }

      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تمت الطباعة الحرارية',
        message: l.tr(
          'screens_create_card_screen.021',
          params: {'count': '${cards.length}'},
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر الطباعة الحرارية',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isThermalPrinting = false);
      }
    }
  }

  String _resolvedIssuerName(AppLocalizer l) {
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final username = _user?['username']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) {
      return fullName;
    }
    if (username.isNotEmpty) {
      return username;
    }
    return l.tr('screens_create_card_screen.001');
  }

  Future<Uint8List> _captureThermalTicketBytes(
    VirtualCard card,
    String issuerName,
  ) {
    final title = _titleC.text.trim().isEmpty
        ? context.loc.tr('screens_create_card_screen.001')
        : _titleC.text.trim();

    return _thermalTicketScreenshot.captureFromWidget(
      ThermalCardTicket(card: card, issuerName: issuerName, title: title),
      context: context,
      pixelRatio: 2.4,
      delay: const Duration(milliseconds: 100),
      targetSize: const Size(320, 420),
    );
  }

  Future<ThermalPrinterDevice?> _resolveThermalPrinter() async {
    final selected = await _thermalPrinterService.selectedDevice();
    final hasPermission = await _thermalPrinterService
        .ensureBluetoothPermission();
    if (!hasPermission) {
      if (!mounted) {
        return null;
      }
      await AppAlertService.showInfo(
        context,
        title: 'صلاحية البلوتوث مطلوبة',
        message: 'فعّل صلاحية البلوتوث للتطبيق ثم أعد محاولة الطباعة الحرارية.',
      );
      return null;
    }

    final bluetoothEnabled = await _thermalPrinterService.isBluetoothEnabled();
    if (!bluetoothEnabled) {
      if (!mounted) {
        return null;
      }
      await AppAlertService.showInfo(
        context,
        title: 'البلوتوث غير مفعّل',
        message: 'شغّل البلوتوث على الجهاز ثم أعد محاولة الطباعة الحرارية.',
      );
      return null;
    }

    final devices = await _thermalPrinterService.pairedDevices();
    if (devices.isEmpty) {
      if (!mounted) {
        return null;
      }
      await AppAlertService.showInfo(
        context,
        title: 'لا توجد طابعات مقترنة',
        message:
            'قم بربط الطابعة الحرارية من إعدادات البلوتوث أولًا ثم أعد المحاولة.',
      );
      return null;
    }

    if (selected != null &&
        devices.any((device) => device.macAddress == selected.macAddress)) {
      return selected;
    }

    if (!mounted) {
      return null;
    }
    final picked = await _showThermalPrinterPicker(devices);
    if (picked != null) {
      await _thermalPrinterService.rememberDevice(picked);
    }
    return picked;
  }

  Future<ThermalPrinterDevice?> _showThermalPrinterPicker(
    List<ThermalPrinterDevice> devices,
  ) async {
    final selected = await _thermalPrinterService.selectedDevice();
    if (!mounted) {
      return null;
    }

    return showModalBottomSheet<ThermalPrinterDevice>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final selectedMac = selected?.macAddress;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Text('اختر الطابعة الحرارية', style: AppTheme.h3),
              const SizedBox(height: 8),
              Text(
                'سيتم حفظ الطابعة المختارة لتسريع الطباعة لاحقًا.',
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 14),
              ...devices.map((device) {
                final isSelected = device.macAddress == selectedMac;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.pop(context, device),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: 0.08)
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primarySoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.print_rounded,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(device.name, style: AppTheme.bodyBold),
                                const SizedBox(height: 4),
                                Text(
                                  device.macAddress,
                                  style: AppTheme.caption.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppTheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showSuccess(List<VirtualCard> cards) {
    final l = context.loc;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_create_card_screen.020')),
        content: Text(
          l.tr(
            'screens_create_card_screen.021',
            params: {'count': '${cards.length}'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.tr('screens_create_card_screen.022')),
          ),
          if (_canUseThermalPrinting)
            ShwakelButton(
              label: 'طباعة حرارية',
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _quickThermalPrintCards(cards, requireSecurity: false);
              },
              width: 150,
              isSecondary: true,
            ),
          if (_canRequestCardPrinting)
            ShwakelButton(
              label: l.tr('screens_create_card_screen.023'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _printCards(cards, requireSecurity: false);
              },
              width: 150,
            ),
        ],
      ),
    );
  }

  Future<void> _pickPrivateUsers() async {
    final l = context.loc;
    final results = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        final selected = List<Map<String, dynamic>>.from(_selectedUsers);
        List<Map<String, dynamic>> results = [];
        bool loading = false;

        Future<void> searchUsers(
          StateSetter setModalState,
          String query,
        ) async {
          setModalState(() => loading = true);
          try {
            results = await _apiService.searchUsers(query);
          } catch (_) {
            results = [];
          } finally {
            setModalState(() => loading = false);
          }
        }

        bool isSelected(Map<String, dynamic> user) {
          final id = user['id']?.toString();
          return selected.any((item) => item['id']?.toString() == id);
        }

        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(l.tr('screens_create_card_screen.024')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: l.tr('screens_create_card_screen.025'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onChanged: (value) => searchUsers(setModalState, value),
                  ),
                  const SizedBox(height: 16),
                  if (selected.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selected.map((user) {
                        return Chip(
                          label: Text('@${user['username'] ?? user['id']}'),
                          onDeleted: () {
                            setModalState(() {
                              selected.removeWhere(
                                (item) =>
                                    item['id']?.toString() ==
                                    user['id']?.toString(),
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: results.map((user) {
                        final selectedNow = isSelected(user);
                        return CheckboxListTile(
                          value: selectedNow,
                          title: Text(
                            user['username']?.toString() ??
                                l.tr('screens_create_card_screen.026'),
                          ),
                          subtitle: Text(
                            l.tr(
                              'screens_create_card_screen.027',
                              params: {'id': '${user['id'] ?? '-'}'},
                            ),
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true && !selectedNow) {
                                selected.add(user);
                              } else if (value == false) {
                                selected.removeWhere(
                                  (item) =>
                                      item['id']?.toString() ==
                                      user['id']?.toString(),
                                );
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_create_card_screen.016')),
              ),
              ShwakelButton(
                label: l.tr('screens_create_card_screen.028'),
                width: 120,
                onPressed: () => Navigator.pop(dialogContext, selected),
              ),
            ],
          ),
        );
      },
    );

    if (results == null || !mounted) {
      return;
    }

    setState(() => _selectedUsers = results);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_create_card_screen.029')),
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
                Text(
                  l.tr('screens_create_card_screen.050'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_create_card_screen.029')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(Icons.add_card_rounded),
                text: l.tr('screens_create_card_screen.066'),
              ),
              Tab(
                icon: const Icon(Icons.history_rounded),
                text: l.tr('screens_create_card_screen.068'),
              ),
            ],
          ),
        ),
        drawer: const AppSidebar(),
        body: TabBarView(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 620;
                final previewHeight = isCompact ? 360.0 : 430.0;
                return Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.only(top: previewHeight),
                      child: ResponsiveScaffoldContainer(
                        padding: const EdgeInsets.all(AppTheme.spacingLg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHero(),
                            const SizedBox(height: 24),
                            _buildForm(),
                          ],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: AppTheme.spacingLg,
                      start: AppTheme.spacingLg,
                      end: AppTheme.spacingLg,
                      child: _buildFloatingDesignPreview(isCompact: isCompact),
                    ),
                  ],
                );
              },
            ),
            SingleChildScrollView(
              child: ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 24),
                    _buildRecent(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: AppTheme.primaryGradient,
      withBorder: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          return Flex(
            direction: isCompact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isCompact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: AppTheme.radiusMd,
                ),
                child: const Icon(
                  Icons.add_card_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              SizedBox(width: isCompact ? 0 : 18, height: isCompact ? 14 : 0),
              if (isCompact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_create_card_screen.030'),
                      style: AppTheme.h2.copyWith(
                        color: Colors.white,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.tr('screens_create_card_screen.031'),
                      style: AppTheme.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.tr('screens_create_card_screen.030'),
                        style: AppTheme.h2.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.tr('screens_create_card_screen.031'),
                        style: AppTheme.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tr('screens_create_card_screen.032'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_create_card_screen.033'),
            style: AppTheme.bodyAction.copyWith(fontSize: 14),
          ),
          if (_isTrialMode) ...[
            const SizedBox(height: 18),
            _buildTrialInfoCard(),
          ],
          const SizedBox(height: 24),
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('البيانات الأساسية', style: AppTheme.bodyBold),
                const SizedBox(height: 6),
                Text(
                  'ابدأ بنوع البطاقة ثم أدخل القيمة والعدد. ستظهر التفاصيل الإضافية فقط عند الحاجة.',
                  style: AppTheme.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!_isTrialMode && _cardTypeItems(l).length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _cardType,
              decoration: InputDecoration(
                labelText: l.tr('screens_create_card_screen.034'),
                prefixIcon: const Icon(Icons.category_rounded),
              ),
              items: _cardTypeItems(l),
              onChanged: (value) {
                setState(() {
                  _cardType = value ?? 'standard';
                  if (_cardType == 'delivery') {
                    _visibilityScope = 'general';
                    _selectedUsers = [];
                  }
                  if (_cardType != 'appointment') {
                    _appointmentStartsAt = null;
                    _appointmentEndsAt = null;
                  }
                  if (_cardType != 'appointment' && _cardType != 'queue') {
                    _appointmentLocationC.clear();
                    _detailsTitleC.clear();
                    _detailsDescriptionC.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
          ],
          if (_isBalanceCard || _isAppointmentCard) ...[
            TextField(
              controller: _amountC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isAppointmentCard
                    ? 'القيمة المالية إن وجدت'
                    : l.tr('screens_create_card_screen.035'),
                prefixIcon: const Icon(Icons.money_rounded),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _qtyC,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.tr('screens_create_card_screen.037'),
              prefixIcon: const Icon(Icons.pin_rounded),
              helperText: _isTrialMode
                  ? 'يمكنك إنشاء أي عدد من البطاقات ما دام مجموعها لا يتجاوز ${CurrencyFormatter.ils(_trialCardsRemainingAmount)}.'
                  : 'أدخل مضاعفات $_cardsPerA4Page فقط مثل $_cardsPerA4Page أو ${_cardsPerA4Page * 2} أو ${_cardsPerA4Page * 3}.',
            ),
          ),
          if (_cardType == 'single_use') ...[
            const SizedBox(height: 16),
            ShwakelCard(
              padding: const EdgeInsets.all(16),
              color: AppTheme.secondary.withValues(alpha: 0.06),
              borderColor: AppTheme.secondary.withValues(alpha: 0.15),
              child: Text(
                l.tr('screens_create_card_screen.036'),
                style: AppTheme.bodyText.copyWith(fontSize: 14),
              ),
            ),
          ],
          if (_cardType == 'delivery') ...[
            const SizedBox(height: 16),
            ShwakelCard(
              padding: const EdgeInsets.all(16),
              color: AppTheme.warning.withValues(alpha: 0.06),
              borderColor: AppTheme.warning.withValues(alpha: 0.15),
              child: Text(
                l.tr('shared.delivery_card_create_note'),
                style: AppTheme.bodyText.copyWith(fontSize: 14),
              ),
            ),
          ],
          if (_needsTypeDetails) ...[
            const SizedBox(height: 16),
            ShwakelCard(
              padding: const EdgeInsets.all(16),
              color:
                  (_isAppointmentCard ? AppTheme.primary : AppTheme.secondary)
                      .withValues(alpha: 0.05),
              borderColor:
                  (_isAppointmentCard ? AppTheme.primary : AppTheme.secondary)
                      .withValues(alpha: 0.15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAppointmentCard
                        ? 'تفاصيل الموعد المطلوبة'
                        : 'تفاصيل تذكرة الطابور',
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detailsTitleC,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _isAppointmentCard
                          ? 'عنوان الموعد'
                          : 'اسم الخدمة أو الطابور',
                      prefixIcon: Icon(
                        _isAppointmentCard
                            ? Icons.event_note_rounded
                            : Icons.confirmation_number_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _appointmentLocationC,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _isAppointmentCard
                          ? 'الموقع'
                          : 'الموقع أو القسم',
                      prefixIcon: const Icon(Icons.place_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detailsDescriptionC,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _isAppointmentCard
                          ? 'ملاحظات أو تعليمات'
                          : 'ملاحظات إضافية',
                      prefixIcon: const Icon(Icons.notes_rounded),
                    ),
                  ),
                  if (_isAppointmentCard) ...[
                    const SizedBox(height: 12),
                    _buildDateTimeField(
                      label: 'بداية الموعد',
                      value: _appointmentStartsAt,
                      icon: Icons.schedule_rounded,
                      onPick: () => _pickDateTime(
                        initialValue: _appointmentStartsAt,
                        onChanged: (value) {
                          setState(() {
                            _appointmentStartsAt = value;
                            _validFrom ??= value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDateTimeField(
                      label: 'نهاية الموعد',
                      value: _appointmentEndsAt,
                      icon: Icons.event_available_rounded,
                      onPick: () => _pickDateTime(
                        initialValue:
                            _appointmentEndsAt ?? _appointmentStartsAt,
                        onChanged: (value) {
                          setState(() {
                            _appointmentEndsAt = value;
                            _validUntil ??= value;
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('إعدادات متقدمة', style: AppTheme.bodyBold),
              subtitle: Text(
                _isTrialMode
                    ? 'في الوضع التجريبي تكون البطاقة خاصة بحسابك تلقائيًا، ويمكنك فقط تعديل الصلاحية والتصميم.'
                    : 'الصلاحية والخصوصية والتصميم والمعاينة. يمكنك تجاهلها إذا كنت تريد إصدارًا سريعًا.',
                style: AppTheme.caption.copyWith(fontSize: 12),
              ),
              children: [
                const SizedBox(height: 12),
                ShwakelCard(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.surfaceVariant,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('نافذة الصلاحية', style: AppTheme.bodyBold),
                      const SizedBox(height: 8),
                      Text(
                        'يمكن تحديد بداية ونهاية لاستخدام البطاقة. إذا تُركت فارغة تبقى البطاقة دون تقييد زمني.',
                        style: AppTheme.caption.copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      _buildDateTimeField(
                        label: 'فعالة من',
                        value: _validFrom,
                        icon: Icons.login_rounded,
                        onPick: () => _pickDateTime(
                          initialValue: _validFrom ?? _appointmentStartsAt,
                          onChanged: (value) =>
                              setState(() => _validFrom = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDateTimeField(
                        label: 'تنتهي في',
                        value: _validUntil,
                        icon: Icons.timer_off_rounded,
                        onPick: () => _pickDateTime(
                          initialValue:
                              _validUntil ?? _appointmentEndsAt ?? _validFrom,
                          onChanged: (value) =>
                              setState(() => _validUntil = value),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isTrialMode &&
                    _canIssuePrivateCards &&
                    _cardType != 'delivery') ...[
                  const SizedBox(height: 16),
                  Text(
                    l.tr('screens_create_card_screen.038'),
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 520;
                      if (isCompact) {
                        return Column(
                          children: [
                            _buildVisibilityChoiceCard(
                              value: 'general',
                              icon: Icons.public_rounded,
                              label: l.tr('screens_create_card_screen.011'),
                            ),
                            const SizedBox(height: 10),
                            _buildVisibilityChoiceCard(
                              value: 'restricted',
                              icon: Icons.lock_rounded,
                              label: l.tr('screens_create_card_screen.010'),
                            ),
                          ],
                        );
                      }
                      return SegmentedButton<String>(
                        segments: [
                          ButtonSegment<String>(
                            value: 'general',
                            icon: const Icon(Icons.public_rounded),
                            label: Text(l.tr('screens_create_card_screen.011')),
                          ),
                          ButtonSegment<String>(
                            value: 'restricted',
                            icon: const Icon(Icons.lock_rounded),
                            label: Text(l.tr('screens_create_card_screen.010')),
                          ),
                        ],
                        selected: {_visibilityScope},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _visibilityScope = selection.first;
                            if (_visibilityScope != 'restricted') {
                              _selectedUsers = [];
                            }
                          });
                        },
                      );
                    },
                  ),
                ],
                if (!_isTrialMode &&
                    _canIssuePrivateCards &&
                    _visibilityScope == 'restricted') ...[
                  const SizedBox(height: 20),
                  ShwakelCard(
                    padding: const EdgeInsets.all(20),
                    color: AppTheme.warning.withValues(alpha: 0.05),
                    borderColor: AppTheme.warning.withValues(alpha: 0.15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_create_card_screen.039'),
                          style: AppTheme.bodyBold,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.tr('screens_create_card_screen.040'),
                          style: AppTheme.caption.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        if (_selectedUsers.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedUsers.map((user) {
                              return Chip(
                                label: Text(
                                  '@${user['username'] ?? user['id']}',
                                ),
                                onDeleted: () {
                                  setState(() {
                                    _selectedUsers.removeWhere(
                                      (item) =>
                                          item['id']?.toString() ==
                                          user['id']?.toString(),
                                    );
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 12),
                        ShwakelButton(
                          label: _selectedUsers.isEmpty
                              ? l.tr('screens_create_card_screen.041')
                              : l.tr('screens_create_card_screen.042'),
                          icon: Icons.group_add_rounded,
                          isSecondary: true,
                          onPressed: _pickPrivateUsers,
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isTrialMode) ...[
                  const SizedBox(height: 16),
                  ShwakelCard(
                    padding: const EdgeInsets.all(16),
                    color: AppTheme.warning.withValues(alpha: 0.05),
                    borderColor: AppTheme.warning.withValues(alpha: 0.15),
                    child: Text(
                      'البطاقات التجريبية تُنشأ كبطاقات خاصة بحسابك فقط، ولا يمكن استخدامها في حساب آخر. بعد التوثيق يمكنك اعتمادها، وقبل ذلك يمكنك حذفها لإرجاع قيمتها إلى الرصيد.',
                      style: AppTheme.bodyText.copyWith(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _buildDesignSettings(),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ShwakelButton(
            label: l.tr('screens_create_card_screen.043'),
            icon: Icons.verified_user_rounded,
            onPressed: _create,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildDesignSettings() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tr('screens_create_card_screen.044'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_create_card_screen.045'),
            style: AppTheme.bodyAction.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleC,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.tr('screens_create_card_screen.046'),
              prefixIcon: const Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stampC,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.tr('screens_create_card_screen.047'),
              prefixIcon: const Icon(Icons.approval_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showLogo,
            title: Text(l.tr('screens_create_card_screen.048')),
            subtitle: Text(
              _hasAccountLogo
                  ? l.tr('screens_create_card_screen.049')
                  : l.tr('screens_create_card_screen.050'),
              style: AppTheme.caption.copyWith(fontSize: 12),
            ),
            onChanged: (value) => setState(() => _showLogo = value),
          ),
          if (_hasAccountLogo)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _useAccountLogo,
              title: Text(l.tr('screens_create_card_screen.051')),
              subtitle: Text(
                l.tr('screens_create_card_screen.052'),
                style: AppTheme.caption.copyWith(fontSize: 12),
              ),
              onChanged: _showLogo
                  ? (value) => setState(() => _useAccountLogo = value)
                  : null,
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showStamp,
            title: Text(l.tr('screens_create_card_screen.053')),
            subtitle: Text(
              l.tr('screens_create_card_screen.054'),
              style: AppTheme.caption.copyWith(fontSize: 12),
            ),
            onChanged: (value) => setState(() => _showStamp = value),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialInfoCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      color: AppTheme.warning.withValues(alpha: 0.07),
      borderColor: AppTheme.warning.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وضع البطاقات التجريبية', style: AppTheme.bodyBold),
          const SizedBox(height: 8),
          Text(
            'هذا الحساب غير موثق بعد، لذلك يتم إنشاء بطاقات تجريبية خاصة بك فقط. مجموع البطاقات غير المستخدمة لا يتجاوز ${CurrencyFormatter.ils(_trialCardsLimit)} وتسجل قيمتها بالسالب على الرصيد.',
            style: AppTheme.bodyAction.copyWith(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _trialInfoChip(
                Icons.account_balance_wallet_rounded,
                'المتبقي ${CurrencyFormatter.ils(_trialCardsRemainingAmount)}',
              ),
              _trialInfoChip(
                Icons.trending_down_rounded,
                'المستخدم ${CurrencyFormatter.ils(_trialCardsOutstandingAmount)}',
              ),
              _trialInfoChip(Icons.lock_rounded, 'خاصة بحسابك'),
              _trialInfoChip(
                Icons.verified_user_rounded,
                'الاعتماد بعد التوثيق',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trialInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
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

  Widget _buildFloatingDesignPreview({required bool isCompact}) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      color: Colors.transparent,
      borderRadius: AppTheme.radiusLg,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: AppTheme.radiusLg,
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.visibility_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'معاينة البطاقة قبل الإصدار',
                    style: AppTheme.bodyBold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 10 : 12),
            SizedBox(
              height: isCompact ? 285 : 345,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isCompact ? 210 : 252),
                  child: _buildPreviewCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final l = context.loc;
    final amount = double.tryParse(_amountC.text) ?? 0;
    final previewCard = VirtualCard(
      id: 'preview',
      barcode: 'SHW-0001-2026',
      value: amount,
      cardType: _cardType,
      visibilityScope: _isTrialMode ? 'restricted' : _visibilityScope,
      createdAt: DateTime.now(),
      details: _currentCardDetails() ?? const {},
    );
    final settings = CardDesignSettings(
      showLogo: _showLogo,
      showStamp: _showStamp,
      logoText: _titleC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.001')
          : _titleC.text.trim(),
      stampText: _stampC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.019')
          : _stampC.text.trim(),
    );
    settings.logoUrl = _useAccountLogo
        ? (_user?['printLogoUrl'])?.toString()
        : null;

    return PrintCardPreview(
      card: previewCard,
      serialNumber: 1,
      printedBy: _resolvedIssuerName(l),
      designSettings: settings,
    );
  }

  Widget _buildRecent() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      color: AppTheme.secondary.withValues(alpha: 0.05),
      child: Column(
        children: [
          const Icon(
            Icons.history_rounded,
            color: AppTheme.secondary,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            l.tr('screens_create_card_screen.060'),
            style: AppTheme.h3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 20),
          _buildRecentRow(
            l.tr('screens_create_card_screen.061'),
            l.tr(
              'screens_create_card_screen.062',
              params: {'count': '${_recent.length}'},
            ),
          ),
          const SizedBox(height: 8),
          _buildRecentRow(
            l.tr('screens_create_card_screen.063'),
            _recent.isNotEmpty
                ? (_recent.first.isPrivate
                      ? l.tr('screens_create_card_screen.010')
                      : l.tr('screens_create_card_screen.011'))
                : '-',
          ),
          const SizedBox(height: 8),
          _buildRecentRow(
            'النوع',
            _recent.isNotEmpty
                ? (_recent.first.isTrial
                      ? 'بطاقة تجريبية'
                      : _cardTypeLabel(l, _recent.first.cardType))
                : '-',
          ),
          const SizedBox(height: 8),
          _buildRecentRow(
            l.tr('screens_create_card_screen.064'),
            _recent.isNotEmpty
                ? (_recent.first.isAppointment && _recent.first.value <= 0
                      ? 'بدون قيمة مالية'
                      : CurrencyFormatter.ils(_recent.first.value))
                : CurrencyFormatter.ils(0),
          ),
          if (_recent.isNotEmpty &&
              _recent.first.title?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _buildRecentRow('العنوان', _recent.first.title!.trim()),
          ],
          if (_recent.isNotEmpty && _recent.first.validUntil != null) ...[
            const SizedBox(height: 8),
            _buildRecentRow('تنتهي', _formatDateTime(_recent.first.validUntil)),
          ],
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 20),
            if (_canUseThermalPrinting) ...[
              ShwakelButton(
                label: 'إعادة طباعة حرارية',
                icon: Icons.local_printshop_rounded,
                isSecondary: true,
                isLoading: _isThermalPrinting,
                onPressed: () => _quickThermalPrintCards(_recent),
              ),
              const SizedBox(height: 10),
            ],
            ShwakelButton(
              label: l.tr('screens_create_card_screen.065'),
              icon: Icons.print_rounded,
              isSecondary: true,
              onPressed: () => _printCards(_recent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentRow(String label, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 320;
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.bodyAction.copyWith(fontSize: 14)),
              const SizedBox(height: 4),
              Text(value, style: AppTheme.bodyBold.copyWith(fontSize: 14)),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyAction.copyWith(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTheme.bodyBold.copyWith(fontSize: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVisibilityChoiceCard({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _visibilityScope == value;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() {
          _visibilityScope = value;
          if (_visibilityScope != 'restricted') {
            _selectedUsers = [];
          }
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyBold.copyWith(
                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}
