import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import '../widgets/support_ticket_actions.dart';
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
    if (!RegExp(r'^05\d{8}$').hasMatch(whatsapp)) {
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
    return _whatsappC.text.replaceAll(RegExp(r'\D+'), '');
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.pageBackgroundGradient,
        ),
        child: SafeArea(
          child: ResponsiveScaffoldContainer(
            maxWidth: 1100,
            padding: AppTheme.pagePadding(context, top: 20),
            child: Center(
              child: SingleChildScrollView(child: _buildRegistrationLayout()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 780) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: _buildRegisterHero()),
                const SizedBox(width: 28),
                Expanded(flex: 6, child: _buildRegisterControls()),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRegisterHero(),
              const SizedBox(height: 22),
              _buildRegisterControls(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRegisterHero() {
    final l = context.loc;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShwakelLogo(size: 82, framed: true),
          const SizedBox(height: 18),
          Text(l.tr('main.001'), style: AppTheme.h1.copyWith(fontSize: 34)),
          const SizedBox(height: 8),
          Text(
            l.tr('main.006'),
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterControls() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.tr('screens_register_screen.009'), style: AppTheme.h1),
        const SizedBox(height: 8),
        Text(
          l.tr('screens_register_screen.039'),
          style: AppTheme.bodyAction.copyWith(
            color: AppTheme.textSecondary,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
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
              helperText: l.tr('screens_register_screen.047'),
            ),
            if ((_pendingReferralCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildReferralAppliedCard(),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: Text(l.tr('screens_register_screen.040')),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: AppTheme.radiusMd,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                l.tr('screens_register_screen.041'),
                style: AppTheme.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 8),
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
        const SizedBox(height: 16),
        SupportTicketActions(supportWhatsapp: _supportWhatsapp ?? ''),
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
                  if ((_supportWhatsapp ?? '').isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SupportTicketActions(supportWhatsapp: _supportWhatsapp!),
                  ],
                  const SizedBox(height: 24),
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

  Widget _buildReferralAppliedCard() {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final title = isEnglish ? 'Applied referral' : 'إحالة مطبقة تلقائيًا';
    final subtitle = isEnglish
        ? 'This registration will use the referral code captured from your invite link.'
        : 'سيتم استخدام رمز الإحالة الملتقط من رابط الدعوة تلقائيًا في هذا التسجيل.';

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
          ? [FilteringTextInputFormatter.digitsOnly]
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
