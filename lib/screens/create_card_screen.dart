import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class CreateCardScreen extends StatefulWidget {
  const CreateCardScreen({super.key});

  @override
  State<CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends State<CreateCardScreen> {
  static const int _cardsPerA4Page = 30;
  static const double _trialCardsLimit = 10;
  static const int _printTitleMaxLength = 24;
  static const int _valueUnitMaxLength = 10;
  static const Map<String, int> _cardTypeDisplayOrder = {
    'standard': 0,
    'delivery': 1,
    'single_use': 2,
    'appointment': 3,
    'queue': 4,
    'subscription': 5,
    'attendance': 6,
  };

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final PDFService _pdfService = PDFService();
  final TextEditingController _amountC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController(
    text: '$_cardsPerA4Page',
  );
  final TextEditingController _titleC = TextEditingController();
  final TextEditingController _stampC = TextEditingController();
  final TextEditingController _valueUnitC = TextEditingController();
  final TextEditingController _detailsTitleC = TextEditingController();
  final TextEditingController _detailsDescriptionC = TextEditingController();
  final TextEditingController _appointmentLocationC = TextEditingController();
  final TextEditingController _allowedPhoneC = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingUser = true;
  bool _isAuthorized = false;
  bool _showLogo = true;
  bool _showStamp = true;
  bool _useAccountLogo = true;
  String _cardType = '';
  String _visibilityScope = 'general';
  DateTime? _validFrom;
  DateTime? _validUntil;
  DateTime? _appointmentStartsAt;
  DateTime? _appointmentEndsAt;
  Map<String, dynamic>? _user;
  Map<String, dynamic> _feeSettings = const {};
  List<VirtualCard> _recent = [];
  List<Map<String, dynamic>> _selectedUsers = [];
  List<String> _selectedPhoneNumbers = [];

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
    _valueUnitC.dispose();
    _detailsTitleC.dispose();
    _detailsDescriptionC.dispose();
    _appointmentLocationC.dispose();
    _allowedPhoneC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = context.loc;
    try {
      final user = await _authService.currentUser();
      Map<String, dynamic> feeSettings = const {};
      try {
        feeSettings = Map<String, dynamic>.from(
          await _apiService.getFeeSettings(),
        );
      } catch (_) {
        feeSettings = const {};
      }
      if (!mounted) {
        return;
      }
      final permissions = AppPermissions.fromUser(user);
      setState(() {
        _user = user;
        _feeSettings = feeSettings;
        _isAuthorized = permissions.canIssueCards;
        final isTrialMode = user?['canIssueTrialCards'] == true;
        final accountName = UserDisplayName.fromMap(
          user,
          fallback: l.tr('screens_create_card_screen.001'),
        );
        if (_titleC.text.trim().isEmpty ||
            _titleC.text.trim() == l.tr('screens_create_card_screen.001')) {
          _titleC.text = accountName;
        }
        _useAccountLogo =
            user?['printLogoUrl']?.toString().trim().isNotEmpty == true;
        final issuableCardTypes = _issuableCardTypesFromUser(user);
        if (_cardType.isNotEmpty && !issuableCardTypes.contains(_cardType)) {
          _cardType = '';
        }
        if (isTrialMode) {
          _visibilityScope = 'restricted';
          if ((_qtyC.text.trim()).isEmpty ||
              (int.tryParse(_qtyC.text.trim()) ?? 0) % _cardsPerA4Page == 0) {
            final minQuantity =
                (user?['cardOperationMinQuantity'] as num?)?.toInt() ?? 1;
            _qtyC.text = '${minQuantity < 1 ? 1 : minQuantity}';
          }
        } else if (!_isBalanceCard) {
          _visibilityScope = 'restricted';
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
  bool get _canPickTargetedUsers =>
      _canIssuePrivateCards || _requiresTargetedPrivateCard;

  bool get _canRequestCardPrinting => _appPermissions.canRequestCardPrinting;

  bool get _hasAccountLogo =>
      _user?['printLogoUrl']?.toString().trim().isNotEmpty == true;

  bool get _isAppointmentCard => _cardType == 'appointment';
  bool get _isQueueCard => _cardType == 'queue';
  bool get _isSubscriptionCard => _cardType == 'subscription';
  bool get _isAttendanceCard => _cardType == 'attendance';

  bool get _hasSelectedCardType => _cardType.trim().isNotEmpty;
  bool get _isBalanceCard => _cardType == 'standard' || _cardType == 'delivery';
  bool get _requiresTargetedPrivateCard => !_isBalanceCard;
  String get _effectiveVisibilityScope =>
      _isTrialMode || _requiresTargetedPrivateCard
      ? 'restricted'
      : _visibilityScope;
  bool get _needsTypeDetails =>
      _isAppointmentCard ||
      _isQueueCard ||
      _isSubscriptionCard ||
      _isAttendanceCard;
  bool get _isTrialMode => _user?['canIssueTrialCards'] == true;
  int get _minimumCardQuantity {
    final raw = (_user?['cardOperationMinQuantity'] as num?)?.toInt() ?? 1;
    return raw < 1 ? 1 : raw;
  }

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

  List<String> get _sortedIssuableCardTypes {
    final values = [..._issuableCardTypes];
    values.sort(
      (a, b) => (_cardTypeDisplayOrder[a] ?? 999).compareTo(
        _cardTypeDisplayOrder[b] ?? 999,
      ),
    );
    return values;
  }

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
    return const [
      'standard',
      'delivery',
      'single_use',
      'appointment',
      'queue',
      'subscription',
      'attendance',
    ];
  }

  String _cardTypeLabel(AppLocalizer l, String type) {
    switch (type) {
      case 'single_use':
        return l.tr('screens_create_card_screen.003');
      case 'delivery':
        return l.tr('shared.delivery_card_label');
      case 'appointment':
        return l.tr('screens_create_card_screen.069');
      case 'queue':
        return l.tr('screens_create_card_screen.070');
      case 'subscription':
        return 'بطاقة اشتراك';
      case 'attendance':
        return 'بطاقة حضور وانصراف';
      default:
        return l.tr('screens_create_card_screen.002');
    }
  }

  IconData _cardTypeIcon(String type) {
    switch (type) {
      case 'single_use':
        return Icons.confirmation_number_rounded;
      case 'delivery':
        return Icons.local_shipping_rounded;
      case 'appointment':
        return Icons.event_available_rounded;
      case 'queue':
        return Icons.people_alt_rounded;
      case 'subscription':
        return Icons.card_membership_rounded;
      case 'attendance':
        return Icons.badge_rounded;
      default:
        return Icons.credit_card_rounded;
    }
  }

  String _cardTypeDescription(String type) {
    switch (type) {
      case 'single_use':
        return 'بطاقة خاصة تظهر ضمن البطاقات الخاصة بدون قيمة مالية.';
      case 'delivery':
        return 'بطاقة مخصصة للتسليم مع رصيد قابل للاستخدام.';
      case 'appointment':
        return 'تذكرة موعد بوقت محدد ويمكن ربطها بتعليمات.';
      case 'queue':
        return 'تذكرة دور أو خدمة مع بيانات تنظيمية واضحة.';
      case 'subscription':
        return 'بطاقة اشتراك بمدة محددة، تظهر فعالة باللون الأخضر داخل فترة الاشتراك.';
      case 'attendance':
        return 'بطاقة تعريف حضور وانصراف قابلة للربط مع أنظمة الموظفين والبصمة.';
      default:
        return 'بطاقة رصيد قياسية مناسبة للاستخدام العام.';
    }
  }

  String _typeDetailsTitle() {
    if (_isAppointmentCard) return 'تفاصيل الموعد المطلوبة';
    if (_isQueueCard) return 'تفاصيل تذكرة الطابور';
    if (_isSubscriptionCard) return 'تفاصيل الاشتراك';
    if (_isAttendanceCard) return 'تفاصيل الحضور والانصراف';
    return 'تفاصيل البطاقة';
  }

  String _typeTitleFieldLabel() {
    if (_isAppointmentCard) return 'عنوان الموعد';
    if (_isQueueCard) return 'اسم الخدمة أو الطابور';
    if (_isSubscriptionCard) return 'اسم الاشتراك';
    if (_isAttendanceCard) return 'اسم الموظف أو عنوان البطاقة';
    return 'العنوان';
  }

  String _typeLocationFieldLabel() {
    if (_isAppointmentCard) return 'الموقع';
    if (_isQueueCard) return 'الموقع أو القسم';
    if (_isSubscriptionCard) return 'الفرع أو الجهة';
    if (_isAttendanceCard) return 'القسم أو موقع الدوام';
    return 'الموقع';
  }

  String _typeDescriptionFieldLabel() {
    if (_isAppointmentCard) return 'ملاحظات أو تعليمات';
    if (_isSubscriptionCard) return 'تفاصيل الاشتراك';
    if (_isAttendanceCard) return 'مرجع الربط أو نظام الحضور';
    return 'ملاحظات إضافية';
  }

  double _feeAmount(String key) =>
      (_feeSettings[key] as num?)?.toDouble() ?? 0.0;

  bool get _isPrivateIssuance => _effectiveVisibilityScope == 'restricted';

  double _issueFeePerCardForType(String type, {required bool isPrivate}) {
    if (_isTrialMode) {
      return 0;
    }
    final normalizedType = type.trim().toLowerCase();
    var fee = switch (normalizedType) {
      'single_use' => _feeAmount('singleUseTicketIssueCost'),
      'appointment' => _feeAmount('appointmentTicketIssueCost'),
      'queue' => _feeAmount('queueTicketIssueCost'),
      'subscription' => _feeAmount('subscriptionCardIssueCost'),
      'attendance' => _feeAmount('attendanceCardIssueCost'),
      'delivery' => _feeAmount('deliveryCardIssueCost'),
      _ => _feeAmount('standardCardIssueCost'),
    };
    final isTicket =
        normalizedType == 'single_use' ||
        normalizedType == 'appointment' ||
        normalizedType == 'queue' ||
        normalizedType == 'subscription' ||
        normalizedType == 'attendance';
    if (isPrivate && !isTicket) {
      fee += _feeAmount('privateCardIssueCost');
    }
    return fee > 0 ? fee : 0;
  }

  double get _currentIssueFeePerCard =>
      _issueFeePerCardForType(_cardType, isPrivate: _isPrivateIssuance);

  double get _currentChargedIssueFeePerCard {
    if (_isTrialMode) {
      return 0;
    }
    if (_isBalanceCard && !_isPrivateIssuance) {
      return 0;
    }
    return _currentIssueFeePerCard;
  }

  double get _currentDeferredIssueFeePerCard =>
      (_currentIssueFeePerCard - _currentChargedIssueFeePerCard).clamp(
        0,
        double.infinity,
      );

  double get _currentCardFaceValue {
    final amount = double.tryParse(_amountC.text.trim()) ?? 0;
    return _isBalanceCard || _isAppointmentCard ? amount : 0;
  }

  double get _currentChargeNowPerCard =>
      _currentCardFaceValue + _currentChargedIssueFeePerCard;

  double get _currentTotalChargeNow {
    final quantity = int.tryParse(_qtyC.text.trim()) ?? 0;
    return _currentChargeNowPerCard * quantity;
  }

  String? _validateAmountForCardType(double amount) {
    if (_isBalanceCard) {
      return amount > 0
          ? null
          : context.loc.tr('screens_create_card_screen.071');
    }

    if (_isAppointmentCard && amount < 0) {
      return context.loc.tr('screens_create_card_screen.072');
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
    if (!_hasSelectedCardType) {
      await AppAlertService.showError(
        context,
        title: 'اختر نوع البطاقة',
        message: 'حدد نوع البطاقة أولًا حتى تظهر تفاصيل الإنشاء والدفع.',
      );
      return;
    }
    final enteredAmount = double.tryParse(_amountC.text) ?? 0;
    final amount = (_isBalanceCard || _isAppointmentCard) ? enteredAmount : 0.0;
    final quantity = int.tryParse(_qtyC.text) ?? 0;
    final isPrivate = _effectiveVisibilityScope == 'restricted';

    if (quantity <= 0) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.004'),
        message: l.tr('screens_create_card_screen.073'),
      );
      return;
    }

    if (quantity < _minimumCardQuantity) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.004'),
        message: l.tr(
          'screens_create_card_screen.074',
          params: {'count': '$_minimumCardQuantity'},
        ),
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
        title: l.tr('screens_create_card_screen.075'),
        message: l.tr(
          'screens_create_card_screen.076',
          params: {'count': '$_cardsPerA4Page'},
        ),
      );
      return;
    }

    if (_isTrialMode) {
      final totalAmount = amount * quantity;
      if (totalAmount > _trialCardsRemainingAmount) {
        await AppAlertService.showError(
          context,
          title: l.tr('screens_create_card_screen.077'),
          message: l.tr(
            'screens_create_card_screen.078',
            params: {
              'amount': CurrencyFormatter.ils(_trialCardsRemainingAmount),
            },
          ),
        );
        return;
      }
    }

    if (_isAppointmentCard) {
      if (_detailsTitleC.text.trim().isEmpty || _appointmentStartsAt == null) {
        await AppAlertService.showError(
          context,
          title: l.tr('screens_create_card_screen.079'),
          message: l.tr('screens_create_card_screen.080'),
        );
        return;
      }

      if (_appointmentEndsAt != null &&
          !_appointmentEndsAt!.isAfter(_appointmentStartsAt!)) {
        await AppAlertService.showError(
          context,
          title: l.tr('screens_create_card_screen.081'),
          message: l.tr('screens_create_card_screen.082'),
        );
        return;
      }
    }

    if (_isQueueCard && _detailsTitleC.text.trim().isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.083'),
        message: l.tr('screens_create_card_screen.084'),
      );
      return;
    }

    if (_isSubscriptionCard) {
      if (_detailsTitleC.text.trim().isEmpty) {
        await AppAlertService.showError(
          context,
          title: 'بيانات الاشتراك غير مكتملة',
          message: 'أدخل اسم الاشتراك قبل إصدار البطاقة.',
        );
        return;
      }
      if (_validFrom == null || _validUntil == null) {
        await AppAlertService.showError(
          context,
          title: 'مدة الاشتراك مطلوبة',
          message: 'حدد بداية ونهاية الاشتراك قبل إصدار البطاقة.',
        );
        return;
      }
    }

    if (_isAttendanceCard && _detailsTitleC.text.trim().isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'بيانات الحضور غير مكتملة',
        message: 'أدخل اسم الموظف أو عنوان بطاقة الحضور والانصراف.',
      );
      return;
    }

    if (_validFrom != null &&
        _validUntil != null &&
        !_validUntil!.isAfter(_validFrom!)) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_create_card_screen.085'),
        message: l.tr('screens_create_card_screen.086'),
      );
      return;
    }

    final confirmed = await _showIssuePreviewConfirmation(
      amount: amount,
      quantity: quantity,
      isPrivate: isPrivate,
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
          visibilityScope: _effectiveVisibilityScope,
          printDesign: _currentPrintDesign(),
          validFrom: _validFrom?.toUtc().toIso8601String(),
          validUntil: _validUntil?.toUtc().toIso8601String(),
          cardDetails: _currentCardDetails(),
          otpCode: securityResult.otpCode,
          localAuthMethod: securityResult.method,
          allowedUserIds: _selectedAllowedUserIds(),
          allowedUserPhones: _selectedAllowedUserPhones(),
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
        'cardType': _cardType,
        'cardDetails': _currentCardDetails(),
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
          title: 'تعذر إصدار البطاقات التجريبية',
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

  Future<bool> _showIssuePreviewConfirmation({
    required double amount,
    required int quantity,
    required bool isPrivate,
  }) async {
    final l = context.loc;
    final typeLabel = _cardTypeLabel(l, _cardType);
    final visibilityLabel = isPrivate
        ? l.tr('screens_create_card_screen.010')
        : l.tr('screens_create_card_screen.011');
    final valueLabel = _cardValueLabel(l, amount);
    final targetCount = _selectedUsers.length + _selectedPhoneNumbers.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('معاينة الدفعة قبل التأكيد'),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          ? (targetCount == 0
                                ? 'ستكون هذه البطاقات خاصة بحسابك فقط.'
                                : l.tr(
                                    'screens_create_card_screen.015',
                                    params: {'count': '$targetCount'},
                                  ))
                          : '',
                    },
                  ),
                  textDirection: TextDirection.rtl,
                  style: AppTheme.bodyAction.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                _buildPreviewCard(),
                const SizedBox(height: 16),
                ShwakelCard(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.surfaceVariant,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تفاصيل البطاقات', style: AppTheme.bodyBold),
                      const SizedBox(height: 10),
                      _buildPreviewSummaryRow('النوع', typeLabel),
                      const SizedBox(height: 8),
                      _buildPreviewSummaryRow('القيمة', valueLabel),
                      const SizedBox(height: 8),
                      _buildPreviewSummaryRow('العدد', '$quantity'),
                      const SizedBox(height: 8),
                      _buildPreviewSummaryRow('النطاق', visibilityLabel),
                      if (_detailsTitleC.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildPreviewSummaryRow(
                          'العنوان',
                          _detailsTitleC.text.trim(),
                        ),
                      ],
                      if (_formatValidityWindow().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildPreviewSummaryRow(
                          'الصلاحية',
                          _formatValidityWindow(),
                        ),
                      ],
                      if (_isAppointmentCard &&
                          _appointmentStartsAt != null) ...[
                        const SizedBox(height: 8),
                        _buildPreviewSummaryRow(
                          'الموعد',
                          '${_formatDateTime(_appointmentStartsAt)}${_appointmentEndsAt != null ? ' - ${_formatDateTime(_appointmentEndsAt)}' : ''}',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildIssueCostSummary(),
              ],
            ),
          ),
        ),
        actions: [
          Row(
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
        ],
      ),
    );
    return confirmed == true;
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
      'valueUnitText': _valueUnitC.text.trim(),
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
    } else if (_isSubscriptionCard) {
      details['ticketKind'] = 'subscription';
      details['subscriptionName'] = _detailsTitleC.text.trim();
      if (_detailsDescriptionC.text.trim().isNotEmpty) {
        details['subscriptionDetails'] = _detailsDescriptionC.text.trim();
      }
    } else if (_isAttendanceCard) {
      details['ticketKind'] = 'attendance';
      details['employeeName'] = _detailsTitleC.text.trim();
      if (_detailsDescriptionC.text.trim().isNotEmpty) {
        details['integrationReference'] = _detailsDescriptionC.text.trim();
      }
    }
    return details.isEmpty ? null : details;
  }

  String _cardValueLabel(AppLocalizer l, double amount) {
    if (_cardType == 'single_use' || _isQueueCard || _isAttendanceCard) {
      return amount <= 0
          ? 'تذكرة استخدام تنظيمي'
          : CurrencyFormatter.ils(amount);
    }
    if ((_isAppointmentCard || _isSubscriptionCard) && amount <= 0) {
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

  List<String> _selectedAllowedUserPhones() {
    return _selectedPhoneNumbers
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty)
        .toList();
  }

  void _addAllowedPhoneFromInput() {
    final raw = _allowedPhoneC.text.trim();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      return;
    }

    final normalized = raw.startsWith('+') ? '+$digits' : digits;
    if (_selectedPhoneNumbers.any((item) => item == normalized)) {
      _allowedPhoneC.clear();
      return;
    }

    setState(() {
      _selectedPhoneNumbers = [..._selectedPhoneNumbers, normalized];
      _allowedPhoneC.clear();
    });
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

  CardDesignSettings _currentPdfDesignSettings() {
    final l = context.loc;
    final settings = CardDesignSettings(
      showLogo: _showLogo,
      showStamp: _showStamp,
      logoText: _titleC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.001')
          : _titleC.text.trim(),
      stampText: _stampC.text.trim().isEmpty
          ? l.tr('screens_create_card_screen.019')
          : _stampC.text.trim(),
      valueUnitText: _valueUnitC.text.trim(),
    );
    settings.logoUrl = (_showLogo && _useAccountLogo)
        ? (_user?['printLogoUrl'])?.toString()
        : null;
    return settings;
  }

  void _applyCurrentPdfDesignSettings() {
    _pdfService.setDesignSettings(_currentPdfDesignSettings());
  }

  List<VirtualCard> _cardsWithPrintFallbacks(List<VirtualCard> cards) {
    final currentAmount = double.tryParse(_amountC.text.trim()) ?? 0;
    final currentDetails = _currentCardDetails() ?? const <String, dynamic>{};
    return cards
        .map(
          (card) => card.copyWith(
            value: card.value > 0 ? card.value : currentAmount,
            cardType: card.cardType.trim().isNotEmpty
                ? card.cardType
                : (_hasSelectedCardType ? _cardType : 'standard'),
            visibilityScope: card.visibilityScope.trim().isNotEmpty
                ? card.visibilityScope
                : _effectiveVisibilityScope,
            details: card.details.isNotEmpty ? card.details : currentDetails,
          ),
        )
        .toList();
  }

  Future<void> _printCards(
    List<VirtualCard> cards, {
    bool requireSecurity = true,
  }) async {
    if (!await _showCardOutputPreviewConfirmation(
      cards,
      confirmLabel: 'تأكيد الطباعة',
      icon: Icons.print_rounded,
    )) {
      return;
    }
    if (requireSecurity && !await _confirmCardOutputSecurity()) {
      return;
    }
    if (!mounted) {
      return;
    }

    final l = context.loc;
    final printedBy = UserDisplayName.fromMap(_user);

    _applyCurrentPdfDesignSettings();
    try {
      final exportCards = _cardsWithPrintFallbacks(cards);
      // Validate that we can generate the PDF sheet before opening the printer dialog.
      final pdf = await _pdfService.createMultiCardPDF(
        exportCards,
        printedBy: printedBy,
      );
      final bytes = await pdf.save();
      if (bytes.isEmpty) {
        throw Exception('تعذر توليد ملف الطباعة.');
      }
      // Extra guard: attempt rasterizing page 1 to ensure rendering works.
      try {
        final stream = Printing.raster(bytes, pages: const [0], dpi: 110);
        await stream.first;
      } catch (_) {
        throw Exception('تعذر تجهيز معاينة الطباعة. يرجى المحاولة لاحقاً.');
      }
      await _pdfService.printPdfBytes(bytes);
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

  Future<bool> _showCardOutputPreviewConfirmation(
    List<VirtualCard> cards, {
    required String confirmLabel,
    required IconData icon,
  }) async {
    if (cards.isEmpty) {
      return false;
    }
    final previewCards = _cardsWithPrintFallbacks(cards);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('معاينة البطاقات قبل الإخراج'),
        contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardPreviewWidget(previewCards.first, serialNumber: 1),
                const SizedBox(height: 16),
                _buildIssuedCardsDetails(previewCards),
              ],
            ),
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('رجوع'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShwakelButton(
                  label: confirmLabel,
                  icon: icon,
                  onPressed: () => Navigator.pop(dialogContext, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _saveCardsPdf(List<VirtualCard> cards) async {
    if (!await _showCardOutputPreviewConfirmation(
      cards,
      confirmLabel: 'تأكيد التنزيل',
      icon: Icons.picture_as_pdf_rounded,
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    final l = context.loc;
    final printedBy = UserDisplayName.fromMap(_user);
    _applyCurrentPdfDesignSettings();
    try {
      final exportCards = _cardsWithPrintFallbacks(cards);
      final pdf = exportCards.length == 1
          ? await _pdfService.createCardPDF(
              exportCards.first,
              printedBy: printedBy,
              serialNumber: 1,
            )
          : await _pdfService.createMultiCardPDF(
              exportCards,
              printedBy: printedBy,
            );
      final timestamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final file = await _pdfService.savePDF(pdf, 'shwakil_cards_$timestamp');
      if (!mounted) {
        return;
      }
      await AppAlertService.showInfo(
        context,
        title: 'تم حفظ نسخة PDF',
        message: 'تم تنزيل الملف في:\n${file.path}',
      );
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

  String _resolvedIssuerName(AppLocalizer l) {
    return UserDisplayName.fromMap(
      _user,
      fallback: l.tr('screens_create_card_screen.001'),
    );
  }

  void _showSuccess(List<VirtualCard> cards) {
    final l = context.loc;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_create_card_screen.020')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.tr(
                    'screens_create_card_screen.021',
                    params: {'count': '${cards.length}'},
                  ),
                ),
                const SizedBox(height: 14),
                if (cards.isNotEmpty) _buildIssuedCardsDetails(cards),
              ],
            ),
          ),
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShwakelButton(
                label: 'تنزيل نسخة PDF',
                icon: Icons.picture_as_pdf_rounded,
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _saveCardsPdf(cards);
                },
              ),
              if (_canRequestCardPrinting) ...[
                const SizedBox(height: 8),
                ShwakelButton(
                  label: 'معاينة ثم طباعة',
                  icon: Icons.print_rounded,
                  isSecondary: true,
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _printCards(cards, requireSecurity: false);
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_create_card_screen.022')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIssuedCardsDetails(List<VirtualCard> cards) {
    final l = context.loc;
    final first = cards.first;
    final totalFaceValue = cards.fold<double>(
      0,
      (sum, card) => sum + card.value,
    );
    final totalIssueCost = cards.fold<double>(
      0,
      (sum, card) => sum + card.issueCost,
    );
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الدفعة المنشأة', style: AppTheme.bodyBold),
          const SizedBox(height: 10),
          _buildPreviewSummaryRow('النوع', _cardTypeLabel(l, first.cardType)),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow('عدد البطاقات', '${cards.length}'),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'إجمالي القيم',
            CurrencyFormatter.ils(totalFaceValue),
          ),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'إجمالي الرسوم',
            CurrencyFormatter.ils(totalIssueCost),
          ),
          if (first.title?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _buildPreviewSummaryRow('العنوان', first.title!.trim()),
          ],
          if (first.validUntil != null) ...[
            const SizedBox(height: 8),
            _buildPreviewSummaryRow('تنتهي', _formatDateTime(first.validUntil)),
          ],
        ],
      ),
    );
  }

  Future<void> _pickPrivateUsers() async {
    if (_isTrialMode) {
      await AppAlertService.showInfo(
        context,
        title: 'اختيار المستفيدين غير متاح',
        message:
            'الحساب غير موثق، لذلك تكون البطاقات الخاصة مخصصة لحسابك فقط ولا يمكن البحث عن مستخدمين آخرين.',
      );
      return;
    }

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
                          label: Text(_userOptionLabel(user)),
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
                          title: Text(_userOptionLabel(user)),
                          subtitle: Text(_userOptionSubtitle(l, user)),
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

  String _userOptionLabel(Map<String, dynamic> user) {
    final displayName = user['displayName']?.toString().trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    return UserDisplayName.fromMap(
      user,
      fallback: user['username']?.toString().trim().isNotEmpty == true
          ? user['username'].toString()
          : '${user['id'] ?? ''}',
    );
  }

  String _userOptionSubtitle(AppLocalizer l, Map<String, dynamic> user) {
    final username = user['username']?.toString().trim() ?? '';
    final id = user['id']?.toString().trim() ?? '-';
    if (username.isNotEmpty) {
      return '@$username - ${l.tr('screens_create_card_screen.027', params: {'id': id})}';
    }

    return l.tr('screens_create_card_screen.027', params: {'id': id});
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
      length: 3,
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
              const Tab(
                icon: Icon(Icons.visibility_rounded),
                text: 'المعاينة والطباعة',
              ),
            ],
          ),
        ),
        drawer: const AppSidebar(),
        body: TabBarView(
          children: [
            SingleChildScrollView(
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
            SingleChildScrollView(
              child: ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_buildPreviewAndPrintWorkspace()],
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
          _buildCardTypeSelector(),
          const SizedBox(height: 16),
          if (!_hasSelectedCardType) ...[
            _buildCardTypeEmptyState(),
          ] else ...[
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
                    ? 'الحد الأدنى $_minimumCardQuantity بطاقة. يمكنك إصدار أي عدد من البطاقات ما دام مجموعها لا يتجاوز ${CurrencyFormatter.formatAmount(_trialCardsRemainingAmount)}.'
                    : 'الحد الأدنى $_minimumCardQuantity بطاقة. أدخل مضاعفات $_cardsPerA4Page فقط مثل $_cardsPerA4Page أو ${_cardsPerA4Page * 2} أو ${_cardsPerA4Page * 3}.',
              ),
            ),
            const SizedBox(height: 16),
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
                    ((_isAppointmentCard || _isSubscriptionCard)
                            ? AppTheme.primary
                            : AppTheme.secondary)
                        .withValues(alpha: 0.05),
                borderColor:
                    ((_isAppointmentCard || _isSubscriptionCard)
                            ? AppTheme.primary
                            : AppTheme.secondary)
                        .withValues(alpha: 0.15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_typeDetailsTitle(), style: AppTheme.bodyBold),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _detailsTitleC,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _typeTitleFieldLabel(),
                        prefixIcon: Icon(_cardTypeIcon(_cardType)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _appointmentLocationC,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _typeLocationFieldLabel(),
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
                        labelText: _typeDescriptionFieldLabel(),
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
                    if (_isSubscriptionCard) ...[
                      const SizedBox(height: 12),
                      _buildDateTimeField(
                        label: 'بداية الاشتراك',
                        value: _validFrom,
                        icon: Icons.play_circle_outline_rounded,
                        onPick: () => _pickDateTime(
                          initialValue: _validFrom,
                          onChanged: (value) =>
                              setState(() => _validFrom = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDateTimeField(
                        label: 'نهاية الاشتراك',
                        value: _validUntil,
                        icon: Icons.event_busy_rounded,
                        onPick: () => _pickDateTime(
                          initialValue: _validUntil ?? _validFrom,
                          onChanged: (value) =>
                              setState(() => _validUntil = value),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('إعدادات متقدمة', style: AppTheme.bodyBold),
                subtitle: Text(
                  _isTrialMode
                      ? 'في الوضع التجريبي تكون البطاقة خاصة بحسابك تلقائيًا، ويمكنك تعديل الصلاحية من هنا والتصميم من تبويب المعاينة.'
                      : 'الصلاحية والخصوصية. إعدادات التصميم والمعاينة موجودة في تبويب المعاينة والطباعة.',
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
                      _isBalanceCard &&
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
                              label: Text(
                                l.tr('screens_create_card_screen.011'),
                              ),
                            ),
                            ButtonSegment<String>(
                              value: 'restricted',
                              icon: const Icon(Icons.lock_rounded),
                              label: Text(
                                l.tr('screens_create_card_screen.010'),
                              ),
                            ),
                          ],
                          selected: {_visibilityScope},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _visibilityScope = selection.first;
                              if (_visibilityScope != 'restricted') {
                                _selectedUsers = [];
                                _selectedPhoneNumbers = [];
                              }
                            });
                          },
                        );
                      },
                    ),
                  ],
                  if (!_isTrialMode && _requiresTargetedPrivateCard) ...[
                    const SizedBox(height: 16),
                    ShwakelCard(
                      padding: const EdgeInsets.all(16),
                      color: AppTheme.warning.withValues(alpha: 0.05),
                      borderColor: AppTheme.warning.withValues(alpha: 0.15),
                      child: Text(
                        'هذا النوع من التذاكر خاص دائمًا. اختر المستفيدين المحددين قبل الإصدار، ولن تظهر التذكرة للعامة.',
                        style: AppTheme.bodyText.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                  if (!_isTrialMode &&
                      _canPickTargetedUsers &&
                      _effectiveVisibilityScope == 'restricted') ...[
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
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _allowedPhoneC,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'رقم هاتف المستفيد',
                                    prefixIcon: Icon(Icons.phone_rounded),
                                  ),
                                  onSubmitted: (_) =>
                                      _addAllowedPhoneFromInput(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton.filledTonal(
                                onPressed: _addAllowedPhoneFromInput,
                                icon: const Icon(Icons.add_rounded),
                                tooltip: 'إضافة الرقم',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_selectedPhoneNumbers.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedPhoneNumbers.map((phone) {
                                return Chip(
                                  avatar: const Icon(Icons.phone_rounded),
                                  label: Text(phone),
                                  onDeleted: () {
                                    setState(() {
                                      _selectedPhoneNumbers.remove(phone);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          if (_selectedPhoneNumbers.isNotEmpty)
                            const SizedBox(height: 12),
                          if (_selectedUsers.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedUsers.map((user) {
                                return Chip(
                                  label: Text(_userOptionLabel(user)),
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
                ],
              ),
            ),
            const SizedBox(height: 28),
            ShwakelButton(
              label: 'إصدار الدفعة الآن',
              icon: Icons.verified_user_rounded,
              onPressed: _create,
              isLoading: _isLoading,
            ),
          ],
        ],
      ),
    );
  }

  void _selectCardType(String type) {
    setState(() {
      _cardType = type;
      if (_requiresTargetedPrivateCard) {
        _visibilityScope = 'restricted';
      } else if (!_isTrialMode && _cardType == 'standard') {
        // Default to public issuance for standard balance cards.
        _visibilityScope = 'general';
      } else if (_cardType == 'delivery') {
        _visibilityScope = 'general';
        _selectedUsers = [];
        _selectedPhoneNumbers = [];
      }
      if (_cardType != 'appointment') {
        _appointmentStartsAt = null;
        _appointmentEndsAt = null;
      }
      if (!_needsTypeDetails) {
        _appointmentLocationC.clear();
        _detailsTitleC.clear();
        _detailsDescriptionC.clear();
      }
      if (_cardType == 'single_use' && _detailsTitleC.text.trim().isEmpty) {
        _detailsTitleC.text = 'بطاقة خاصة';
      }
    });
  }

  void _clearSelectedCardType() {
    setState(() {
      _cardType = '';
      _visibilityScope = _isTrialMode ? 'restricted' : 'general';
      _validFrom = null;
      _validUntil = null;
      _appointmentStartsAt = null;
      _appointmentEndsAt = null;
      _appointmentLocationC.clear();
      _detailsTitleC.clear();
      _detailsDescriptionC.clear();
      _selectedUsers = [];
      _selectedPhoneNumbers = [];
    });
  }

  Widget _buildCardTypeEmptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      color: AppTheme.surfaceVariant,
      borderColor: AppTheme.border,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(Icons.touch_app_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'اختر نوع البطاقة أولًا. بعد الاختيار ستظهر حقول الإنشاء ومعاينة الدفع فقط لهذا النوع.',
              style: AppTheme.bodyAction.copyWith(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTypeSelector() {
    final l = context.loc;
    final visibleTypes = _hasSelectedCardType
        ? _sortedIssuableCardTypes.where((type) => type == _cardType).toList()
        : _sortedIssuableCardTypes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.tr('screens_create_card_screen.034'), style: AppTheme.bodyBold),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 620;
            final cardWidth = isCompact
                ? constraints.maxWidth
                : ((constraints.maxWidth - 24) / 3).clamp(240.0, 320.0);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: visibleTypes.map((type) {
                final isSelected = _cardType == type;
                final fee = _issueFeePerCardForType(
                  type,
                  isPrivate: _effectiveVisibilityScope == 'restricted',
                );
                return SizedBox(
                  width: cardWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _selectCardType(type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: 0.08)
                            : AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.border,
                          width: isSelected ? 1.4 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primarySoft
                                      : AppTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _cardTypeIcon(type),
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _cardTypeLabel(l, type),
                                  style: AppTheme.bodyBold,
                                ),
                              ),
                              if (isSelected)
                                IconButton.filledTonal(
                                  tooltip: 'تغيير نوع البطاقة',
                                  onPressed: _clearSelectedCardType,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _cardTypeDescription(type),
                            style: AppTheme.caption.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(
                              fee > 0
                                  ? 'رسوم الإصدار: ${CurrencyFormatter.ils(fee)} لكل بطاقة'
                                  : 'بدون رسوم إصدار مباشرة',
                              style: AppTheme.caption.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildIssueCostSummary() {
    final quantity = int.tryParse(_qtyC.text.trim()) ?? 0;
    final isDeferred = !_isTrialMode && _isBalanceCard && !_isPrivateIssuance;
    final note = _isTrialMode
        ? 'في البطاقات التجريبية يتم احتساب قيمة البطاقة فقط ضمن الحد المتاح لهذا الحساب.'
        : isDeferred
        ? 'رسوم الإصدار لهذه البطاقة لا تُخصم الآن، وتُحتسب لاحقًا عند استخدام البطاقة.'
        : 'رسوم الإصدار لهذه العملية تُضاف ضمن المبلغ المخصوم الآن.';

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      color: AppTheme.secondary.withValues(alpha: 0.05),
      borderColor: AppTheme.secondary.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ملخص الدفع والرسوم', style: AppTheme.bodyBold),
          const SizedBox(height: 6),
          Text(
            'راجع ما سيتم خصمه الآن لكل بطاقة وفي إجمالي العملية قبل المتابعة.',
            style: AppTheme.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 14),
          _buildPreviewSummaryRow(
            'قيمة البطاقة الواحدة',
            CurrencyFormatter.ils(_currentCardFaceValue),
          ),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'رسوم الإصدار لكل بطاقة',
            CurrencyFormatter.ils(_currentIssueFeePerCard),
          ),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'المخصوم الآن لكل بطاقة',
            CurrencyFormatter.ils(_currentChargeNowPerCard),
          ),
          if (_currentDeferredIssueFeePerCard > 0) ...[
            const SizedBox(height: 8),
            _buildPreviewSummaryRow(
              'الرسوم المؤجلة لكل بطاقة',
              CurrencyFormatter.ils(_currentDeferredIssueFeePerCard),
            ),
          ],
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'إجمالي الخصم الآن',
            quantity > 0 ? CurrencyFormatter.ils(_currentTotalChargeNow) : '-',
          ),
          const SizedBox(height: 12),
          Text(
            note,
            style: AppTheme.caption.copyWith(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewAndPrintWorkspace() {
    if (!_hasSelectedCardType) {
      return _buildCardTypeEmptyState();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 820;
        final preview = _buildPrintPreviewPanel(isCompact: isCompact);
        final settings = _buildPreviewSettingsPanel();
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              preview,
              const SizedBox(height: 16),
              settings,
              const SizedBox(height: 16),
              _buildPreviewActionPanel(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: preview),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  settings,
                  const SizedBox(height: 16),
                  _buildPreviewActionPanel(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrintPreviewPanel({required bool isCompact}) {
    return Column(
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
              child: const Icon(Icons.preview_rounded, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('معاينة البطاقة', style: AppTheme.h3),
                  const SizedBox(height: 4),
                  Text(
                    'مطابقة لتصميم الطباعة على صفحة A4 بواقع 30 بطاقة.',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: isCompact ? 14 : 18),
        SizedBox(width: double.infinity, child: _buildPreviewCard()),
      ],
    );
  }

  Widget _buildPreviewSettingsPanel() {
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
            maxLength: _printTitleMaxLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_printTitleMaxLength),
            ],
            decoration: InputDecoration(
              labelText: l.tr('screens_create_card_screen.046'),
              prefixIcon: const Icon(Icons.title_rounded),
              counterText: '',
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
          const SizedBox(height: 16),
          TextField(
            controller: _valueUnitC,
            onChanged: (_) => setState(() {}),
            maxLength: _valueUnitMaxLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_valueUnitMaxLength),
            ],
            decoration: const InputDecoration(
              labelText: 'نص بجانب القيمة',
              hintText: 'شيكل، دولار، عينة...',
              prefixIcon: Icon(Icons.sell_rounded),
              counterText: '',
              helperText: 'حتى 10 أحرف فقط',
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

  Widget _buildPreviewActionPanel() {
    final l = context.loc;
    final amount = double.tryParse(_amountC.text) ?? 0;
    final quantity = int.tryParse(_qtyC.text) ?? 0;
    final canPreviewPrint = _recent.isNotEmpty;
    final visibilityLabel = _effectiveVisibilityScope == 'restricted'
        ? l.tr('screens_create_card_screen.010')
        : l.tr('screens_create_card_screen.011');
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      color: AppTheme.secondary.withValues(alpha: 0.05),
      borderColor: AppTheme.secondary.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('جاهزية الطباعة', style: AppTheme.h3),
          const SizedBox(height: 12),
          _buildPreviewSummaryRow('النوع', _cardTypeLabel(l, _cardType)),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow('القيمة', _cardValueLabel(l, amount)),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'العدد المطلوب',
            quantity > 0 ? '$quantity' : '-',
          ),
          const SizedBox(height: 8),
          _buildPreviewSummaryRow('الخصوصية', visibilityLabel),
          if (_effectiveVisibilityScope == 'restricted') ...[
            const SizedBox(height: 8),
            _buildPreviewSummaryRow(
              'مستفيدون محددون',
              '${_selectedUsers.length} مستخدم - ${_selectedPhoneNumbers.length} رقم',
            ),
          ],
          if (_formatValidityWindow().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildPreviewSummaryRow('الصلاحية', _formatValidityWindow()),
          ],
          const SizedBox(height: 8),
          _buildPreviewSummaryRow(
            'الشعار والختم',
            '${_showLogo ? 'مفعل' : 'مخفي'} / ${_showStamp ? 'مفعل' : 'مخفي'}',
          ),
          const SizedBox(height: 18),
          ShwakelButton(
            label: 'إصدار الدفعة الآن',
            icon: Icons.verified_user_rounded,
            onPressed: _create,
            isLoading: _isLoading,
          ),
          if (canPreviewPrint) ...[
            const SizedBox(height: 10),
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

  Widget _buildPreviewSummaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.bodyBold.copyWith(fontSize: 13),
          ),
        ),
      ],
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
            'هذا الحساب غير موثق بعد، لذلك يتم إصدار بطاقات تجريبية خاصة بك فقط. مجموع البطاقات غير المستخدمة لا يتجاوز ${CurrencyFormatter.ils(_trialCardsLimit)} وتسجل قيمتها بالسالب على الرصيد.',
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

  Widget _buildPreviewCard() {
    final amount = double.tryParse(_amountC.text) ?? 0;
    final previewCard = VirtualCard(
      id: 'preview',
      barcode: '1234567890123456',
      value: amount,
      cardType: _cardType,
      visibilityScope: _effectiveVisibilityScope,
      createdAt: DateTime.now(),
      details: _currentCardDetails() ?? const {},
    );
    return _buildCardPreviewWidget(previewCard, serialNumber: 1);
  }

  Widget _buildCardPreviewWidget(
    VirtualCard previewCard, {
    required int serialNumber,
  }) {
    final l = context.loc;
    final printedBy = _resolvedIssuerName(l);
    final settings = _currentPdfDesignSettings();
    _pdfService.setDesignSettings(settings);

    return FutureBuilder<Uint8List>(
      future: () async {
        final pdf = await _pdfService.createSmallCardSheetPreviewPDF(
          previewCard,
          printedBy: printedBy,
          serialNumber: serialNumber,
        );
        final bytes = await pdf.save();
        final stream = Printing.raster(bytes, pages: const [0], dpi: 220);
        final page = await stream.first;
        return page.toPng();
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.surfaceVariant,
            child: const Text('تعذر توليد معاينة الطباعة.'),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            data,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        );
      },
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
            _selectedPhoneNumbers = [];
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
