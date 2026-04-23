import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';

class QuickTransferScreen extends StatefulWidget {
  const QuickTransferScreen({super.key});

  @override
  State<QuickTransferScreen> createState() => _QuickTransferScreenState();
}

class _QuickTransferScreenState extends State<QuickTransferScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final TextEditingController _phoneController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _recipient;
  bool _isLoading = true;
  bool _canTransfer = false;
  bool _canViewQuickTransfer = false;
  bool _isLookingUpRecipient = false;
  int _activeTab = 0;
  bool _showLookupTools = false;
  CountryOption _selectedCountry = PhoneNumberService.countries.first;

  String _t(String key) => context.loc.tr(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
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
        _canViewQuickTransfer = appPermissions.canOpenQuickTransfer;
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
    'phone': _user?['whatsapp']?.toString() ?? '',
  });

  Future<void> _scan() async {
    final scannedValue = await showDialog<String>(
      context: context,
      builder: (_) => BarcodeScannerDialog(
        title: _t('screens_quick_transfer_screen.005'),
        description: context.loc.tr('screens_quick_transfer_screen.044'),
        height: 320,
        onCancelLabel: _t('screens_quick_transfer_screen.006'),
      ),
    );
    if (scannedValue != null && scannedValue.isNotEmpty) {
      await _startTransferFromQr(scannedValue);
    }
  }

  Future<void> _startTransferFromQr(String raw) async {
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(raw));
      if (payload['type'] != 'shwakel_transfer') {
        throw _t('screens_quick_transfer_screen.007');
      }
      if (payload['userId'] == _user?['id']?.toString()) {
        throw _t('screens_quick_transfer_screen.008');
      }

      final recipient = <String, dynamic>{
        'id': payload['userId']?.toString() ?? '',
        'username':
            payload['username']?.toString() ??
            _t('screens_quick_transfer_screen.009'),
        'whatsapp': payload['phone']?.toString() ?? '',
        'role': '',
      };
      await _startTransferToRecipient(recipient);
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _lookupRecipient() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      await AppAlertService.showError(
        context,
        title: _t('screens_quick_transfer_screen.010'),
        message: _t('screens_quick_transfer_screen.023'),
      );
      return;
    }

    setState(() => _isLookingUpRecipient = true);
    try {
      final response = await _api.lookupUserByPhone(
        phone: rawPhone,
        countryCode: _selectedCountry.dialCode,
      );
      final recipient = Map<String, dynamic>.from(
        response['user'] as Map? ?? const <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() => _recipient = recipient);
    } catch (error) {
      if (!mounted) return;
      setState(() => _recipient = null);
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

    final amount = await _askAmount(recipient);
    if (amount == null || amount <= 0) {
      return;
    }
    if (!mounted) return;

    final securityResult = await TransferSecurityService.confirmTransfer(
      context,
    );
    if (!securityResult.isVerified) {
      return;
    }

    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      await _api.transferBalance(
        recipientId: recipientId,
        amount: amount,
        otpCode: securityResult.otpCode,
        localAuthMethod: securityResult.method,
        location: location,
      );
      await _load();
      if (!mounted) return;
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_quick_transfer_screen.012'),
        message: _t('screens_quick_transfer_screen.026'),
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<double?> _askAmount(Map<String, dynamic> recipient) {
    return showDialog<double>(
      context: context,
      builder: (dialogContext) {
        final amountController = TextEditingController();
        return AlertDialog(
          title: Text(_t('screens_quick_transfer_screen.013')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecipientPreviewCard(recipient: recipient),
              const SizedBox(height: 20),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _t('screens_quick_transfer_screen.027'),
                  prefixIcon: const Icon(Icons.payments_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('screens_quick_transfer_screen.014')),
            ),
            ShwakelButton(
              label: _t('screens_quick_transfer_screen.015'),
              width: 140,
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  double.tryParse(amountController.text.trim()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_canViewQuickTransfer) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_t('screens_quick_transfer_screen.016')),
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
        drawer: const AppSidebar(),
        body: Center(child: Text(_t('screens_quick_transfer_screen.028'))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_t('screens_quick_transfer_screen.016')),
        actions: [
          IconButton(
            tooltip: _showLookupTools
                ? context.loc.tr('screens_quick_transfer_screen.040')
                : context.loc.tr('screens_quick_transfer_screen.041'),
            onPressed: () =>
                setState(() => _showLookupTools = !_showLookupTools),
            icon: Icon(
              _showLookupTools
                  ? Icons.search_off_rounded
                  : Icons.manage_search_rounded,
            ),
          ),
          IconButton(
            tooltip: context.loc.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: AppTheme.pagePadding(context, top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTransferTabs(),
              const SizedBox(height: 18),
              _buildActiveTransferView(),
            ],
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

  Widget _buildTransferTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: context.loc.tr('screens_quick_transfer_screen.036'),
              icon: Icons.send_rounded,
              index: 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTabButton(
              label: context.loc.tr('screens_quick_transfer_screen.037'),
              icon: Icons.qr_code_2_rounded,
              index: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required int index,
  }) {
    final isActive = _activeTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.bodyBold.copyWith(
                color: isActive ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTransferView() {
    if (_activeTab == 1) {
      return _buildMyCode();
    }

    return Column(
      children: [
        if (_showLookupTools) ...[
          _buildLookupCard(compact: true),
          const SizedBox(height: 18),
        ] else ...[
          ToolToggleHint(
            message: context.loc.tr('screens_quick_transfer_screen.043'),
            icon: Icons.manage_search_rounded,
          ),
          const SizedBox(height: 18),
        ],
        _buildScanCard(),
      ],
    );
  }

  Widget _buildLookupCard({required bool compact}) {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            title: context.loc.tr('screens_quick_transfer_screen.038'),
            subtitle: context.loc.tr('screens_quick_transfer_screen.039'),
            icon: Icons.phone_iphone_rounded,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, innerConstraints) {
              final stackFields = compact || innerConstraints.maxWidth < 520;
              final countryField = DropdownButtonFormField<CountryOption>(
                initialValue: _selectedCountry,
                decoration: InputDecoration(
                  labelText: _t('screens_quick_transfer_screen.017'),
                ),
                items: PhoneNumberService.countries
                    .map(
                      (country) => DropdownMenuItem<CountryOption>(
                        value: country,
                        child: Text('+${country.dialCode}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedCountry = value);
                },
              );
              final phoneField = TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _t('screens_quick_transfer_screen.031'),
                  prefixIcon: const Icon(Icons.phone_rounded),
                ),
                onSubmitted: (_) => _lookupRecipient(),
              );

              if (stackFields) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    countryField,
                    const SizedBox(height: 12),
                    phoneField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 150, child: countryField),
                  const SizedBox(width: 12),
                  Expanded(child: phoneField),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: _t('screens_quick_transfer_screen.018'),
            icon: Icons.search_rounded,
            gradient: AppTheme.primaryGradient,
            isLoading: _isLookingUpRecipient,
            onPressed: _canTransfer ? _lookupRecipient : null,
          ),
          if (!_canTransfer) ...[
            const SizedBox(height: 12),
            ShwakelCard(
              padding: const EdgeInsets.all(16),
              color: AppTheme.warning.withValues(alpha: 0.08),
              borderColor: AppTheme.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
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
          if (_recipient != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppTheme.cardHighlightGradient,
                borderRadius: AppTheme.radiusMd,
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('screens_quick_transfer_screen.019'),
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 14),
                  _RecipientPreviewCard(recipient: _recipient!),
                  const SizedBox(height: 14),
                  Text(
                    _t('screens_quick_transfer_screen.032'),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ShwakelButton(
                    label: _t('screens_quick_transfer_screen.033'),
                    icon: Icons.send_rounded,
                    onPressed: _canTransfer
                        ? () => _startTransferToRecipient(_recipient!)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            title: _t('screens_quick_transfer_screen.020'),
            subtitle: _t('screens_quick_transfer_screen.034'),
            icon: Icons.qr_code_scanner_rounded,
            accent: AppTheme.accent,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: AppTheme.radiusMd,
            ),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppTheme.accent,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.loc.tr('screens_quick_transfer_screen.045'),
                  style: AppTheme.h3.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  context.loc.tr('screens_quick_transfer_screen.046'),
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ShwakelButton(
            label: _t('screens_quick_transfer_screen.021'),
            icon: Icons.qr_code_scanner_rounded,
            isSecondary: true,
            onPressed: _canTransfer ? _scan : null,
          ),
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
          const SizedBox(height: 10),
          Text(
            _t('screens_quick_transfer_screen.035'),
            style: AppTheme.caption.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.radiusMd,
            ),
            child: QrImageView(data: _payload(), size: 240),
          ),
          const SizedBox(height: 24),
          Text(
            _user?['username']?.toString() ?? '',
            style: AppTheme.h1.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          if ((_user?['whatsapp']?.toString() ?? '').isNotEmpty)
            Text(
              _user?['whatsapp']?.toString() ?? '',
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.h3),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ],
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
      default:
        return l.tr('screens_quick_transfer_screen.003');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final username = recipient['username']?.toString().trim();
    final phone = recipient['whatsapp']?.toString().trim() ?? '';
    final role = recipient['role']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username?.isNotEmpty == true
                      ? username!
                      : l.tr('screens_quick_transfer_screen.004'),
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 4),
                Text(_maskedPhone(phone), style: AppTheme.bodyAction),
              ],
            ),
          ),
          Container(
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
          ),
        ],
      ),
    );
  }
}
