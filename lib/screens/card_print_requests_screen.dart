import 'package:flutter/material.dart';

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

class CardPrintRequestsScreen extends StatefulWidget {
  const CardPrintRequestsScreen({super.key});

  @override
  State<CardPrintRequestsScreen> createState() =>
      _CardPrintRequestsScreenState();
}

class _CardPrintRequestsScreenState extends State<CardPrintRequestsScreen> {
  static const Map<String, int> _cardTypeDisplayOrder = {
    'standard': 0,
    'delivery': 1,
    'single_use': 2,
    'appointment': 3,
    'queue': 4,
  };

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic>? _user;
  Map<String, dynamic> _feeSettings = const {};
  bool _isLoading = true;
  bool _isAuthorized = false;
  bool _isSubmitting = false;

  Map<String, dynamic> get _subUserOperationalLimits =>
      Map<String, dynamic>.from(
        _user?['subUserOperationalLimits'] as Map? ?? const {},
      );

  bool get _isSubUser => _user?['isSubUser'] == true;

  double? _limitAsDouble(String key) =>
      (_subUserOperationalLimits[key] as num?)?.toDouble();

  bool get _isDriverAccount => _user?['role']?.toString() == 'driver';
  int get _minimumCardQuantity {
    final raw = (_user?['cardOperationMinQuantity'] as num?)?.toInt() ?? 1;
    return raw < 1 ? 1 : raw;
  }

  String _subUserPrintLimitMessage(BuildContext context) {
    final l = context.loc;
    final limit = CurrencyFormatter.ils(
      _limitAsDouble('printRequestMaxAmount') ?? 0,
    );
    final rawDebtLimit = _limitAsDouble('printingDebtLimit') ?? 0;
    if (rawDebtLimit > 0) {
      return l.tr(
        'screens_card_print_requests_screen.049',
        params: {
          'limit': limit,
          'debtLimit': CurrencyFormatter.ils(rawDebtLimit),
        },
      );
    }

    return l.tr(
      'screens_card_print_requests_screen.054',
      params: {'limit': limit},
    );
  }

  String _cardTypeLabel(BuildContext context, String cardType) {
    final l = context.loc;
    return switch (cardType) {
      'single_use' => l.tr('screens_card_print_requests_screen.027'),
      'delivery' => l.tr('shared.delivery_card_label'),
      'appointment' => l.tr('screens_card_print_requests_screen.055'),
      'queue' => l.tr('screens_card_print_requests_screen.056'),
      _ => l.tr('screens_card_print_requests_screen.028'),
    };
  }

  String _cardTypeUsageNote(String cardType) {
    return cardType == 'delivery'
        ? context.loc.tr('shared.delivery_card_payments_note')
        : '';
  }

  bool _isBalanceCardType(String cardType) =>
      cardType == 'standard' || cardType == 'delivery';

