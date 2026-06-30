import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/auth_screen_shell.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import 'otp_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _registrationDefaultCountryCode = '970';

  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  final _fullNameC = TextEditingController();
  final _whatsappC = TextEditingController();

  bool _isLoading = false;
  bool _isCheckingPendingRegistration = true;
  bool _registrationEnabled = true;
  bool _termsAccepted = false;
  String? _supportWhatsapp;
  String? _pendingReferralCode;

  @override
  void initState() {
    super.initState();
    OfflineSessionService.setOfflineMode(false);
    unawaited(_authService.logout());
    _loadSettings();
    _loadPendingReferral();
    _checkPendingRegistrationForDevice();
  }

  @override
  void dispose() {
    _fullNameC.dispose();
    _whatsappC.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final results = await Future.wait<dynamic>([
        _apiService.getAuthSettings(),
        ContactInfoService.getContactInfo(),
      ]);
      final settings = Map<String, dynamic>.from(results[0] as Map);
      final contact = Map<String, dynamic>.from(results[1] as Map);
      if (!mounted) {
        return;
      }
      setState(() {
        _registrationEnabled = settings['registrationEnabled'] == true;
        _supportWhatsapp = ContactInfoService.supportWhatsapp(contact);
      });
    } catch (_) {}
  }

  Future<void> _loadPendingReferral() async {
    final referralCode =
        await ReferralAttributionService.getPendingReferralCode();
    if (!mounted) {
      return;
    }

    setState(() => _pendingReferralCode = referralCode);
  }

  Future<void> _checkPendingRegistrationForDevice() async {
    try {
      final result = await _authService
          .getPendingRegistrationForCurrentDevice();
      if (!mounted) {
        return;
      }

      final pendingRegistration = result.pendingRegistration;
      if (result.hasPendingRegistration && pendingRegistration != null) {
        final whatsapp =
            pendingRegistration['whatsapp']?.toString().trim() ?? '';
        final fullName =
            pendingRegistration['fullName']?.toString().trim() ?? '';
        final countryCode =
            pendingRegistration['countryCode']?.toString().trim() ?? '';
        final pendingRegistrationId =
            pendingRegistration['id']?.toString().trim() ?? '';

        if (whatsapp.isNotEmpty && pendingRegistrationId.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                fullName: fullName,
                username: pendingRegistration['username']?.toString() ?? '',
                whatsapp: whatsapp,
                countryCode: countryCode,
                termsAccepted: true,
                referralPhone: _pendingReferralCode,
                pendingRegistrationId: pendingRegistrationId,
                purpose: 'register',
                statusMessage: result.message,
              ),
            ),
          );
          return;
        }
      }
    } catch (_) {
      // Do not block registration if the pending lookup fails.
    } finally {
      if (mounted) {
        setState(() => _isCheckingPendingRegistration = false);
      }
    }
  }

  String? _validatePersonalStep() {
    final l = context.loc;
    final fullName = _fullNameC.text.trim();
    if (fullName.isEmpty || fullName.length < 4) {
      return l.tr('screens_register_screen.029');
    }
    return null;
  }

  String? _validateContactStep() {
    final l = context.loc;
    final whatsapp = _registrationWhatsappInput();
    if (!PhoneNumberService.isSupportedMobile(
      whatsapp,
      defaultDialCode: _registrationDefaultCountryCode,
    )) {
      return l.tr('screens_register_screen.031');
    }

    return null;
  }

  String? _validateConfirmationStep() {
    final l = context.loc;
    if (!_termsAccepted) {
      return l.tr('screens_register_screen.038');
    }

    return null;
  }

  Future<void> _register() async {
    final l = context.loc;
    final localError =
        _validatePersonalStep() ??
        _validateContactStep() ??
        _validateConfirmationStep();
    if (localError != null) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_register_screen.007'),
        message: localError,
        extraContext: _registrationErrorContext(action: 'local_validation'),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final whatsapp = _registrationWhatsappInput();
      final otp = await _authService.startRegistration(
        fullName: _fullNameC.text.trim(),
        whatsapp: whatsapp,
        countryCode: _registrationDefaultCountryCode,
        termsAccepted: true,
        referralPhone: _pendingReferralCode,
      );

      if (!mounted) {
        return;
      }

      if (otp.loginRequired == true) {
        await AppAlertService.showInfo(
          context,
          title: l.tr('screens_register_screen.028'),
          message:
              otp.message ?? 'هذا الرقم مرتبط مسبقًا، انتقل إلى تسجيل الدخول.',
        );
        if (!mounted) {
          return;
        }
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: {'initialIdentifier': otp.loginIdentifier ?? whatsapp},
        );
        return;
      }

      final pendingRegistrationId = otp.pendingRegistrationId?.trim() ?? '';
      if (pendingRegistrationId.isNotEmpty && otp.otpRequired != false) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              fullName: _fullNameC.text.trim(),
              username: '',
              whatsapp: otp.whatsapp?.trim().isNotEmpty == true
                  ? otp.whatsapp!.trim()
                  : whatsapp,
              countryCode: _registrationDefaultCountryCode,
              termsAccepted: true,
              referralPhone: _pendingReferralCode,
              pendingRegistrationId: pendingRegistrationId,
              purpose: 'register',
              initialDebugOtpCode: otp.debugOtpCode,
              statusMessage: otp.message,
            ),
          ),
        );
        return;
      }

      if (otp.otpRequired == false) {
        await AppAlertService.showSuccess(
          context,
          title: l.tr('screens_register_screen.009'),
          message:
              otp.message ?? 'تم تسجيل بياناتكم، وسيتم التواصل معكم للتفاصيل.',
        );
        if (!mounted) {
          return;
        }
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: _fullNameC.text.trim(),
            username: '',
            whatsapp: whatsapp,
            countryCode: _registrationDefaultCountryCode,
            termsAccepted: true,
            referralPhone: _pendingReferralCode,
            pendingRegistrationId: pendingRegistrationId,
            purpose: 'register',
            initialDebugOtpCode: otp.debugOtpCode,
            statusMessage: otp.message,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_register_screen.008'),
        message: ErrorMessageService.sanitize(error),
        extraContext: _registrationErrorContext(action: 'start_registration'),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _registrationWhatsappInput() {
    return PhoneNumberService.normalize(
      input: _whatsappC.text,
      defaultDialCode: _registrationDefaultCountryCode,
    );
  }

  Map<String, dynamic> _registrationErrorContext({required String action}) {
    final normalizedWhatsapp = PhoneNumberService.normalize(
      input: _whatsappC.text,
      defaultDialCode: _registrationDefaultCountryCode,
    );
    return {
      'screen': 'register',
      'action': action,
      'enteredFullName': _fullNameC.text.trim(),
      'enteredWhatsapp': _whatsappC.text.trim(),
      'normalizedWhatsapp': normalizedWhatsapp,
      'countryCode': 'auto',
      'defaultCountryCode': _registrationDefaultCountryCode,
      'termsAccepted': _termsAccepted,
      'referralPhone': _pendingReferralCode ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPendingRegistration) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_registrationEnabled) {
      return _buildDisabledState();
    }

    return AuthScreenShell(
      title: context.loc.tr('screens_register_screen.009'),
      subtitle: context.loc.tr('main.006'),
      child: _buildRegisterControls(),
    );
  }

  Widget _buildRegisterControls() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              l.tr('screens_register_screen.011'),
              _fullNameC,
              Icons.badge_rounded,
            ),
            const SizedBox(height: 16),
            _field(
              l.tr('screens_register_screen.017'),
              _whatsappC,
              Icons.chat_rounded,
              type: TextInputType.phone,
            ),
            if ((_pendingReferralCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildReferralAppliedCard(),
            ],
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _termsAccepted,
              onChanged: (value) {
                setState(() => _termsAccepted = value ?? false);
              },
              title: Text(
                l.tr('screens_register_screen.042'),
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.bold),
              ),
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.primary,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),
            ShwakelButton(
              label: l.tr('screens_register_screen.023'),
              onPressed: _register,
              isLoading: _isLoading,
              icon: Icons.assignment_turned_in_rounded,
              iconAtEnd: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSecondaryActions(l),
      ],
    );
  }

  Widget _buildDisabledState() {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ResponsiveScaffoldContainer(
            maxWidth: 560,
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: ShwakelCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.pause_circle_filled_rounded,
                    size: 64,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.tr('screens_register_screen.043'),
                    textAlign: TextAlign.center,
                    style: AppTheme.h2,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.tr('screens_register_screen.044'),
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyAction.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if ((_supportWhatsapp ?? '').isNotEmpty) ...[
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/support-tickets'),
                      child: Text(l.text('الدعم', 'Support')),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ShwakelButton(
                    label: l.tr('screens_register_screen.046'),
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/login'),
                    isSecondary: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActions(AppLocalizer l) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          child: Text(l.tr('screens_register_screen.040')),
        ),
        if ((_supportWhatsapp ?? '').isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/support-tickets'),
            child: Text(l.text('الدعم', 'Support')),
          ),
      ],
    );
  }

  Widget _buildReferralAppliedCard() {
    final l = context.loc;
    final title = l.text('إحالة مطبقة تلقائيًا', 'Applied referral');
    final subtitle = l.text(
      'سيتم استخدام رمز الإحالة الملتقط من رابط الدعوة تلقائيًا في هذا التسجيل.',
      'This registration will use the referral code captured from your invite link.',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTheme.caption.copyWith(
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(_pendingReferralCode ?? '', style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    bool readOnly = false,
    VoidCallback? onTap,
    String? prefix,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      inputFormatters: type == TextInputType.phone
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))]
          : null,
      obscureText: obscure,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        prefixText: prefix,
        helperText: helperText,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
