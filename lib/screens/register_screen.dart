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
  String? _supportWhatsapp;

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

  Future<void> _next() async {
    final error = _validateStep(_currentStep);
    if (error != null) {
      await AppAlertService.showError(
        context,
        title: 'تحقق من البيانات',
        message: error,
      );
      return;
    }

    if (_currentStep < 2) {
      setState(() => _currentStep++);
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    await _register();
  }

  Future<void> _prev() async {
    if (_currentStep <= 0) {
      return;
    }

    setState(() => _currentStep--);
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  String? _validateStep(int step) {
    return switch (step) {
      0 => _validatePersonalStep(),
      1 => _validateContactStep(),
      2 => _validateSecurityStep(),
      _ => null,
    };
  }

  String? _validatePersonalStep() {
    final fullName = _fullNameC.text.trim();
    final username = _usernameC.text.trim();
    final nationalId = _digitsOnly(_nationalIdC.text);
    final birthDate = _birthDateC.text.trim();

    if (fullName.isEmpty || fullName.length < 4) {
      return 'أدخل الاسم الكامل بشكل صحيح.';
    }
    if (username.isEmpty) {
      return 'اسم المستخدم مطلوب.';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'اسم المستخدم يجب أن يكون بالإنجليزية ويحتوي على أحرف أو أرقام فقط مع السماح بـ . و _ و -';
    }
    if (nationalId.length < 6 || nationalId.length > 16) {
      return 'رقم الهوية غير صالح.';
    }
    if (birthDate.isEmpty) {
      return 'اختر تاريخ الميلاد.';
    }

    final parsedDate = DateTime.tryParse(birthDate);
    if (parsedDate == null || parsedDate.isAfter(DateTime.now())) {
      return 'تاريخ الميلاد غير صالح.';
    }

    return null;
  }

  String? _validateContactStep() {
    final whatsapp = PhoneNumberService.normalize(
      input: _whatsappC.text,
      defaultDialCode: _selectedCountry.dialCode,
    );
    if (whatsapp.isEmpty ||
        whatsapp.length < _selectedCountry.dialCode.length + 8) {
      return 'أدخل رقم واتساب صحيحًا.';
    }

    if (_referralPhoneC.text.trim().isNotEmpty) {
      final referral = PhoneNumberService.normalize(
        input: _referralPhoneC.text,
        defaultDialCode: _selectedCountry.dialCode,
      );
      if (referral.length < _selectedCountry.dialCode.length + 8) {
        return 'رقم المحيل أو الموصي غير صالح.';
      }
    }

    return null;
  }

  String? _validateSecurityStep() {
    final password = _passwordC.text;
    final confirm = _confirmPassC.text;

    if (password.trim().isEmpty) {
      return 'كلمة المرور مطلوبة.';
    }
    if (password.length < 8) {
      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.';
    }
    if (!_passwordLetterPattern.hasMatch(password)) {
      return 'كلمة المرور يجب أن تحتوي على حرف واحد على الأقل.';
    }
    if (!_passwordSymbolPattern.hasMatch(password)) {
      return 'كلمة المرور يجب أن تحتوي على رمز واحد على الأقل.';
    }
    if (confirm.trim().isEmpty) {
      return 'تأكيد كلمة المرور مطلوب.';
    }
    if (password.length < 6) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.';
    }
    if (password != confirm) {
      return 'تأكيد كلمة المرور غير مطابق.';
    }
    if (!_termsAccepted) {
      return 'يجب الموافقة على الشروط والأحكام لإكمال التسجيل.';
    }

    return null;
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

  Future<void> _register() async {
    final localError =
        _validatePersonalStep() ??
        _validateContactStep() ??
        _validateSecurityStep();
    if (localError != null) {
      await AppAlertService.showError(
        context,
        title: 'تحقق من البيانات',
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
        nationalId: _digitsOnly(_nationalIdC.text),
        birthDate: _birthDateC.text.trim(),
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
            nationalId: _digitsOnly(_nationalIdC.text),
            birthDate: _birthDateC.text.trim(),
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
        title: 'تعذر بدء التسجيل',
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
                        'إنشاء حساب جديد',
                        style: AppTheme.h1.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'أكمل البيانات خطوة بخطوة، ولن تنتقل للخطوة التالية قبل اكتمال الحقول المطلوبة.',
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildStepperHeader(),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 540,
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
                      const SizedBox(height: 24),
                      _buildNavigationButtons(),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/login'),
                        child: const Text('لديك حساب بالفعل؟ تسجيل الدخول'),
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

  Widget _buildStepPersonal() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('البيانات الأساسية', style: AppTheme.h3),
          const SizedBox(height: 24),
          _field('الاسم الكامل', _fullNameC, Icons.badge_rounded),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بيانات التواصل', style: AppTheme.h3),
          const SizedBox(height: 24),
          DropdownButtonFormField<CountryOption>(
            initialValue: _selectedCountry,
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
            'رقم المحيل أو الموصي',
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 12),
          Text(
            'يجب أن تحتوي كلمة المرور على 8 أحرف على الأقل، مع حرف واحد ورمز واحد على الأقل.',
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const Spacer(),
          CheckboxListTile(
            value: _termsAccepted,
            onChanged: (value) {
              setState(() => _termsAccepted = value ?? false);
            },
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
              label: _currentStep == 2 ? 'إرسال رمز التحقق' : 'التالي',
              onPressed: _next,
              isLoading: _isLoading,
              icon: _currentStep == 2
                  ? Icons.sms_rounded
                  : Icons.arrow_back_rounded,
              iconAtEnd: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperHeader() {
    final labels = ['البيانات', 'التواصل', 'الحماية'];
    return SizedBox(
      width: 460,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (index) {
          final isDone = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Row(
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isCurrent
                        ? AppTheme.primary
                        : isDone
                        ? AppTheme.success
                        : AppTheme.border,
                    child: isDone
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isCurrent
                                  ? Colors.white
                                  : AppTheme.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(labels[index], style: AppTheme.caption),
                ],
              ),
              if (index < 2)
                Container(
                  width: 56,
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
                    'التسجيل متوقف حاليًا',
                    textAlign: TextAlign.center,
                    style: AppTheme.h2,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'يمكنك التواصل مع الإدارة لطلب إنشاء حساب جديد أو تفعيل التسجيل من جديد.',
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
                      title: 'رقم الإدارة',
                      message:
                          'راسل الإدارة مباشرة عبر واتساب لطلب فتح التسجيل أو إنشاء حساب لك.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  ShwakelButton(
                    label: 'العودة إلى تسجيل الدخول',
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(
        () => _birthDateC.text = picked.toIso8601String().split('T').first,
      );
    }
  }
}