  List<String> _issuablePrintCardTypes() {
    final raw = _user?['cardIssuanceOptions'];
    if (raw is List) {
      final values = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) {
        return values;
      }
    }
    if (_isDriverAccount) {
      return const ['delivery'];
    }
    return const ['standard', 'delivery', 'single_use', 'appointment', 'queue'];
  }

  List<String> _sortedPrintableTypes() {
    final values = [..._issuablePrintCardTypes()];
    values.sort(
      (a, b) => (_cardTypeDisplayOrder[a] ?? 999).compareTo(
        _cardTypeDisplayOrder[b] ?? 999,
      ),
    );
    return values;
  }

  IconData _cardTypeIcon(String cardType) {
    return switch (cardType) {
      'single_use' => Icons.confirmation_number_rounded,
      'delivery' => Icons.local_shipping_rounded,
      'appointment' => Icons.event_available_rounded,
      'queue' => Icons.people_alt_rounded,
      _ => Icons.credit_card_rounded,
    };
  }

  String _cardTypeDescription(String cardType) {
    return switch (cardType) {
      'single_use' => 'تذكرة استخدام سريع تُطبع لمستفيدين محددين.',
      'delivery' => 'بطاقة توصيل برصيد قابل للاستخدام مع طباعة جاهزة.',
      'appointment' => 'تذكرة موعد بتاريخ ووقت وتعليمات واضحة.',
      'queue' => 'تذكرة دور أو خدمة مع تفاصيل تنظيمية.',
      _ => 'بطاقة رصيد عامة مناسبة للطباعة والاستخدام المعتاد.',
    };
  }

  double _cardRequestFeeAmount(double baseAmount, double feePercent) {
    if (baseAmount <= 0 || feePercent <= 0) {
      return 0;
    }
    final rounded = double.parse(
      (baseAmount * (feePercent / 100)).toStringAsFixed(2),
    );
    return rounded > 0 ? rounded : 0.01;
  }

  double _feeAmount(String key) =>
      (_feeSettings[key] as num?)?.toDouble() ?? 0.0;

  double _issueFeePerCard(String cardType, {required bool isPrivate}) {
    final normalizedType = cardType.trim().toLowerCase();
    var fee = switch (normalizedType) {
      'single_use' => _feeAmount('singleUseTicketIssueCost'),
      'appointment' => _feeAmount('appointmentTicketIssueCost'),
      'queue' => _feeAmount('queueTicketIssueCost'),
      'delivery' => _feeAmount('deliveryCardIssueCost'),
      _ => _feeAmount('standardCardIssueCost'),
    };
    final isTicket =
        normalizedType == 'single_use' ||
        normalizedType == 'appointment' ||
        normalizedType == 'queue';
    if (isPrivate && !isTicket) {
      fee += _feeAmount('privateCardIssueCost');
    }
    return fee > 0 ? fee : 0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = context.loc;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMyCardPrintRequests(),
        _refreshAndReadCurrentUser(),
        _apiService.getFeeSettings(),
      ]);
      if (!mounted) {
        return;
      }
      final user = results[1] as Map<String, dynamic>?;
      final permissions = AppPermissions.fromUser(user);
      setState(() {
        _requests = List<Map<String, dynamic>>.from(results[0] as List);
        _user = user;
        _feeSettings = Map<String, dynamic>.from(results[2] as Map);
        _isAuthorized = permissions.canRequestCardPrinting;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: l.tr('screens_card_print_requests_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<Map<String, dynamic>?> _refreshAndReadCurrentUser() async {
    var user = await _authService.currentUser();
    try {
      await _authService.refreshCurrentUser().timeout(
        const Duration(milliseconds: 1800),
      );
      user = await _authService.currentUser();
    } catch (_) {
      user ??= await _authService.currentUser();
    }
    return user;
  }

  Future<void> _showCreateRequestDialog() async {
    if (!_isAuthorized) {
      return;
    }
    final l = context.loc;
    final valueController = TextEditingController();
    final quantityController = TextEditingController(
      text: '$_minimumCardQuantity',
    );
    final notesController = TextEditingController();
    final detailsTitleController = TextEditingController();
    final detailsDescriptionController = TextEditingController();
    final detailsLocationController = TextEditingController();
    final startsAtController = TextEditingController();
    final endsAtController = TextEditingController();
    final validFromController = TextEditingController();
    final validUntilController = TextEditingController();
    final allowedPhoneController = TextEditingController();
    final selectedUsers = <Map<String, dynamic>>[];
    final selectedPhoneNumbers = <String>[];
    final availableTypes = _sortedPrintableTypes();
    var cardType =
        availableTypes.contains(_isDriverAccount ? 'delivery' : 'standard')
        ? (_isDriverAccount ? 'delivery' : 'standard')
        : (availableTypes.isNotEmpty ? availableTypes.first : 'standard');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isBalanceCard = _isBalanceCardType(cardType);
          final requiresTargetedUsers = !isBalanceCard;
          final selectedUserIds = selectedUsers
              .map((item) => item['id']?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toList();
          final selectedPhones = selectedPhoneNumbers
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
          final availableBalance =
              (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
          final feePercent =
              (_user?['customCardPrintRequestFeePercent'] as num?)
                  ?.toDouble() ??
              0;
          final value = double.tryParse(valueController.text.trim()) ?? 0;
          final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
          final faceAmount = isBalanceCard ? value * quantity : 0.0;
          final isPrivateRequest =
              requiresTargetedUsers ||
              selectedUserIds.isNotEmpty ||
              selectedPhones.isNotEmpty;
          final issueCostPerCard = _issueFeePerCard(
            cardType,
            isPrivate: isPrivateRequest,
          );
          final chargedIssueCostAmount = !isBalanceCard || isPrivateRequest
              ? issueCostPerCard * quantity
              : 0.0;
          final deferredIssueCostAmount = isBalanceCard && !isPrivateRequest
              ? issueCostPerCard * quantity
              : 0.0;
          final baseAmount = faceAmount + chargedIssueCostAmount;
          final feeAmount = _cardRequestFeeAmount(baseAmount, feePercent);
          final totalAmount = baseAmount + feeAmount;

          void addAllowedPhone() {
            final raw = allowedPhoneController.text.trim();
            final digits = raw.replaceAll(RegExp(r'\D'), '');
            if (digits.length < 6) {
              return;
            }
            final normalized = raw.startsWith('+') ? '+$digits' : digits;
            if (!selectedPhoneNumbers.contains(normalized)) {
              setDialogState(() => selectedPhoneNumbers.add(normalized));
            }
            allowedPhoneController.clear();
          }

          Future<void> submit() async {
            if (quantity <= 0 || (isBalanceCard && value <= 0)) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.002'),
                message: l.tr('screens_card_print_requests_screen.003'),
              );
              return;
            }

            if (quantity < _minimumCardQuantity) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.057'),
                message: l.tr(
                  'screens_card_print_requests_screen.058',
                  params: {'count': '$_minimumCardQuantity'},
                ),
              );
              return;
            }

            if (requiresTargetedUsers &&
                selectedUserIds.isEmpty &&
                selectedPhones.isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.059'),
                message: l.tr('screens_card_print_requests_screen.060'),
              );
              return;
            }

            if (cardType == 'appointment' &&
                (detailsTitleController.text.trim().isEmpty ||
                    startsAtController.text.trim().isEmpty)) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.061'),
                message: l.tr('screens_card_print_requests_screen.062'),
              );
              return;
            }

            if (cardType == 'queue' &&
                detailsTitleController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.063'),
                message: l.tr('screens_card_print_requests_screen.064'),
              );
              return;
            }

            if (totalAmount > availableBalance) {
              final contact = await ContactInfoService.getContactInfo();
              if (!dialogContext.mounted) {
                return;
              }
              await _showOverLimitDialog(
                dialogContext,
                availableBalance: availableBalance,
                totalAmount: totalAmount,
                feePercent: feePercent,
                supportWhatsapp: ContactInfoService.supportWhatsapp(contact),
              );
              return;
            }

            setDialogState(() => _isSubmitting = true);
            try {
              final details = <String, dynamic>{
                if (detailsTitleController.text.trim().isNotEmpty)
                  'title': detailsTitleController.text.trim(),
                if (detailsDescriptionController.text.trim().isNotEmpty)
                  'description': detailsDescriptionController.text.trim(),
                if (detailsLocationController.text.trim().isNotEmpty)
                  'location': detailsLocationController.text.trim(),
                if (startsAtController.text.trim().isNotEmpty)
                  'startsAt': startsAtController.text.trim(),
                if (endsAtController.text.trim().isNotEmpty)
                  'endsAt': endsAtController.text.trim(),
              };
              final response = await _apiService.requestCardPrint(
                value: isBalanceCard ? value : 0,
                quantity: quantity,
                cardType: cardType,
                notes: notesController.text,
                allowedUserIds: selectedUserIds,
                allowedUserPhones: selectedPhones,
                validFrom: validFromController.text,
                validUntil: validUntilController.text,
                cardDetails: details,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              await AppAlertService.showSuccess(
                context,
                title: l.tr('screens_card_print_requests_screen.004'),
                message:
                    response['message']?.toString() ??
                    l.tr('screens_card_print_requests_screen.005'),
              );
              await _load();
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => _isSubmitting = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.006'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(l.tr('screens_card_print_requests_screen.007')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSubUser) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          _subUserPrintLimitMessage(dialogContext),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l.tr('screens_card_print_requests_screen.008'),
                        style: AppTheme.bodyBold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: availableTypes.map((type) {
                        final selected = cardType == type;
                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            setDialogState(() {
                              cardType = type;
                              if (_isBalanceCardType(type)) {
                                selectedUsers.clear();
                                detailsTitleController.clear();
                                detailsDescriptionController.clear();
                                detailsLocationController.clear();
                                startsAtController.clear();
                                endsAtController.clear();
                                validFromController.clear();
                                validUntilController.clear();
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 198,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primary.withValues(alpha: 0.08)
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.border,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _cardTypeIcon(type),
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _cardTypeLabel(dialogContext, type),
                                        style: AppTheme.bodyBold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _cardTypeDescription(type),
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    if (cardType == 'delivery')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          l.tr('shared.delivery_card_print_note'),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (cardType == 'delivery') const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: isBalanceCard,
                      decoration: InputDecoration(
                        labelText: !isBalanceCard
                            ? l.tr('screens_card_print_requests_screen.011')
                            : l.tr('screens_card_print_requests_screen.012'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.secondary.withValues(alpha: 0.05),
                      borderColor: AppTheme.secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ملخص الخصم والرسوم', style: AppTheme.bodyBold),
                          const SizedBox(height: 10),
                          _metaItem(
                            'قيمة البطاقات',
                            CurrencyFormatter.ils(faceAmount),
                          ),
                          const SizedBox(height: 8),
                          _metaItem(
                            'رسوم الإصدار المخصومة الآن',
                            CurrencyFormatter.ils(chargedIssueCostAmount),
                          ),
                          if (deferredIssueCostAmount > 0) ...[
                            const SizedBox(height: 8),
                            _metaItem(
                              'رسوم الإصدار المؤجلة',
                              CurrencyFormatter.ils(deferredIssueCostAmount),
                            ),
                          ],
                          if (feeAmount > 0) ...[
                            const SizedBox(height: 8),
                            _metaItem(
                              'رسوم طلب الطباعة',
                              CurrencyFormatter.ils(feeAmount),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _metaItem(
                            'إجمالي الخصم الآن',
                            CurrencyFormatter.ils(totalAmount),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            deferredIssueCostAmount > 0
                                ? 'هذا النوع يحتفظ برسوم إصدار مؤجلة تُحسب عند استخدام البطاقة، بينما يظهر في هذا الطلب فقط ما سيُخصم الآن.'
                                : 'هذا الملخص يوضح كامل المبلغ الذي سيُخصم الآن عند إرسال طلب الطباعة.',
                            style: AppTheme.caption.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (requiresTargetedUsers) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFFFCDD5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'بطاقة خاصة',
                              style: AppTheme.bodyBold.copyWith(
                                color: const Color(0xFFBE123C),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'هذا النوع يطبع لمستفيدين محددين فقط، وستظهر تكلفة الإصدار ضمن طلب الطباعة.',
                              style: AppTheme.caption.copyWith(
                                color: const Color(0xFF9F1239),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: allowedPhoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'رقم هاتف المستفيد',
                                      prefixIcon: Icon(Icons.phone_rounded),
                                    ),
                                    onSubmitted: (_) => addAllowedPhone(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  onPressed: addAllowedPhone,
                                  icon: const Icon(Icons.add_rounded),
                                  tooltip: 'إضافة الرقم',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (selectedPhoneNumbers.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: selectedPhoneNumbers.map((phone) {
                                  return InputChip(
                                    avatar: const Icon(Icons.phone_rounded),
                                    label: Text(phone),
                                    onDeleted: () => setDialogState(
                                      () => selectedPhoneNumbers.remove(phone),
                                    ),
                                  );
                                }).toList(),
                              ),
                            if (selectedPhoneNumbers.isNotEmpty)
                              const SizedBox(height: 10),
                            if (selectedUsers.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: selectedUsers.map((user) {
                                  final id = user['id']?.toString() ?? '';
                                  final label = UserDisplayName.fromMap(
                                    user,
                                    fallback: id,
                                  );
                                  return InputChip(
                                    label: Text(label),
                                    onDeleted: () {
                                      setDialogState(
                                        () => selectedUsers.removeWhere(
                                          (item) =>
                                              item['id']?.toString() == id,
                                        ),
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final results = await _pickPrintTargetUsers(
                                    dialogContext,
                                    selectedUsers,
                                  );
                                  if (results != null) {
                                    setDialogState(() {
                                      selectedUsers
                                        ..clear()
                                        ..addAll(results);
                                    });
                                  }
                                },
                                icon: const Icon(Icons.group_add_rounded),
                                label: Text(
                                  selectedUsers.isEmpty
                                      ? 'اختيار المستفيدين'
                                      : 'تعديل المستفيدين',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: detailsTitleController,
                        decoration: InputDecoration(
                          labelText: cardType == 'appointment'
                              ? 'عنوان الموعد'
                              : cardType == 'queue'
                              ? 'اسم خدمة الطابور'
                              : 'عنوان التذكرة',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (cardType == 'appointment') ...[
                        TextField(
                          controller: startsAtController,
                          decoration: const InputDecoration(
                            labelText: 'وقت بداية الموعد',
                            hintText: '2026-05-01 09:00',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: endsAtController,
                          decoration: const InputDecoration(
                            labelText: 'وقت نهاية الموعد',
                            hintText: '2026-05-01 09:30',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (cardType == 'appointment' || cardType == 'queue') ...[
                        TextField(
                          controller: detailsLocationController,
                          decoration: const InputDecoration(
                            labelText: 'الموقع أو الفرع',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: validFromController,
                        decoration: const InputDecoration(
                          labelText: 'بداية الصلاحية',
                          hintText: 'اختياري - 2026-05-01 08:00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: validUntilController,
                        decoration: const InputDecoration(
                          labelText: 'نهاية الصلاحية',
                          hintText: 'اختياري - 2026-05-01 18:00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: detailsDescriptionController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'تفاصيل إضافية',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_card_print_requests_screen.013',
                        ),
                        helperText:
                            'الحد الأدنى لهذا الحساب هو $_minimumCardQuantity بطاقة.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_card_print_requests_screen.014',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_card_print_requests_screen.015')),
              ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : submit,
                child: Text(
                  _isSubmitting
                      ? l.tr('screens_card_print_requests_screen.016')
                      : l.tr('screens_card_print_requests_screen.017'),
                ),
              ),
            ],
          );
        },
      ),
    );

    valueController.dispose();
    quantityController.dispose();
    notesController.dispose();
    detailsTitleController.dispose();
    detailsDescriptionController.dispose();
    detailsLocationController.dispose();
    startsAtController.dispose();
    endsAtController.dispose();
    validFromController.dispose();
    validUntilController.dispose();
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  Future<List<Map<String, dynamic>>?> _pickPrintTargetUsers(
    BuildContext dialogContext,
    List<Map<String, dynamic>> current,
  ) async {
    final searchController = TextEditingController();
    final selected = List<Map<String, dynamic>>.from(current);
    var results = <Map<String, dynamic>>[];
    var isSearching = false;

    try {
      return await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: dialogContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> searchUsers(String query) async {
              setModalState(() => isSearching = true);
              try {
                results = query.trim().isEmpty
                    ? <Map<String, dynamic>>[]
                    : await _apiService.searchUsers(query.trim());
              } catch (_) {
                results = <Map<String, dynamic>>[];
              }
              if (context.mounted) {
                setModalState(() => isSearching = false);
              }
            }

            bool isSelected(Map<String, dynamic> user) {
              final id = user['id']?.toString();
              return selected.any((item) => item['id']?.toString() == id);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('اختيار المستفيدين', style: AppTheme.h3),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'ابحث بالاسم أو رقم الهاتف',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: searchUsers,
                    ),
                    const SizedBox(height: 12),
                    if (selected.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: selected.map((user) {
                          final id = user['id']?.toString() ?? '';
                          return InputChip(
                            label: Text(
                              UserDisplayName.fromMap(user, fallback: id),
                            ),
                            onDeleted: () => setModalState(
                              () => selected.removeWhere(
                                (item) => item['id']?.toString() == id,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: results.length,
                              itemBuilder: (context, index) {
                                final user = results[index];
                                final checked = isSelected(user);
                                final id = user['id']?.toString() ?? '';
                                final title = UserDisplayName.fromMap(
                                  user,
                                  fallback: id,
                                );
                                final subtitle =
                                    user['whatsapp']?.toString() ??
                                    user['username']?.toString() ??
                                    '';
                                return CheckboxListTile(
                                  value: checked,
                                  title: Text(title),
                                  subtitle: subtitle.isNotEmpty
                                      ? Text(subtitle)
                                      : null,
                                  onChanged: (value) {
                                    setModalState(() {
                                      if (value == true && !checked) {
                                        selected.add(user);
                                      } else if (value != true) {
                                        selected.removeWhere(
                                          (item) =>
                                              item['id']?.toString() == id,
                                        );
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: const Text('اعتماد'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _showOverLimitDialog(
    BuildContext dialogContext, {
    required double availableBalance,
    required double totalAmount,
    required double feePercent,
    required String supportWhatsapp,
  }) async {
    final l = context.loc;
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(l.tr('screens_card_print_requests_screen.041')),
        content: Text(
          l.tr(
            'screens_card_print_requests_screen.042',
            params: {
              'available': CurrencyFormatter.ils(availableBalance),
              'total': CurrencyFormatter.ils(totalAmount),
              'fee': feePercent.toStringAsFixed(2),
              'phone': supportWhatsapp,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.tr('screens_card_print_requests_screen.043')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_card_print_requests_screen.018')),
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
                  l.tr('screens_card_print_requests_screen.037'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final availableBalance =
        (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
    final printFee = (_user?['customCardPrintRequestFeePercent'] as num?)
        ?.toDouble();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_card_print_requests_screen.018')),
        actions: [
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            useSafeArea: false,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              8,
              AppTheme.spacingLg,
              AppTheme.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPrintInfoCard(
                  availableBalance: availableBalance,
                  printFee: printFee,
                ),
                if (_isSubUser) ...[
                  const SizedBox(height: 12),
                  ShwakelCard(
                    padding: const EdgeInsets.all(16),
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    child: Text(
                      _subUserPrintLimitMessage(context),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.tr('screens_card_print_requests_screen.024'),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  )
                else
                  ..._requests.map(_buildRequestCard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrintInfoCard({
    required double availableBalance,
    required double? printFee,
  }) {
    final l = context.loc;
    final feeLabel = printFee == null
        ? l.tr('screens_card_print_requests_screen.022')
        : '${CurrencyFormatter.formatAmount(printFee)}%';
    final debtLimit = (_user?['printingDebtLimit'] as num?)?.toDouble() ?? 0;
    final currentDebt = (_user?['outstandingDebt'] as num?)?.toDouble() ?? 0;
    final showPrintFee = (printFee ?? 0) > 0;
    final showDebtLimit = debtLimit > 0;
    final showCurrentDebt = currentDebt > 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.premium,
      gradient: const LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF0F766E)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final actionButton = SizedBox(
            width: compact ? double.infinity : 190,
            child: ShwakelButton(
              label: l.tr('screens_card_print_requests_screen.023'),
              icon: Icons.print_rounded,
              onPressed: _showCreateRequestDialog,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  if (compact)
                    _buildPrintInfoHeader()
                  else
                    Expanded(child: _buildPrintInfoHeader()),
                  SizedBox(width: compact ? 0 : 18, height: compact ? 18 : 0),
                  actionButton,
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPrintMetricTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: l.tr('screens_card_print_requests_screen.020'),
                    value: CurrencyFormatter.ils(availableBalance),
                  ),
                  if (showPrintFee)
                    _buildPrintMetricTile(
                      icon: Icons.percent_rounded,
                      label: l.tr('screens_card_print_requests_screen.021'),
                      value: feeLabel,
                    ),
                  if (showDebtLimit)
                    _buildPrintMetricTile(
                      icon: Icons.credit_score_rounded,
                      label: l.tr('screens_card_print_requests_screen.051'),
                      value: CurrencyFormatter.ils(debtLimit),
                    ),
                  if (showCurrentDebt)
                    _buildPrintMetricTile(
                      icon: Icons.trending_down_rounded,
                      label: l.tr('screens_card_print_requests_screen.052'),
                      value: CurrencyFormatter.ils(currentDebt),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrintInfoHeader() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.print_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.tr('screens_card_print_requests_screen.050'),
                style: AppTheme.h3.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l.tr('screens_card_print_requests_screen.019'),
          style: AppTheme.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.76),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPrintMetricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: AppTheme.isPhone(context) ? double.infinity : 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_admin_dashboard_screen.057'),
      message: l.tr('screens_card_print_requests_screen.053'),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status']?.toString() ?? 'pending_review';
    final cardTypeLabel = _cardTypeLabel(
      context,
      request['cardType']?.toString() ?? 'standard',
    );
    final quantity = (request['quantity'] as num?)?.toInt() ?? 0;
    final totalAmount = CurrencyFormatter.ils(
      (request['totalAmount'] as num?)?.toDouble() ?? 0,
    );
    final createdAt = _formatDateTime(
      request['createdAt']?.toString(),
      request['created_at']?.toString() ?? '-',
    );
    final title = request['statusLabel']?.toString().trim().isNotEmpty == true
        ? request['statusLabel']!.toString()
        : cardTypeLabel;
    final chargedIssueCostAmount =
        (request['chargedIssueCostAmount'] as num?)?.toDouble() ?? 0;
    final deferredIssueCostAmount =
        (request['deferredIssueCostAmount'] as num?)?.toDouble() ?? 0;
    final hasFees = chargedIssueCostAmount > 0 || deferredIssueCostAmount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        onTap: () => _showRequestDetails(request),
        padding: const EdgeInsets.all(14),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.print_rounded,
                color: _statusColor(status),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyBold.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cardTypeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _requestInfoChip(Icons.layers_rounded, '$quantity بطاقة'),
                      _requestInfoChip(
                        Icons.account_balance_wallet_rounded,
                        totalAmount,
                      ),
                      if (hasFees)
                        _requestInfoChip(
                          Icons.receipt_long_rounded,
                          'يشمل تفاصيل الرسوم',
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    createdAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_left_rounded,
              color: AppTheme.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRequestDetails(Map<String, dynamic> request) async {
    final l = context.loc;
    final chargedIssueCostAmount =
        (request['chargedIssueCostAmount'] as num?)?.toDouble() ?? 0;
    final deferredIssueCostAmount =
        (request['deferredIssueCostAmount'] as num?)?.toDouble() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
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
                    Expanded(
                      child: Text('تفاصيل طلب الطباعة', style: AppTheme.h3),
                    ),
                    _statusChip(
                      request['status']?.toString() ?? 'pending_review',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.026'),
                      _cardTypeLabel(
                        context,
                        request['cardType']?.toString() ?? 'standard',
                      ),
                    ),
                    if ((request['cardType']?.toString() ?? '') == 'delivery')
                      _metaItem(
                        l.tr('shared.usage_label'),
                        _cardTypeUsageNote(
                          request['cardType']?.toString() ?? 'standard',
                        ),
                      ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.029'),
                      l.tr(
                        'screens_card_print_requests_screen.030',
                        params: {'count': '${request['quantity'] ?? 0}'},
                      ),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.031'),
                      CurrencyFormatter.ils(
                        (request['cardValue'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    if (chargedIssueCostAmount > 0)
                      _metaItem(
                        'رسوم الإصدار المخصومة الآن',
                        CurrencyFormatter.ils(chargedIssueCostAmount),
                      ),
                    if (deferredIssueCostAmount > 0)
                      _metaItem(
                        'رسوم الإصدار المؤجلة',
                        CurrencyFormatter.ils(deferredIssueCostAmount),
                      ),
                    if (((request['feeAmount'] as num?)?.toDouble() ?? 0) > 0)
                      _metaItem(
                        'رسوم طلب الطباعة',
                        CurrencyFormatter.ils(
                          (request['feeAmount'] as num?)?.toDouble() ?? 0,
                        ),
                      ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.032'),
                      CurrencyFormatter.ils(
                        (request['totalAmount'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.044'),
                      request['sourceType'] == 'local'
                          ? l.tr('screens_card_print_requests_screen.045')
                          : l.tr('screens_card_print_requests_screen.046'),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.047'),
                      _formatDateTime(
                        request['lastPrintedAt']?.toString(),
                        l.tr('screens_card_print_requests_screen.048'),
                      ),
                    ),
                  ],
                ),
                if ((request['customerNotes']?.toString().trim().isNotEmpty ??
                    false))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Text(
                        l.tr(
                          'screens_card_print_requests_screen.033',
                          params: {'notes': '${request['customerNotes']}'},
                        ),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  ),
                if (chargedIssueCostAmount > 0 || deferredIssueCostAmount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Text(
                        deferredIssueCostAmount > 0
                            ? 'تم عرض الرسوم المخصومة الآن والرسوم المؤجلة بشكل منفصل حتى تعرف ما يدخل ضمن خصم الطلب وما يُحتسب لاحقًا عند الاستخدام.'
                            : 'جميع رسوم الإصدار الخاصة بهذا الطلب تدخل ضمن الخصم الحالي الظاهر أمامك.',
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  ),
                if ((request['adminNotes']?.toString().trim().isNotEmpty ??
                    false))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(18),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Text(
                        l.tr(
                          'screens_card_print_requests_screen.034',
                          params: {'notes': '${request['adminNotes']}'},
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
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

  Widget _requestInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'approved' => AppTheme.primary,
      'printing' => AppTheme.warning,
      'ready' => AppTheme.success,
      'completed' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };
  }

  Widget _statusChip(String status) {
    final l = context.loc;
    final color = _statusColor(status);
    final label = switch (status) {
      'pending_review' => l.tr('screens_card_print_requests_screen.035'),
      'approved' => l.tr('screens_card_print_requests_screen.036'),
      'printing' => l.tr('screens_card_print_requests_screen.037'),
      'ready' => l.tr('screens_card_print_requests_screen.038'),
      'completed' => l.tr('screens_card_print_requests_screen.039'),
      'rejected' => l.tr('screens_card_print_requests_screen.040'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _formatDateTime(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
