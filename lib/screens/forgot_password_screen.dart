import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/support_contact_card.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final RegExp _usernamePattern = RegExp(
    r'^[A-Za-z\u0600-\u06FF0-9._@+\-\s]+$',
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
      setState(() {
        _supportWhatsapp = supportWhatsapp.isEmpty ? null : supportWhatsapp;
      });
    } catch (_) {}
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _validateUsernameInput(String username) {
    final l = context.loc;
    if (username.isEmpty) {
      return l.text(
        'يرجى إدخال اسم المستخدم أو رقم الجوال.',
        'Please enter the username or phone number.',
      );
    }
    if (username.length < 3 || username.length > 64) {
      return l.text(
        'اسم المستخدم يجب أن يكون بين 3 و64 خانة.',
        'Username must be between 3 and 64 characters.',
      );
    }
    if (!_usernamePattern.hasMatch(username)) {
      return l.text(
        'اسم المستخدم يحتوي على رموز غير مدعومة.',
        'Username contains unsupported characters.',
      );
    }
    return null;
  }

  String? _validateLookupInputs({
    required String nationalId,
    required String birthDate,
    required String normalizedWhatsapp,
  }) {
    final l = context.loc;
    if (nationalId.isEmpty || birthDate.isEmpty || normalizedWhatsapp.isEmpty) {
      return l.text(
        'يرجى تعبئة الهوية وتاريخ الميلاد ورقم الجوال.',
        'Please fill in the national ID, birth date, and phone number.',
      );
    }
    if (nationalId.length > 32 || !_nationalIdPattern.hasMatch(nationalId)) {
      return l.text(
        'رقم الهوية يجب أن يحتوي على أرقام أو شرطة فقط.',
        'National ID must contain only digits or hyphens.',
      );
    }
    if (!_datePattern.hasMatch(birthDate)) {
      return l.text(
        'يرجى إدخال تاريخ الميلاد بصيغة YYYY-MM-DD.',
        'Birth date must be in YYYY-MM-DD format.',
      );
    }
    final parsedBirthDate = DateTime.tryParse(birthDate);
    if (parsedBirthDate == null || _formatDate(parsedBirthDate) != birthDate) {
      return l.text('تاريخ الميلاد غير صالح.', 'Invalid birth date.');
    }
    if (normalizedWhatsapp.length < 6 || normalizedWhatsapp.length > 15) {
      return l.text('رقم الجوال غير صالح.', 'Invalid phone number.');
    }
    return null;
  }

  String? _validateResetInputs({
    required String username,
    required String otpCode,
    required String newPassword,
  }) {
    final l = context.loc;
    final usernameMessage = _validateUsernameInput(username);
    if (usernameMessage != null) {
      return usernameMessage;
    }
    if (otpCode.trim().length < 4 || otpCode.trim().length > 10) {
      return l.text('رمز التحقق غير صالح.', 'Invalid verification code.');
    }
    if (newPassword.length < 8 || newPassword.length > 64) {
      return l.text(
        'كلمة المرور يجب أن تكون بين 8 و64 خانة.',
        'Password must be between 8 and 64 characters.',
      );
    }
    if (!_passwordLetterPattern.hasMatch(newPassword) ||
        !_passwordDigitPattern.hasMatch(newPassword)) {
      return l.text(
        'كلمة المرور يجب أن تحتوي على أحرف وأرقام معًا.',
        'Password must contain both letters and numbers.',
      );
    }
    return null;
  }

  Future<void> _pickBirthDate() async {
    final l = context.loc;
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
      helpText: l.text('اختر تاريخ الميلاد', 'Select birth date'),
      cancelText: l.text('إلغاء', 'Cancel'),
      confirmText: l.text('اعتماد', 'Confirm'),
    );
    if (pickedDate == null) {
      return;
    }
    _birthDateController.text = _formatDate(pickedDate);
  }

  Future<void> _requestOtp() async {
    final l = context.loc;
    final username = _usernameController.text.trim();
    final validationMessage = _validateUsernameInput(username);
    if (validationMessage != null) {
      await AppAlertService.showError(
        context,
        title: l.text('خطأ', 'Error'),
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
        title: l.text('تم الإرسال', 'Sent successfully'),
        message: l.text(
          'تم إرسال رمز الاستعادة إلى واتساب الحساب. لن تتغير كلمة المرور بدون الرمز.',
          'A recovery code has been sent to the account WhatsApp. The password will not change without the code.',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.text('خطأ', 'Error'),
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
    final l = context.loc;
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
        title: l.text('خطأ', 'Error'),
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
        title: l.text('تم العثور على الحساب', 'Account found'),
        message: l.text(
          'تمت المطابقة. اسم المستخدم: ${_usernameController.text}',
          'Match found. Username: ${_usernameController.text}',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.text('خطأ', 'Error'),
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
    final l = context.loc;
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
        title: l.text('خطأ', 'Error'),
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
        title: l.text('نجاح', 'Success'),
        message: l.text(
          'تمت إعادة تعيين كلمة المرور. يمكنك تسجيل الدخول الآن.',
          'Your password has been reset. You can log in now.',
        ),
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
        title: l.text('خطأ', 'Error'),
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
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.text('استعادة كلمة المرور', 'Reset Password'))),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          ResponsiveScaffoldContainer(
            maxWidth: 860,
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
            child: Column(
              children: [
                _buildHeroCard(),
                const SizedBox(height: 18),
                ShwakelCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        l.text('استعادة كلمة المرور', 'Reset Password'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.text(
                          'ابحث عن الحساب أولًا، ثم اطلب رمز الاستعادة، وبعدها عيّن كلمة مرور جديدة.',
                          'Find the account first, then request the recovery code, and finally set a new password.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          height: 1.7,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if ((_supportWhatsapp ?? '').isNotEmpty) ...[
                        SupportContactCard(
                          phoneNumber: _supportWhatsapp!,
                          title: l.text('تحتاج مساعدة؟', 'Need help?'),
                          message: l.text(
                            'إذا لم تتطابق البيانات أو فقدت الرقم المرتبط، تواصل مع الدعم من هذا الرقم.',
                            'If your data does not match or you lost access to the linked number, contact support using this number.',
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              l.text(
                                'البحث عن الحساب عبر الهوية',
                                'Find account by identity',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nationalIdController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l.text('رقم الهوية', 'National ID'),
                                prefixIcon: const Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _birthDateController,
                              readOnly: true,
                              onTap: _pickBirthDate,
                              decoration: InputDecoration(
                                labelText: l.text('تاريخ الميلاد', 'Birth date'),
                                helperText: l.text(
                                  'مثال: 1995-04-21',
                                  'Example: 1995-04-21',
                                ),
                                prefixIcon: const Icon(Icons.cake_outlined),
                                suffixIcon: IconButton(
                                  onPressed: _pickBirthDate,
                                  icon: const Icon(
                                    Icons.calendar_month_rounded,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<CountryOption>(
                              initialValue: _selectedCountry,
                              decoration: InputDecoration(
                                labelText: l.text('اختر الدولة', 'Select country'),
                                prefixIcon: const Icon(Icons.public_rounded),
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
                                labelText: l.text('رقم الجوال', 'Phone number'),
                                prefixIcon: const Icon(Icons.phone_rounded),
                                prefixText: '+${_selectedCountry.dialCode}  ',
                              ),
                            ),
                            const SizedBox(height: 12),
                            ShwakelButton(
                              label: _isLookingUp
                                  ? l.text('جارٍ البحث...', 'Searching...')
                                  : l.text('بحث عن الحساب', 'Find account'),
                              icon: Icons.search_rounded,
                              onPressed: _isLookingUp ? null : _lookupAccount,
                              isLoading: _isLookingUp,
                              width: double.infinity,
                              isSecondary: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'اسم المستخدم أو رقم الجوال',
                            'Username or phone number',
                          ),
                          helperText: l.text(
                            'يمكن استخدام أي منهما.',
                            'You can use either one.',
                          ),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ShwakelButton(
                        label: _isRequesting
                            ? l.text('جارٍ الإرسال...', 'Sending...')
                            : l.text('إرسال الرمز', 'Send code'),
                        icon: Icons.mark_chat_read_rounded,
                        onPressed: _isRequesting ? null : _requestOtp,
                        isLoading: _isRequesting,
                        width: double.infinity,
                      ),
                      if ((_debugOtpCode ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          l.text(
                            'رمز تجريبي: $_debugOtpCode',
                            'Debug code: $_debugOtpCode',
                          ),
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TextField(
                        controller: _otpController,
                        decoration: InputDecoration(
                          labelText: l.text('رمز التحقق', 'Verification code'),
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'كلمة المرور الجديدة',
                            'New password',
                          ),
                          prefixIcon: const Icon(Icons.password_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ShwakelButton(
                        label: _isResetting
                            ? l.text('جارٍ التحديث...', 'Updating...')
                            : l.text(
                                'حفظ كلمة المرور الجديدة',
                                'Save new password',
                              ),
                        icon: Icons.lock_reset_rounded,
                        onPressed: _isResetting ? null : _resetPassword,
                        isLoading: _isResetting,
                        width: double.infinity,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.text('استعادة الحساب بشكل آمن', 'Secure account recovery'),
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            l.text(
              'ابحث عن الحساب، اطلب الرمز، ثم عيّن كلمة مرور جديدة بخطوات واضحة وسريعة.',
              'Find the account, request the code, then set a new password through clear and quick steps.',
            ),
            style: AppTheme.bodyAction.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
