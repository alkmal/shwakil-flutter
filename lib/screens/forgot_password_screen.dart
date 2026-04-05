import 'package:flutter/material.dart';
import '../services/index.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/support_contact_card.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final RegExp _usernamePattern = RegExp(
    r"^[A-Za-z\u0600-\u06FF0-9._@+\-\s]+$",
    unicode: true,
  );
  static final RegExp _nationalIdPattern = RegExp(r'^[0-9-]+$', unicode: true);
  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _passwordLetterPattern = RegExp(
    r'[A-Za-z\u0600-\u06FF]',
    unicode: true,
  );
  static final RegExp _passwordDigitPattern = RegExp(r'\d');
  final AuthService _authService = AuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  CountryOption _selectedCountry = PhoneNumberService.countries.first;
  bool _isRequesting = false;
  bool _isResetting = false;
  bool _isLookingUp = false;
  String? _debugOtpCode;
  String? _supportWhatsapp;
  @override
  void initState() {
    super.initState();
    _loadSupportContact();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nationalIdController.dispose();
    _birthDateController.dispose();
    _whatsappController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSupportContact() async {
    try {
      final contact = await ContactInfoService.getContactInfo();
      final supportWhatsapp = ContactInfoService.supportWhatsapp(contact);
      if (!mounted) {
        return;
      }
      setState(
        () =>
            _supportWhatsapp = supportWhatsapp.isEmpty ? null : supportWhatsapp,
      );
    } catch (_) {}
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _validateUsernameInput(String username) {
    if (username.isEmpty) {
      return 'يرجى إدخال اسم المستخدم أو رقم الجوال.';
    }
    if (username.length < 3 || username.length > 64) {
      return 'اسم المستخدم يجب أن يكون بين 3 و64 خانة.';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'اسم المستخدم يحتوي على رموز غير مدعومة.';
    }
    return null;
  }

  String? _validateLookupInputs({
    required String nationalId,
    required String birthDate,
    required String normalizedWhatsapp,
  }) {
    if (nationalId.isEmpty || birthDate.isEmpty || normalizedWhatsapp.isEmpty) {
      return 'يرجى تعبئة الهوية وتاريخ الميلاد ورقم الجوال.';
    }
    if (nationalId.length > 32 || !_nationalIdPattern.hasMatch(nationalId)) {
      return 'رقم الهوية يجب أن يحتوي على أرقام أو شرطة فقط.';
    }
    if (!_datePattern.hasMatch(birthDate)) {
      return 'يرجى إدخال تاريخ الميلاد بصيغة YYYY-MM-DD.';
    }
    final parsedBirthDate = DateTime.tryParse(birthDate);
    if (parsedBirthDate == null || _formatDate(parsedBirthDate) != birthDate) {
      return 'تاريخ الميلاد غير صالح.';
    }
    if (normalizedWhatsapp.length < 6 || normalizedWhatsapp.length > 15) {
      return 'رقم الجوال غير صالح.';
    }
    return null;
  }

  String? _validateResetInputs({
    required String username,
    required String otpCode,
    required String newPassword,
  }) {
    final usernameMessage = _validateUsernameInput(username);
    if (usernameMessage != null) {
      return usernameMessage;
    }
    if (otpCode.trim().length < 4 || otpCode.trim().length > 10) {
      return 'رمز التحقق غير صالح.';
    }
    if (newPassword.length < 8 || newPassword.length > 64) {
      return 'كلمة المرور يجب أن تكون بين 8 و64 خانة.';
    }
    if (!_passwordLetterPattern.hasMatch(newPassword) ||
        !_passwordDigitPattern.hasMatch(newPassword)) {
      return 'كلمة المرور يجب أن تحتوي على أحرف وأرقام معا.';
    }
    return null;
  }

  Future<void> _pickBirthDate() async {
    final initialDate =
        DateTime.tryParse(_birthDateController.text) ??
        DateTime(DateTime.now().year - 18, 1, 1);
    final firstDate = DateTime(1940, 1, 1);
    final lastDate = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(lastDate) ? lastDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'اختر تاريخ الميلاد',
      cancelText: 'إلغاء',
      confirmText: 'اعتماد',
    );
    if (pickedDate == null) {
      return;
    }
    _birthDateController.text = _formatDate(pickedDate);
  }

  Future<void> _requestOtp() async {
    final username = _usernameController.text.trim();
    final validationMessage = _validateUsernameInput(username);
    if (validationMessage != null) {
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: validationMessage,
        extraContext: {'username': username},
      );
      return;
    }
    setState(() => _isRequesting = true);
    try {
      final result = await _authService.requestPasswordResetOtp(
        username: username,
      );
      if (!mounted) {
        return;
      }
      setState(() => _debugOtpCode = result.debugOtpCode);
      await AppAlertService.showSuccess(
        context,
        title: 'تم الإرسال',
        message:
            'تم إرسال رمز الاستعادة إلى واتساب الحساب. لن تتغير كلمة المرور بدون الرمز.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: ErrorMessageService.sanitize(error),
        extraContext: {
          'username': _usernameController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _lookupAccount() async {
    final nationalId = _nationalIdController.text.trim();
    final birthDate = _birthDateController.text.trim();
    final normalizedWhatsapp = PhoneNumberService.normalize(
      input: _whatsappController.text,
      defaultDialCode: _selectedCountry.dialCode,
    );
    final validationMessage = _validateLookupInputs(
      nationalId: nationalId,
      birthDate: birthDate,
      normalizedWhatsapp: normalizedWhatsapp,
    );
    if (validationMessage != null) {
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: validationMessage,
        extraContext: {
          'username': _usernameController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
        },
      );
      return;
    }
    setState(() => _isLookingUp = true);
    try {
      final result = await _authService.lookupAccountByIdentity(
        nationalId: nationalId,
        birthDate: birthDate,
        whatsapp: normalizedWhatsapp,
        countryCode: _selectedCountry.dialCode,
      );
      final user = Map<String, dynamic>.from(result['user'] as Map);
      _usernameController.text = user['username']?.toString() ?? '';
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم العثور على الحساب',
        message: 'تمت المطابقة. اسم المستخدم: ${_usernameController.text}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: ErrorMessageService.sanitize(error),
        extraContext: {
          'username': _usernameController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isLookingUp = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final username = _usernameController.text.trim();
    final otpCode = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    final validationMessage = _validateResetInputs(
      username: username,
      otpCode: otpCode,
      newPassword: newPassword,
    );
    if (validationMessage != null) {
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: validationMessage,
        extraContext: {
          'username': username,
          'whatsapp': _whatsappController.text.trim(),
        },
      );
      return;
    }
    setState(() => _isResetting = true);
    try {
      await _authService.resetPassword(
        username: username,
        otpCode: otpCode,
        newPassword: newPassword,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'نجاح',
        message: 'تمت إعادة تعيين كلمة المرور. يمكنك تسجيل الدخول الآن.',
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'خطأ',
        message: ErrorMessageService.sanitize(error),
        extraContext: {
          'username': _usernameController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ResponsiveScaffoldContainer(
            maxWidth: 860,
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F0F172A),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'استعادة كلمة المرور',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ابحث عن الحساب أولًا، ثم اطلب رمز الاستعادة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      height: 1.7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if ((_supportWhatsapp ?? '').isNotEmpty) ...[
                    SupportContactCard(
                      phoneNumber: _supportWhatsapp!,
                      title: 'تحتاج مساعدة؟',
                      message:
                          'إذا لم تتطابق البيانات أو فقدت الرقم المرتبط، تواصل مع الدعم من هذا الرقم.',
                    ),
                    const SizedBox(height: 20),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'البحث عن الحساب عبر الهوية',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nationalIdController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهوية',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _birthDateController,
                          readOnly: true,
                          onTap: _pickBirthDate,
                          decoration: InputDecoration(
                            labelText: 'تاريخ الميلاد',
                            helperText: 'مثال: 1995-04-21',
                            prefixIcon: const Icon(Icons.cake_outlined),
                            suffixIcon: IconButton(
                              onPressed: _pickBirthDate,
                              icon: const Icon(Icons.calendar_month_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<CountryOption>(
                          initialValue: _selectedCountry,
                          decoration: const InputDecoration(
                            labelText: 'اختر الدولة',
                            prefixIcon: Icon(Icons.public_rounded),
                          ),
                          items: PhoneNumberService.countries
                              .map(
                                (country) => DropdownMenuItem<CountryOption>(
                                  value: country,
                                  child: Text(
                                    '${country.name} (+${country.dialCode})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => _selectedCountry = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _whatsappController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'رقم الجوال',
                            prefixIcon: const Icon(Icons.phone_rounded),
                            prefixText: '+${_selectedCountry.dialCode}  ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLookingUp ? null : _lookupAccount,
                            icon: _isLookingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search_rounded),
                            label: Text(
                              _isLookingUp ? 'جار البحث...' : 'بحث عن الحساب',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم أو رقم الجوال',
                      helperText: 'يمكن استخدام أي منهما.',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isRequesting ? null : _requestOtp,
                      child: Text(
                        _isRequesting ? 'جار الإرسال...' : 'إرسال الرمز',
                      ),
                    ),
                  ),
                  if ((_debugOtpCode ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'رمز تجريبي: $_debugOtpCode',
                      style: const TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                      labelText: 'رمز التحقق',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      prefixIcon: Icon(Icons.password_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isResetting ? null : _resetPassword,
                      child: Text(
                        _isResetting
                            ? 'جار التحديث...'
                            : 'حفظ كلمة المرور الجديدة',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
