import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import 'otp_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  final _fullNameC = TextEditingController();
  final _usernameC = TextEditingController();
  final _passwordC = TextEditingController();
  final _confirmPassC = TextEditingController();
  final _nationalIdC = TextEditingController();
  final _birthDateC = TextEditingController();
  final _whatsappC = TextEditingController();
  final _referralPhoneC = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _registrationEnabled = true;
  bool _termsAccepted = false;
  CountryOption _selectedCountry = PhoneNumberService.countries.first;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fullNameC.dispose();
    _usernameC.dispose();
    _passwordC.dispose();
    _confirmPassC.dispose();
    _nationalIdC.dispose();
    _birthDateC.dispose();
    _whatsappC.dispose();
    _referralPhoneC.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _apiService.getAuthSettings();
      if (mounted) {
        setState(() {
          _registrationEnabled = settings['registrationEnabled'] == true;
        });
      }
    } catch (_) {}
  }

  void _next() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    _register();
  }

  void _prev() {
    if (_currentStep <= 0) return;
    setState(() => _currentStep--);
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _register() async {
    if (!_termsAccepted) {
      AppAlertService.showError(
        context,
        message: 'يرجى الموافقة على الشروط والأحكام أولًا.',
      );
      return;
    }

    if (_passwordC.text != _confirmPassC.text) {
      AppAlertService.showError(
        context,
        message: 'تأكيد كلمة المرور غير مطابق.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final whatsapp = PhoneNumberService.normalize(
        input: _whatsappC.text,
        defaultDialCode: _selectedCountry.dialCode,
      );
      final otp = await _authService.startRegistration(
        fullName: _fullNameC.text,
        username: _usernameC.text,
        password: _passwordC.text,
        whatsapp: whatsapp,
        countryCode: _selectedCountry.dialCode,
        nationalId: _nationalIdC.text,
        birthDate: _birthDateC.text,
        termsAccepted: true,
        referralPhone: _referralPhoneC.text.isEmpty ? null : _referralPhoneC.text,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: _fullNameC.text,
            username: _usernameC.text,
            password: _passwordC.text,
            whatsapp: whatsapp,
            countryCode: _selectedCountry.dialCode,
            nationalId: _nationalIdC.text,
            birthDate: _birthDateC.text,
            termsAccepted: true,
            referralPhone: _referralPhoneC.text.isEmpty
                ? null
                : _referralPhoneC.text,
            pendingRegistrationId: otp.pendingRegistrationId,
            purpose: 'register',
            initialDebugOtpCode: otp.debugOtpCode,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_registrationEnabled) return _buildDisabledState();

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
                      const SizedBox(height: 32),
                      _buildStepperHeader(),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 520,
                        width: 500,
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildStepPersonal(),
                            _buildStepContact(),
                            _buildStepSecurity(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildNavigationButtons(),
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

  Widget _buildStepPersonal() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text('المعلومات الشخصية', style: AppTheme.h3),
          const SizedBox(height: 24),
          _field('الاسم الرباعي', _fullNameC, Icons.badge_rounded),
          const SizedBox(height: 16),
          _field(
            'اسم المستخدم بالإنجليزية',
            _usernameC,
            Icons.alternate_email_rounded,
          ),
          const SizedBox(height: 16),
          _field(
            'رقم الهوية',
            _nationalIdC,
            Icons.credit_card_rounded,
            type: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _field(
            'تاريخ الميلاد',
            _birthDateC,
            Icons.cake_rounded,
            readOnly: true,
            onTap: _pickDate,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContact() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text('بيانات التواصل والتوصية', style: AppTheme.h3),
          const SizedBox(height: 24),
          DropdownButtonFormField<CountryOption>(
            value: _selectedCountry,
            decoration: const InputDecoration(
              labelText: 'الدولة',
              prefixIcon: Icon(Icons.public_rounded),
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
            'رقم الواتساب',
            _whatsappC,
            Icons.chat_rounded,
            type: TextInputType.phone,
            prefix: '+${_selectedCountry.dialCode} ',
          ),
          const SizedBox(height: 16),
          _field(
            'رقم هاتف المحيل أو الموصي (اختياري)',
            _referralPhoneC,
            Icons.link_rounded,
            type: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget _buildStepSecurity() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text('تأمين الحساب', style: AppTheme.h3),
          const SizedBox(height: 24),
          _field('كلمة المرور', _passwordC, Icons.lock_rounded, obscure: true),
          const SizedBox(height: 16),
          _field(
            'تأكيد كلمة المرور',
            _confirmPassC,
            Icons.lock_reset_rounded,
            obscure: true,
          ),
          const Spacer(),
          CheckboxListTile(
            value: _termsAccepted,
            onChanged: (value) => setState(() => _termsAccepted = value ?? false),
            title: Text(
              'أوافق على الشروط والسياسات والرسوم المعروضة.',
              style: AppTheme.caption.copyWith(fontWeight: FontWeight.bold),
            ),
            contentPadding: EdgeInsets.zero,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return SizedBox(
      width: 500,
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: ShwakelButton(
                label: 'السابق',
                isSecondary: true,
                onPressed: _prev,
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 16),
          Expanded(
            child: ShwakelButton(
              label: _currentStep == 2 ? 'إنشاء الحساب' : 'التالي',
              onPressed: _next,
              isLoading: _isLoading,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperHeader() {
    return SizedBox(
      width: 400,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (index) {
          final isDone = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isCurrent
                    ? AppTheme.primary
                    : (isDone ? AppTheme.success : AppTheme.border),
                child: isDone
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrent ? Colors.white : AppTheme.textTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              if (index < 2)
                Container(
                  width: 60,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: isDone ? AppTheme.success : AppTheme.border,
                ),
            ],
          );
        }),
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
              color: AppTheme.primary.withOpacity(0.05),
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
              color: AppTheme.accent.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisabledState() {
    return Scaffold(
      body: Center(
        child: ShwakelCard(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_clock_rounded,
                size: 64,
                color: AppTheme.warning,
              ),
              const SizedBox(height: 24),
              Text('التسجيل غير متاح حاليًا', style: AppTheme.h2),
              Text(
                'يرجى التواصل مع الإدارة إذا كنت بحاجة إلى إنشاء حساب جديد.',
                style: AppTheme.caption,
              ),
              const SizedBox(height: 32),
              ShwakelButton(
                label: 'العودة إلى تسجيل الدخول',
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              ),
            ],
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _birthDateC.text = picked.toString().split(' ')[0]);
    }
  }
}
