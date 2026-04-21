import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import '../widgets/support_contact_card.dart';
import 'otp_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-zA-Z0-9._@+-]{3,32}$');
  static final RegExp _passwordLetterPattern = RegExp(r'[A-Za-z\u0600-\u06FF]');
  static final RegExp _passwordSymbolPattern = RegExp(
    r'[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:\|,.<>\/\?~`]',
  );

  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  final _fullNameC = TextEditingController();
  final _usernameC = TextEditingController();
  final _passwordC = TextEditingController();
  final _confirmPassC = TextEditingController();
  final _whatsappC = TextEditingController();
  final _referralPhoneC = TextEditingController();

  bool _isLoading = false;
  bool _registrationEnabled = true;
  bool _termsAccepted = false;
  CountryOption _selectedCountry = PhoneNumberService.countries.first;
  String? _supportWhatsapp;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _fullNameC.dispose();
    _usernameC.dispose();
    _passwordC.dispose();
    _confirmPassC.dispose();
    _whatsappC.dispose();
    _referralPhoneC.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _apiService.getAuthSettings();
      final contact = await ContactInfoService.getContactInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _registrationEnabled = settings['registrationEnabled'] == true;
        _supportWhatsapp = ContactInfoService.supportWhatsapp(contact);
      });
    } catch (_) {}
  }

  String? _validatePersonalStep() {
    final l = context.loc;
    final fullName = _fullNameC.text.trim();
    final username = _usernameC.text.trim();
    if (fullName.isEmpty || fullName.length < 4) {
      return l.tr('screens_register_screen.029');
    }
    if (username.isEmpty) {
      return l.tr('screens_register_screen.002');
    }
    if (!_usernamePattern.hasMatch(username)) {
      return l.tr('screens_register_screen.030');
    }
    return null;
  }

  String? _validateContactStep() {
    final l = context.loc;
    final whatsapp = PhoneNumberService.normalize(
      input: _whatsappC.text,
      defaultDialCode: _selectedCountry.dialCode,
    );
    if (whatsapp.isEmpty ||
        whatsapp.length < _selectedCountry.dialCode.length + 8) {
      return l.tr('screens_register_screen.031');
    }

    if (_referralPhoneC.text.trim().isNotEmpty) {
      final referral = PhoneNumberService.normalize(
        input: _referralPhoneC.text,
        defaultDialCode: _selectedCountry.dialCode,
      );
      if (referral.length < _selectedCountry.dialCode.length + 8) {
        return l.tr('screens_register_screen.032');
      }
    }

    return null;
  }

  String? _validateSecurityStep() {
    final l = context.loc;
    final password = _passwordC.text;
    final confirm = _confirmPassC.text;

    if (password.trim().isEmpty) {
      return l.tr('screens_register_screen.006');
    }
    if (password.length < 8) {
      return l.tr('screens_register_screen.033');
    }
    if (!_passwordLetterPattern.hasMatch(password)) {
      return l.tr('screens_register_screen.034');
    }
    if (!_passwordSymbolPattern.hasMatch(password)) {
      return l.tr('screens_register_screen.035');
    }
    if (confirm.trim().isEmpty) {
      return l.tr('screens_register_screen.036');
    }
    if (password != confirm) {
      return l.tr('screens_register_screen.037');
    }
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
        _validateSecurityStep();
    if (localError != null) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_register_screen.007'),
        message: localError,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final whatsapp = PhoneNumberService.normalize(
        input: _whatsappC.text,
        defaultDialCode: _selectedCountry.dialCode,
      );
      final referralPhone = _referralPhoneC.text.trim().isEmpty
          ? null
          : PhoneNumberService.normalize(
              input: _referralPhoneC.text,
              defaultDialCode: _selectedCountry.dialCode,
            );
      final otp = await _authService.startRegistration(
        fullName: _fullNameC.text.trim(),
        username: _usernameC.text.trim(),
        password: _passwordC.text,
        whatsapp: whatsapp,
        countryCode: _selectedCountry.dialCode,
        termsAccepted: true,
        referralPhone: referralPhone,
      );

      if (!mounted) {
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: _fullNameC.text.trim(),
            username: _usernameC.text.trim(),
            password: _passwordC.text,
            whatsapp: whatsapp,
            countryCode: _selectedCountry.dialCode,
            termsAccepted: true,
            referralPhone: referralPhone,
            pendingRegistrationId: otp.pendingRegistrationId,
            purpose: 'register',
            initialDebugOtpCode: otp.debugOtpCode,
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
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_registrationEnabled) {
      return _buildDisabledState();
    }

    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildBackgroundDecor(),
          SafeArea(
            child: ResponsiveScaffoldContainer(
              maxWidth: 1100,
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const ShwakelLogo(size: 80, framed: true),
                      const SizedBox(height: 24),
                      Text(
                        l.tr('screens_register_screen.009'),
                        style: AppTheme.h1.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.tr('screens_register_screen.039'),
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _buildFormCard(),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/login'),
                        child: Text(l.tr('screens_register_screen.040')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            l.tr('screens_register_screen.011'),
            _fullNameC,
            Icons.badge_rounded,
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_register_screen.012'),
            _usernameC,
            Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<CountryOption>(
            initialValue: _selectedCountry,
            decoration: InputDecoration(
              labelText: l.tr('screens_register_screen.016'),
              prefixIcon: const Icon(Icons.public_rounded),
            ),
            items: PhoneNumberService.countries
                .map(
                  (country) => DropdownMenuItem(
                    value: country,
                    child: Text('${country.name} (+${country.dialCode})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCountry = value);
              }
            },
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_register_screen.017'),
            _whatsappC,
            Icons.chat_rounded,
            type: TextInputType.phone,
            prefix: '+${_selectedCountry.dialCode} ',
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_register_screen.020'),
            _passwordC,
            Icons.lock_rounded,
            obscure: true,
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_register_screen.021'),
            _confirmPassC,
            Icons.lock_reset_rounded,
            obscure: true,
          ),
          const SizedBox(height: 12),
          Text(
            l.tr('screens_register_screen.041'),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
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
          const SizedBox(height: 12),
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(22),
            shadowLevel: ShwakelShadowLevel.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رقم الإحالة', style: AppTheme.bodyBold),
                const SizedBox(height: 4),
                Text(
                  'اختياري: أدخله فقط إذا كان لديك رقم محيل.',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  l.tr('screens_register_screen.018'),
                  _referralPhoneC,
                  Icons.link_rounded,
                  type: TextInputType.phone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: l.tr('screens_register_screen.023'),
            onPressed: _register,
            isLoading: _isLoading,
            icon: Icons.sms_rounded,
            iconAtEnd: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecor() {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -50,
          left: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
          ),
        ),
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
                    SupportContactCard(
                      phoneNumber: _supportWhatsapp!,
                      title: l.tr('screens_register_screen.028'),
                      message: l.tr('screens_register_screen.045'),
                    ),
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

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool obscure = false,
    bool readOnly = false,
    VoidCallback? onTap,
    String? prefix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        prefixText: prefix,
      ),
    );
  }
}
