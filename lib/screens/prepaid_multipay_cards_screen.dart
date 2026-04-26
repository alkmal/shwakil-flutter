import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class PrepaidMultipayCardsScreen extends StatefulWidget {
  const PrepaidMultipayCardsScreen({super.key});

  @override
  State<PrepaidMultipayCardsScreen> createState() =>
      _PrepaidMultipayCardsScreenState();
}

class _PrepaidMultipayCardsScreenState
    extends State<PrepaidMultipayCardsScreen> {
  final ApiService _api = ApiService();
  final _labelC = TextEditingController();
  final _amountC = TextEditingController();
  final _pinC = TextEditingController();
  final _payCardNumberC = TextEditingController();
  final _payAmountC = TextEditingController();
  final _payPinC = TextEditingController();
  final _payNoteC = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isAcceptingPayment = false;
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _payments = const [];
  Map<String, dynamic> _summary = const {};
  final Set<String> _revealedCardIds = <String>{};
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelC.dispose();
    _amountC.dispose();
    _pinC.dispose();
    _payCardNumberC.dispose();
    _payAmountC.dispose();
    _payPinC.dispose();
    _payNoteC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final payload = await _api.getPrepaidMultipayCards();
      if (!mounted) {
        return;
      }
      setState(() {
        _cards = List<Map<String, dynamic>>.from(
          (payload['cards'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _payments = List<Map<String, dynamic>>.from(
          (payload['payments'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _revealedCardIds.removeWhere(
          (id) => !_cards.any((card) => card['id']?.toString() == id),
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
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
    final pin = _pinC.text.trim();
    if (label.isEmpty || amount <= 0 || !RegExp(r'^\d{3}$').hasMatch(pin)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات البطاقة غير مكتملة',
        message: 'أدخل اسم البطاقة، مبلغًا صحيحًا، ورمز PIN من 3 أرقام.',
      );
      return;
    }

    final security = await TransferSecurityService.confirmTransfer(context);
    if (!mounted || !security.isVerified) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _api.createPrepaidMultipayCard(
        label: label,
        amount: amount,
        pin: pin,
        expiresAt: _expiresAt.toUtc().toIso8601String(),
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _labelC.clear();
      _amountC.clear();
      _pinC.clear();
      _expiresAt = DateTime.now().add(const Duration(days: 30));
      await _load();
      if (!mounted) return;
      await AppAlertService.showSuccess(
        context,
        title: 'تم إنشاء البطاقة',
        message: 'تم حجز المبلغ في بطاقة دفع مسبق متعددة الاستخدام.',
      );
    } catch (error) {
      if (!mounted) return;
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

    try {
      await _api.updatePrepaidMultipayCardStatus(
        cardId: card['id']?.toString() ?? '',
        action: action,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر تحديث البطاقة',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _acceptPayment() async {
    final cardNumber = _payCardNumberC.text.trim();
    final amount = double.tryParse(_payAmountC.text.trim()) ?? 0;
    final pin = _payPinC.text.trim();
    if (cardNumber.isEmpty ||
        amount <= 0 ||
        !RegExp(r'^\d{3}$').hasMatch(pin)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات الدفع غير مكتملة',
        message: 'أدخل رقم البطاقة، مبلغًا صحيحًا، ورمز PIN من 3 أرقام.',
      );
      return;
    }

    setState(() => _isAcceptingPayment = true);
    try {
      final payload = await _api.acceptPrepaidMultipayCardPayment(
        cardNumber: cardNumber,
        amount: amount,
        pin: pin,
        note: _payNoteC.text,
        idempotencyKey: _newPaymentKey(),
      );
      _payCardNumberC.clear();
      _payAmountC.clear();
      _payPinC.clear();
      _payNoteC.clear();
      if (!mounted) return;
      final payment = Map<String, dynamic>.from(
        payload['payment'] as Map? ?? const {},
      );
      final remaining = (payment['remainingCardBalance'] as num?)?.toDouble();
      await AppAlertService.showSuccess(
        context,
        title: 'تم قبول الدفع',
        message: remaining == null
            ? 'تمت العملية بنجاح.'
            : 'تم استلام ${CurrencyFormatter.ils(amount)}. المتبقي في البطاقة ${CurrencyFormatter.ils(remaining)}.',
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر قبول الدفع',
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

  Future<void> _showCardQr(Map<String, dynamic> card) async {
    final canReveal = await _ensureCardRevealed(card);
    if (!canReveal || !mounted) {
      return;
    }
    final rawNumber = card['rawCardNumber']?.toString() ?? '';
    if (rawNumber.isEmpty) {
      return;
    }
    final payload = jsonEncode({
      'type': 'prepaid_multipay_card',
      'cardNumber': rawNumber,
    });

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(card['label']?.toString() ?? 'بطاقة دفع مسبق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            SelectableText(
              card['cardNumber']?.toString() ?? rawNumber,
              textAlign: TextAlign.center,
              style: AppTheme.bodyBold,
            ),
          ],
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

  Future<void> _changePin(Map<String, dynamic> card) async {
    final currentPinC = TextEditingController();
    final newPinC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير PIN البطاقة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPinC,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'PIN الحالي',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPinC,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'PIN الجديد',
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
            child: const Text('تغيير'),
          ),
        ],
      ),
    );

    final currentPin = currentPinC.text.trim();
    final newPin = newPinC.text.trim();
    currentPinC.dispose();
    newPinC.dispose();
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (!RegExp(r'^\d{3}$').hasMatch(currentPin) ||
        !RegExp(r'^\d{3}$').hasMatch(newPin)) {
      await AppAlertService.showError(
        context,
        title: 'PIN غير صالح',
        message: 'أدخل الرمز الحالي والجديد من 3 أرقام.',
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
        currentPin: currentPin,
        newPin: newPin,
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      await _load();
      if (!mounted) return;
      await AppAlertService.showSuccess(
        context,
        title: 'تم تغيير PIN',
        message: 'تم تحديث رمز البطاقة بنجاح.',
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر تغيير PIN',
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
      allowOtpFallback: false,
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

  Future<void> _showCardDetails(Map<String, dynamic> card) async {
    final payments = List<Map<String, dynamic>>.from(
      (card['payments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    String filter = 'all';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final filtered = payments.where((payment) {
            if (filter == 'today') {
              final createdAt = DateTime.tryParse(
                payment['createdAt']?.toString() ?? '',
              );
              if (createdAt == null) return false;
              final now = DateTime.now();
              return createdAt.year == now.year &&
                  createdAt.month == now.month &&
                  createdAt.day == now.day;
            }
            return true;
          }).toList();

          return AlertDialog(
            title: Text(card['label']?.toString() ?? 'تفاصيل البطاقة'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('كل العمليات'),
                        selected: filter == 'all',
                        onSelected: (_) => setDialogState(() => filter = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('اليوم'),
                        selected: filter == 'today',
                        onSelected: (_) =>
                            setDialogState(() => filter = 'today'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Text(
                      'لا توجد عمليات ضمن هذا النطاق.',
                      style: AppTheme.bodyAction,
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 18),
                        itemBuilder: (context, index) {
                          final payment = filtered[index];
                          final amount =
                              (payment['amount'] as num?)?.toDouble() ?? 0;
                          final note = payment['note']?.toString() ?? '';
                          return Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note.isEmpty ? 'دفع بطاقة مسبقة' : note,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.bodyBold,
                                    ),
                                    Text(
                                      _formatDate(
                                        DateTime.tryParse(
                                          payment['createdAt']?.toString() ??
                                              '',
                                        ),
                                      ),
                                      style: AppTheme.caption,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                CurrencyFormatter.ils(amount),
                                style: AppTheme.bodyBold,
                              ),
                            ],
                          );
                        },
                      ),
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
          );
        },
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now().add(const Duration(days: 2)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialDate: _expiresAt,
    );
    if (date == null || !mounted) {
      return;
    }
    setState(
      () => _expiresAt = DateTime(date.year, date.month, date.day, 23, 59),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('بطاقات الدفع المسبق'),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummary(),
                        const SizedBox(height: 16),
                        _buildPaymentForm(),
                        const SizedBox(height: 16),
                        _buildCreateForm(),
                        const SizedBox(height: 20),
                        _buildRecentPayments(),
                        const SizedBox(height: 20),
                        Text('بطاقاتك', style: AppTheme.h2),
                        const SizedBox(height: 12),
                        if (_cards.isEmpty)
                          _buildEmpty()
                        else
                          ..._cards.map(
                            (card) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildCard(card),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
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
            'الرصيد المحجوز',
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

  Widget _buildCreateForm() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إضافة بطاقة جديدة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'بطاقة دفع مسبق داخلية مخصصة لشواكل وليست بطاقة دولية.',
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
              labelText: 'المبلغ المحجوز',
              prefixIcon: Icon(Icons.payments_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pinC,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'PIN من 3 أرقام',
              prefixIcon: Icon(Icons.pin_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickExpiry,
            icon: const Icon(Icons.event_rounded),
            label: Text('تنتهي في ${_formatDate(_expiresAt)}'),
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
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('قبول دفع من بطاقة مسبقة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'يتم الخصم من رصيد البطاقة المحجوز وإضافة المبلغ لرصيد التاجر مباشرة.',
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
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _scanPaymentCard,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('مسح QR البطاقة'),
            ),
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
          TextField(
            controller: _payPinC,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'PIN البطاقة',
              prefixIcon: Icon(Icons.pin_rounded),
              counterText: '',
            ),
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
            label: 'قبول الدفع',
            icon: Icons.point_of_sale_rounded,
            isLoading: _isAcceptingPayment,
            onPressed: _acceptPayment,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentPayments() {
    if (_payments.isEmpty) {
      return const SizedBox.shrink();
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('آخر مدفوعات البطاقات', style: AppTheme.h3),
          const SizedBox(height: 12),
          ..._payments
              .take(6)
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
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
                if (note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildCard(Map<String, dynamic> card) {
    final status = card['status']?.toString() ?? 'active';
    final cardId = card['id']?.toString() ?? '';
    final isRevealed = _revealedCardIds.contains(cardId);
    final displayNumber = isRevealed
        ? card['cardNumber']?.toString() ?? ''
        : '•••• •••• •••• ••••';
    final color = switch (status) {
      'active' => AppTheme.success,
      'frozen' => AppTheme.warning,
      'spent' => AppTheme.primary,
      'cancelled' => AppTheme.error,
      'expired' => AppTheme.textTertiary,
      _ => AppTheme.primary,
    };
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF111827), Color(0xFF0F766E)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card['label']?.toString() ?? '',
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  displayNumber,
                  style: AppTheme.h3.copyWith(
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'شواكل prepaid',
                        style: AppTheme.caption.copyWith(color: Colors.white70),
                      ),
                    ),
                    Text(
                      _formatDate(
                        DateTime.tryParse(card['expiresAt']?.toString() ?? ''),
                      ),
                      style: AppTheme.caption.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
              _cardChip(Icons.info_rounded, _statusLabel(status), color: color),
            ],
          ),
          _buildCardWarnings(card),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _toggleCardNumber(card),
                icon: Icon(
                  isRevealed
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                label: Text(isRevealed ? 'إخفاء الرقم' : 'إظهار الرقم'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showCardDetails(card),
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('التفاصيل'),
              ),
              if (status == 'active' || status == 'frozen')
                OutlinedButton.icon(
                  onPressed: () => _showCardQr(card),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('QR'),
                ),
            ],
          ),
          if (status == 'active' || status == 'frozen') ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'active')
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'freeze'),
                    icon: const Icon(Icons.pause_circle_rounded),
                    label: const Text('تجميد'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _updateStatus(card, 'activate'),
                    icon: const Icon(Icons.play_circle_rounded),
                    label: const Text('تفعيل'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _updateStatus(card, 'cancel'),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('إلغاء وإرجاع الرصيد'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _changePin(card),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('تغيير PIN'),
                ),
              ],
            ),
          ],
          _buildCardPayments(card),
        ],
      ),
    );
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
        'expiring_soon' => 'قرب انتهاء البطاقة',
        'daily_amount_near_limit' => 'قرب حد المبلغ اليومي',
        'daily_count_near_limit' => 'قرب حد عدد العمليات',
        _ => warning,
      };
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
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

  Widget _buildCardPayments(Map<String, dynamic> card) {
    final payments = List<Map<String, dynamic>>.from(
      (card['payments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    if (payments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('حركات البطاقة', style: AppTheme.bodyBold),
        const SizedBox(height: 8),
        ...payments
            .take(3)
            .map(
              (payment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        payment['note']?.toString().isNotEmpty == true
                            ? payment['note'].toString()
                            : 'دفع بطاقة مسبقة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.ils(
                        (payment['amount'] as num?)?.toDouble() ?? 0,
                      ),
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
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

  String _statusLabel(String status) {
    return switch (status) {
      'active' => 'نشطة',
      'frozen' => 'مجمدة',
      'spent' => 'مستهلكة',
      'cancelled' => 'ملغاة',
      'expired' => 'منتهية',
      _ => status,
    };
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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
