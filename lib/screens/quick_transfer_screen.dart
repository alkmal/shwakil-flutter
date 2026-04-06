import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class QuickTransferScreen extends StatefulWidget {
  const QuickTransferScreen({super.key});

  @override
  State<QuickTransferScreen> createState() => _QuickTransferScreenState();
}

class _QuickTransferScreenState extends State<QuickTransferScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final MobileScannerController _camC = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _phoneController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _recipient;
  bool _isLoading = true;
  bool _canTransfer = false;
  bool _isLookingUpRecipient = false;
  CountryOption _selectedCountry = PhoneNumberService.countries.first;

  String _t(String key, [String? english]) =>
      english == null ? context.loc.tr(key) : context.loc.text(key, english);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _camC.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final u = await _auth.currentUser();
      if (!mounted) {
        return;
      }
      setState(() {
        _user = u;
        _canTransfer = u?['permissions']?['canTransfer'] == true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
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
    await showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ShwakelCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('screens_quick_transfer_screen.005'),
                  style: AppTheme.h3,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: AppTheme.radiusMd,
                  child: SizedBox(
                    height: 320,
                    child: MobileScanner(
                      controller: _camC,
                      onDetect: (capture) {
                        final rawValue = capture.barcodes.first.rawValue ?? '';
                        if (rawValue.isNotEmpty) {
                          Navigator.pop(dialogContext, rawValue);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ShwakelButton(
                  label: _t('screens_quick_transfer_screen.006'),
                  isSecondary: true,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((value) {
      if (value != null && value is String) {
        _startTransferFromQr(value);
      }
    });
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
      if (!mounted) {
        return;
      }
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
        message: _t(
          'أدخل رقم الهاتف للبحث عن المستلم.',
          'Enter a phone number to find the recipient.',
        ),
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
      if (!mounted) {
        return;
      }
      setState(() => _recipient = recipient);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _recipient = null);
      await AppAlertService.showError(
        context,
        title: _t('تعذر العثور على المستخدم', 'Could not find the user'),
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
        message: _t(
          'تعذر تحديد حساب المستلم.',
          'Could not determine the recipient account.',
        ),
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
    if (!mounted) {
      return;
    }

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
        location: location,
      );
      await _load();
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_quick_transfer_screen.012'),
        message: _t(
          'تم إرسال الرصيد بنجاح إلى المستلم.',
          'The balance was sent successfully to the recipient.',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
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
                  labelText: _t(
                    'المبلغ المراد تحويله (₪)',
                    'Amount to transfer (₪)',
                  ),
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
    if (!_canTransfer) {
      return Scaffold(
        body: Center(
          child: Text(
            _t(
              'لا تملك صلاحية استخدام التحويل السريع.',
              'You do not have permission to use quick transfer.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(_t('screens_quick_transfer_screen.016'))),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              ShwakelCard(
                padding: const EdgeInsets.all(24),
                shadowLevel: ShwakelShadowLevel.medium,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.phone_iphone_rounded,
                            color: AppTheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  'إرسال الرصيد برقم الهاتف',
                                  'Send balance by phone number',
                                ),
                                style: AppTheme.h3,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  'أدخل رقم المستلم فقط، ثم راجع بياناته الأساسية بدون إظهار أي معلومات مالية.',
                                  'Enter only the recipient phone number, then review basic details without showing any financial information.',
                                ),
                                style: AppTheme.bodyAction,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 520;
                        final countryField =
                            DropdownButtonFormField<CountryOption>(
                              initialValue: _selectedCountry,
                              decoration: InputDecoration(
                                labelText: _t(
                                  'screens_quick_transfer_screen.017',
                                ),
                              ),
                              items: PhoneNumberService.countries
                                  .map(
                                    (country) =>
                                        DropdownMenuItem<CountryOption>(
                                          value: country,
                                          child: Text('+${country.dialCode}'),
                                        ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                setState(() => _selectedCountry = value);
                              },
                            );
                        final phoneField = TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: _t(
                              'رقم هاتف المستلم',
                              'Recipient phone number',
                            ),
                            prefixIcon: const Icon(Icons.phone_rounded),
                          ),
                          onSubmitted: (_) => _lookupRecipient(),
                        );

                        if (isCompact) {
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
                            SizedBox(width: 140, child: countryField),
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
                      isLoading: _isLookingUpRecipient,
                      onPressed: _lookupRecipient,
                    ),
                    if (_recipient != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: AppTheme.radiusMd,
                          border: Border.all(color: AppTheme.border),
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
                              _t(
                                'لأسباب تتعلق بالخصوصية لا يتم عرض رصيد المستلم.',
                                'For privacy reasons, the recipient balance is not displayed.',
                              ),
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ShwakelButton(
                              label: _t(
                                'إرسال الرصيد لهذا الرقم',
                                'Send balance to this number',
                              ),
                              icon: Icons.send_rounded,
                              onPressed: () =>
                                  _startTransferToRecipient(_recipient!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ShwakelCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: AppTheme.accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t('screens_quick_transfer_screen.020'),
                                style: AppTheme.h3,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _t(
                                  'يمكنك أيضًا مسح رمز المستلم لإكمال التحويل بسرعة.',
                                  'You can also scan the recipient code to complete the transfer faster.',
                                ),
                                style: AppTheme.bodyAction,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ShwakelButton(
                      label: _t('screens_quick_transfer_screen.021'),
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: _scan,
                      isSecondary: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildMyCode(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyCode() {
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      gradient: AppTheme.darkGradient,
      child: Column(
        children: [
          Text(
            _t('screens_quick_transfer_screen.022'),
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'اعرض هذا الرمز للمرسل ليتمكن من تحويل الرصيد إليك مباشرة.',
              'Show this code to the sender so they can transfer balance to you directly.',
            ),
            style: AppTheme.caption.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.radiusMd,
            ),
            child: QrImageView(data: _payload(), size: 240),
          ),
          const SizedBox(height: 32),
          Text(
            _user?['username']?.toString() ?? '',
            style: AppTheme.h1.copyWith(color: Colors.white),
          ),
          Text(
            _user?['whatsapp']?.toString() ?? '',
            style: AppTheme.bodyBold.copyWith(color: Colors.white70),
          ),
        ],
      ),
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
