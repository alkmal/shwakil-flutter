import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/country_selector_field.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class QuickTransferScreen extends StatefulWidget {
  const QuickTransferScreen({
    super.key,
    this.initialTab = 0,
    this.merchantReceiveOnly = false,
  });

  final int initialTab;
  final bool merchantReceiveOnly;

  @override
  State<QuickTransferScreen> createState() => _QuickTransferScreenState();
}

class _QuickTransferScreenState extends State<QuickTransferScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _lastTransferReport;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;
  bool _isLoading = true;
  bool _canTransfer = false;
  bool _isLookingUpRecipient = false;
  bool _isTransfering = false;
  String _selectedCountryCode = PhoneNumberService.countries.first.dialCode;

  String _t(String key) => context.loc.tr(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final u = await _auth.currentUser();
      if (!mounted) return;
      final appPermissions = AppPermissions.fromUser(u);
      setState(() {
        _user = u;
        _canTransfer = appPermissions.canTransfer;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _payload() => jsonEncode({
    'type': 'shwakel_transfer',
    'userId': _user?['id']?.toString() ?? '',
    'username': _user?['username']?.toString() ?? '',
    'phone': PhoneNumberService.localDisplay(_user?['whatsapp']?.toString()),
  });

  Future<void> _lookupRecipient() async {
    final rawPhone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (rawPhone.isEmpty) {
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.010'),
        message: _t('screens_quick_transfer_screen.023'),
      );
      return;
    }
    if (amount <= 0) {
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.049'),
        message: _t('screens_quick_transfer_screen.050'),
      );
      return;
    }

    setState(() => _isLookingUpRecipient = true);
    try {
      final response = await _api.lookupUserByPhone(
        phone: rawPhone,
        countryCode: _selectedCountryCode,
      );
      final recipient = Map<String, dynamic>.from(
        response['user'] as Map? ?? const <String, dynamic>{},
      );
      if (!mounted) return;
      await _startTransferToRecipient(recipient);
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.024'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isLookingUpRecipient = false);
      }
    }
  }

  Future<void> _startTransferToRecipient(Map<String, dynamic> recipient) async {
    final l = context.loc;
    final recipientId = recipient['id']?.toString() ?? '';
    if (recipientId.isEmpty) {
      await AppAlertService.showError(
        context,
        message: _t('screens_quick_transfer_screen.025'),
      );
      return;
    }
    if (recipientId == _user?['id']?.toString()) {
      await AppAlertService.showError(
        context,
        message: _t('screens_quick_transfer_screen.011'),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.049'),
        message: _t('screens_quick_transfer_screen.050'),
      );
      return;
    }
    if (!mounted) return;

    final fee = _transferFee(amount);
    final creditedAmount = double.parse((amount - fee).toStringAsFixed(2));
    if (creditedAmount <= 0) {
      await AppAlertService.showError(
        context,
        title: l.text('قيمة غير صالحة', 'Invalid amount'),
        message: 'المبلغ بعد الخصم غير صالح للتحويل.',
      );
      return;
    }

    final confirmed = await _showTransferConfirmation(
      recipient: recipient,
      amount: amount,
      fee: fee,
      creditedAmount: creditedAmount,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final securityResult = await TransferSecurityService.confirmTransfer(
      context,
    );
    if (!securityResult.isVerified) {
      return;
    }

    var progressShown = false;
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      if (!mounted) return;
      setState(() => _isTransfering = true);
      _showTransferProgressDialog();
      progressShown = true;
      final response = await _api.transferBalance(
        recipientId: recipientId,
        amount: amount,
        otpCode: securityResult.otpCode,
        securityPin: securityResult.securityPin,
        localAuthMethod: securityResult.method,
        location: location,
      );
      await _load();
      if (!mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      final report = _buildTransferReport(
        recipient: recipient,
        requestedAmount: amount,
        response: response,
      );
      setState(() {
        _lastTransferReport = report;
        _amountController.clear();
      });
      await _showTransferReport(report);
    } catch (error) {
      if (!mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.051'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isTransfering = false);
      }
    }
  }

  void _showTransferProgressDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                _t('screens_quick_transfer_screen.047'),
                style: AppTheme.bodyBold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _t('screens_quick_transfer_screen.048'),
                textAlign: TextAlign.center,
                style: AppTheme.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _transferFee(double amount) {
    final percent =
        (_user?['effectiveTransferFeePercent'] as num?)?.toDouble() ??
        (_user?['customTransferFeePercent'] as num?)?.toDouble() ??
        1.0;
    return double.parse((amount * (percent / 100)).toStringAsFixed(2));
  }

  Future<bool?> _showTransferConfirmation({
    required Map<String, dynamic> recipient,
    required double amount,
    required double fee,
    required double creditedAmount,
  }) {
    final l = context.loc;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l.text('تأكيد التحويل', 'Confirm transfer')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RecipientPreviewCard(recipient: recipient),
                const SizedBox(height: 16),
                _transferDetailRow(
                  l.text('قيمة التحويل', 'Transfer amount'),
                  CurrencyFormatter.ils(amount),
                ),
                const SizedBox(height: 8),
                _transferDetailRow(
                  l.text('قيمة الخصم', 'Deduction'),
                  fee <= 0
                      ? l.text('مجانا عرض خاص', 'Free special offer')
                      : CurrencyFormatter.ils(fee),
                ),
                const SizedBox(height: 8),
                _transferDetailRow(
                  l.text('الصافي للمستلم', 'Net to recipient'),
                  CurrencyFormatter.ils(creditedAmount),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('screens_quick_transfer_screen.014')),
            ),
            ShwakelButton(
              label: l.text('تأكيد', 'Confirm'),
              width: 140,
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _transferDetailRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: AppTheme.bodyBold),
      ],
    );
  }

  Map<String, dynamic> _buildTransferReport({
    required Map<String, dynamic> recipient,
    required double requestedAmount,
    required Map<String, dynamic> response,
  }) {
    final fee =
        (response['fee'] as num?)?.toDouble() ?? _transferFee(requestedAmount);
    final credited =
        (response['creditedAmount'] as num?)?.toDouble() ??
        double.parse((requestedAmount - fee).toStringAsFixed(2));
    return {
      'status': response['pendingApproval'] == true ? 'pending' : 'completed',
      'message':
          response['message']?.toString() ??
          _t('screens_quick_transfer_screen.026'),
      'recipient': recipient,
      'amount':
          (response['grossAmount'] as num?)?.toDouble() ?? requestedAmount,
      'fee': fee,
      'creditedAmount': credited,
      'balance': (response['balance'] as num?)?.toDouble(),
      'requestId': response['requestId']?.toString() ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _showTransferReport(Map<String, dynamic> report) {
    final l = context.loc;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('تقرير التحويل', 'Transfer report')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(child: _transferReportCard(report)),
        ),
        actions: [
          ShwakelButton(
            label: l.text('تحميل التقرير', 'Download report'),
            icon: Icons.picture_as_pdf_rounded,
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _shareTransferReportPdf(report);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.text('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  Widget _transferReportCard(Map<String, dynamic> report) {
    final recipient = Map<String, dynamic>.from(
      report['recipient'] as Map? ?? const {},
    );
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report['status'] == 'pending'
                    ? Icons.pending_actions_rounded
                    : Icons.check_circle_rounded,
                color: report['status'] == 'pending'
                    ? AppTheme.warning
                    : AppTheme.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report['message']?.toString() ?? '',
                  style: AppTheme.bodyBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RecipientPreviewCard(recipient: recipient),
          const SizedBox(height: 14),
          _transferDetailRow(
            'قيمة التحويل',
            CurrencyFormatter.ils(_reportNum(report, 'amount')),
          ),
          const SizedBox(height: 8),
          _transferDetailRow(
            'قيمة الخصم',
            CurrencyFormatter.ils(_reportNum(report, 'fee')),
          ),
          const SizedBox(height: 8),
          _transferDetailRow(
            'الصافي للمستلم',
            CurrencyFormatter.ils(_reportNum(report, 'creditedAmount')),
          ),
          if (report['balance'] is num) ...[
            const SizedBox(height: 8),
            _transferDetailRow(
              'رصيدك بعد العملية',
              CurrencyFormatter.ils(_reportNum(report, 'balance')),
            ),
          ],
        ],
      ),
    );
  }

  double _reportNum(Map<String, dynamic> report, String key) =>
      (report[key] as num?)?.toDouble() ?? 0;

  Future<void> _shareTransferReportPdf(Map<String, dynamic> report) async {
    _pdfRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _pdfBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
    final recipient = Map<String, dynamic>.from(
      report['recipient'] as Map? ?? const {},
    );
    final recipientName = UserDisplayName.fromMap(recipient, fallback: '-');
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: _pdfRegularFont!,
          bold: _pdfBoldFont!,
        ),
        build: (_) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'تقرير تحويل شواكل',
                style: pw.TextStyle(fontSize: 22, font: _pdfBoldFont),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'الحالة: ${report['status'] == 'pending' ? 'بانتظار الموافقة' : 'مكتمل'}',
              ),
              pw.Text('المستلم: $recipientName'),
              pw.Text(
                'قيمة التحويل: ${CurrencyFormatter.ils(_reportNum(report, 'amount'))}',
              ),
              pw.Text(
                'قيمة الخصم: ${CurrencyFormatter.ils(_reportNum(report, 'fee'))}',
              ),
              pw.Text(
                'الصافي للمستلم: ${CurrencyFormatter.ils(_reportNum(report, 'creditedAmount'))}',
              ),
              if (report['balance'] is num)
                pw.Text(
                  'رصيدك بعد العملية: ${CurrencyFormatter.ils(_reportNum(report, 'balance'))}',
                ),
              pw.Text('وقت التنفيذ: ${report['createdAt'] ?? ''}'),
            ],
          ),
        ),
      ),
    );
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'shwakel-transfer-report.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_canTransfer) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(
            widget.merchantReceiveOnly
                ? 'استلام التاجر'
                : _t('screens_quick_transfer_screen.016'),
          ),
          actions: [
            IconButton(
              tooltip: context.loc.tr('screens_admin_customers_screen.041'),
              onPressed: _showHelpDialog,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
        ),
        drawer: AppSidebar.drawerFor(context),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _t('screens_quick_transfer_screen.053'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.merchantReceiveOnly
              ? 'استلام التاجر'
              : _t('screens_quick_transfer_screen.016'),
        ),
        actions: [
          IconButton(
            tooltip: context.loc.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: AppTheme.pagePadding(context, top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_buildActiveTransferView()],
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    await AppAlertService.showInfo(
      context,
      title: context.loc.tr('screens_transactions_screen.039'),
      message: context.loc.tr('screens_quick_transfer_screen.042'),
    );
  }

  Widget _buildActiveTransferView() {
    if (widget.merchantReceiveOnly) {
      return Column(children: [_buildMyCode()]);
    }

    return Column(
      children: [
        _buildLookupCard(compact: true),
        if (_lastTransferReport != null) ...[
          const SizedBox(height: 18),
          _transferReportCard(_lastTransferReport!),
        ],
      ],
    );
  }

  Widget _buildLookupCard({required bool compact}) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            title: l.text('تحويل سريع', 'Quick transfer'),
            subtitle: l.text(
              'أدخل رقم الهاتف والقيمة فقط، ثم راجع تفاصيل التحويل قبل التأكيد.',
              'Enter phone number and amount only, then review transfer details before confirming.',
            ),
            icon: Icons.phone_iphone_rounded,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, innerConstraints) {
              final phoneField = TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _t('screens_quick_transfer_screen.031'),
                  prefixIcon: const Icon(Icons.phone_rounded),
                ),
                onSubmitted: (_) => _lookupRecipient(),
              );
              return Column(
                children: [
                  CountrySelectorField(
                    value: _selectedCountryCode,
                    compact: true,
                    onChanged: (value) =>
                        setState(() => _selectedCountryCode = value),
                  ),
                  const SizedBox(height: 12),
                  phoneField,
                  const SizedBox(height: 14),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('screens_quick_transfer_screen.027'),
                      prefixIcon: const Icon(Icons.payments_rounded),
                    ),
                    onSubmitted: (_) => _lookupRecipient(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: l.text('متابعة التحويل', 'Continue transfer'),
            icon: Icons.arrow_forward_rounded,
            gradient: AppTheme.primaryGradient,
            isLoading: _isLookingUpRecipient || _isTransfering,
            onPressed: (_canTransfer && !_isTransfering)
                ? _lookupRecipient
                : null,
          ),
          if (!_canTransfer) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('screens_quick_transfer_screen.028'),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMyCode() {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.darkGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      borderColor: Colors.white.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _t('screens_quick_transfer_screen.022'),
            style: AppTheme.h2.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.radiusMd,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final qrSize = constraints.maxWidth < 320
                    ? constraints.maxWidth - 32
                    : 240.0;
                return QrImageView(
                  data: _payload(),
                  size: qrSize.clamp(160.0, 240.0),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _user?['username']?.toString() ?? '',
            style: AppTheme.h1.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          if ((_user?['whatsapp']?.toString() ?? '').isNotEmpty)
            Text(
              PhoneNumberService.localDisplay(_user?['whatsapp']?.toString()),
              style: AppTheme.bodyBold.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeading({
    required String title,
    required String subtitle,
    required IconData icon,
    Color accent = AppTheme.primary,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final badge = Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: accent),
        );
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.h3),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 14)),
            ],
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [badge, const SizedBox(height: 12), text],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            badge,
            const SizedBox(width: 14),
            Expanded(child: text),
          ],
        );
      },
    );
  }
}

