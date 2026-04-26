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
  final _codeC = TextEditingController();
  final _reloadAmountC = TextEditingController();
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
  List<Map<String, dynamic>> _cards = const [];
  List<Map<String, dynamic>> _payments = const [];
  Map<String, dynamic> _summary = const {};
  final Set<String> _revealedCardIds = <String>{};
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 30));
  String? _selectedCardId;
  String _activityFilter = 'all';

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
    _reloadAmountC.dispose();
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
      });
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
        expiresAt: _expiresAt.toUtc().toIso8601String(),
        otpCode: security.otpCode,
        localAuthMethod: security.method,
      );
      _labelC.clear();
      _amountC.clear();
      _codeC.clear();
      _expiresAt = DateTime.now().add(const Duration(days: 30));
      _selectedCardId = (payload['card'] as Map?)?['id']?.toString();
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم إنشاء البطاقة',
        message: 'تم إنشاء البطاقة وحجز الرصيد فيها، وهي الآن بانتظار موافقة الإدارة قبل التفعيل.',
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

  Future<void> _reloadSelectedCard() async {
    final card = _selectedCard;
    if (card == null) {
      return;
    }

    final amount = double.tryParse(_reloadAmountC.text.trim()) ?? 0;
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
      _reloadAmountC.clear();
      _selectedCardId = (payload['card'] as Map?)?['id']?.toString() ??
          card['id']?.toString();
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم شحن البطاقة',
        message: 'تمت إضافة ${CurrencyFormatter.ils(amount)} إلى البطاقة المحددة.',
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
        message: 'أدخل رقم البطاقة والمبلغ والشهر والسنة وكود الحماية من 3 أرقام.',
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
        title: 'تم قبول الدفع',
        message: remaining == null
            ? 'تمت العملية بنجاح.'
            : 'تم استلام ${CurrencyFormatter.ils(amount)}. المتبقي في البطاقة ${CurrencyFormatter.ils(remaining)}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
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
      'expiryMonth': (card['expiryMonth'] as num?)?.toInt(),
      'expiryYear': (card['expiryYear'] as num?)?.toInt(),
      'label': card['label']?.toString(),
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

  Future<void> _changeSecurityCode(Map<String, dynamic> card) async {
    final currentCodeC = TextEditingController();
    final newCodeC = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير كود الحماية'),
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
        message: 'تم تغيير كود الحماية الخاص بالبطاقة.',
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

  void _openPaymentsTab() {
    final controller = DefaultTabController.of(context);
    controller.animateTo(2);
  }

  void _openManagementTab() {
    final controller = DefaultTabController.of(context);
    controller.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummary(),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'البطاقات'),
                          Tab(text: 'الإدارة والشحن'),
                          Tab(text: 'الدفع والحركات'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildCardsTab(),
                          _buildManagementTab(),
                          _buildPaymentsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
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
          Text('قائمة البطاقات', style: AppTheme.h2),
          const SizedBox(height: 8),
          Text(
            'اختر بطاقة لعرض شكلها الكامل وتفاصيلها وحركاتها تحت القائمة.',
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
          const SizedBox(height: 20),
          if (selected != null) ...[
            Text('البطاقة المحددة', style: AppTheme.h2),
            const SizedBox(height: 12),
            _buildSelectedCardDetails(selected),
          ],
        ],
      ),
    );
  }

  Widget _buildManagementTab() {
    final selected = _selectedCard;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (selected != null) ...[
            _buildSelectedCardHeader(selected),
            const SizedBox(height: 16),
          ],
          _buildCreateForm(),
          const SizedBox(height: 16),
          _buildReloadForm(selected),
        ],
      ),
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
            child: Icon(
              Icons.credit_card_rounded,
              color: _statusColor(status),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card['label']?.toString() ?? '',
                  style: AppTheme.bodyBold,
                ),
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
          Icon(
            isSelected ? Icons.keyboard_arrow_up_rounded : Icons.chevron_left,
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedCardDetails(Map<String, dynamic> card) {
    final status = card['status']?.toString() ?? 'active';
    final canManage = status != 'cancelled' &&
        status != 'expired' &&
        status != 'rejected';
    final canShowQr = status == 'active' || status == 'frozen';
    final canUseForPayment = status == 'active';
    final canReload = status == 'active' || status == 'frozen';
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

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVisualCard(card, isLarge: true),
          const SizedBox(height: 18),
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
              if (canShowQr)
                OutlinedButton.icon(
                  onPressed: () => _showCardQr(card),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('QR'),
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
                  onPressed: _openManagementTab,
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('شحن البطاقة'),
                ),
            ],
          ),
          if (canManage) ...[
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
                OutlinedButton.icon(
                  onPressed: () => _updateStatus(card, 'cancel'),
                  icon: const Icon(Icons.cancel_rounded),
                  label: Text(
                    status == 'pending_approval'
                        ? 'إلغاء الطلب وإرجاع الرصيد'
                        : 'تعطيل نهائي وإرجاع الرصيد',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text('تفاصيل البطاقة', style: AppTheme.h3),
          const SizedBox(height: 10),
          _detailsGrid(card),
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
            Text('لا توجد أنشطة على هذه البطاقة حتى الآن.', style: AppTheme.bodyAction)
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

  Widget _buildSelectedCardHeader(Map<String, dynamic> card) {
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surfaceMuted,
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('البطاقة المحددة للشحن والإدارة', style: AppTheme.caption),
                Text(
                  '${card['label'] ?? '-'}  |  ${card['cardNumber'] ?? '-'}',
                  style: AppTheme.bodyBold,
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.ils((card['balance'] as num?)?.toDouble() ?? 0),
            style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
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
            'أنشئ بطاقة جديدة برصيد مبدئي، وتاريخ انتهاء، وكود أمان من 3 أرقام.',
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
              labelText: 'كود الحماية من 3 أرقام',
              prefixIcon: Icon(Icons.pin_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickExpiry,
            icon: const Icon(Icons.event_rounded),
            label: Text(
              'تنتهي في ${_expiresAt.month.toString().padLeft(2, '0')}/${(_expiresAt.year % 100).toString().padLeft(2, '0')}',
            ),
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

  Widget _buildReloadForm(Map<String, dynamic>? selected) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('شحن بطاقة موجودة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            selected == null
                ? 'اختر بطاقة من تبويب البطاقات أولًا لبدء الشحن.'
                : 'سيتم خصم المبلغ من رصيد حسابك وإضافته إلى البطاقة المحددة.',
            style: AppTheme.bodyAction,
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_rounded, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected['label']?.toString() ?? '',
                          style: AppTheme.bodyBold,
                        ),
                        Text(
                          '${selected['cardNumber'] ?? '-'}  |  ${selected['expiryLabel'] ?? '-'}',
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyFormatter.ils(
                      (selected['balance'] as num?)?.toDouble() ?? 0,
                    ),
                    style: AppTheme.bodyBold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reloadAmountC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'مبلغ الشحن',
                prefixIcon: Icon(Icons.savings_rounded),
              ),
            ),
            const SizedBox(height: 16),
            ShwakelButton(
              label: 'شحن البطاقة',
              icon: Icons.add_circle_outline_rounded,
              isLoading: _isReloading,
              onPressed: _isReloading ? null : _reloadSelectedCard,
            ),
          ],
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
            'يعتمد التحقق على رقم البطاقة والشهر والسنة وكود الحماية من 3 أرقام.',
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
                label: const Text('مسح QR'),
              ),
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
                    labelText: 'الكود',
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
            ..._payments.take(12).map(
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

  Widget _buildVisualCard(
    Map<String, dynamic> card, {
    bool isLarge = false,
  }) {
    final cardId = card['id']?.toString() ?? '';
    final isRevealed = _revealedCardIds.contains(cardId);
    final displayNumber = isRevealed
        ? card['cardNumber']?.toString() ?? ''
        : '•••• •••• •••• ••••';

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
                  card['label']?.toString() ?? '',
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          SizedBox(height: isLarge ? 26 : 18),
          Text(
            displayNumber,
            style: AppTheme.h2.copyWith(
              color: Colors.white,
              letterSpacing: 1.1,
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
          Text(
            CurrencyFormatter.ils(amount),
            style: AppTheme.bodyBold,
          ),
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