class _RecipientPreviewCard extends StatelessWidget {
  const _RecipientPreviewCard({required this.recipient});

  final Map<String, dynamic> recipient;

  String _maskedPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) {
      return phone;
    }
    final start = digits.substring(0, 4);
    final end = digits.substring(digits.length - 2);
    return '$start••••$end';
  }

  String _roleLabel(BuildContext context, String role) {
    final l = context.loc;
    switch (role) {
      case 'admin':
        return l.tr('screens_quick_transfer_screen.001');
      case 'support':
        return l.tr('screens_quick_transfer_screen.002');
      case 'driver':
        return l.tr('shared.role_driver');
      case 'verified_member':
        return l.tr('shared.role_verified_member');
      case 'advanced_member':
        return l.tr('shared.role_verified_member');
      default:
        return l.tr('screens_quick_transfer_screen.003');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final username = recipient['username']?.toString().trim();
    final phone = PhoneNumberService.localDisplay(
      recipient['whatsapp']?.toString(),
    );
    final role = recipient['role']?.toString().trim() ?? '';
    final displayName = UserDisplayName.fromMap(
      recipient,
      fallback: username?.isNotEmpty == true
          ? username!
          : l.tr('screens_quick_transfer_screen.004'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final avatar = Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_rounded, color: AppTheme.primary),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName, style: AppTheme.bodyBold),
              const SizedBox(height: 4),
              Text(
                username?.isNotEmpty == true
                    ? '@$username'
                    : _maskedPhone(phone),
                style: AppTheme.bodyAction,
              ),
              if (username?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(_maskedPhone(phone), style: AppTheme.caption),
              ],
            ],
          );
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _roleLabel(context, role),
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 10),
                badge,
              ],
            );
          }

          return Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(child: info),
              const SizedBox(width: 8),
              badge,
            ],
          );
        },
      ),
    );
  }
}
