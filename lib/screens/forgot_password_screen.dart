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
      return l.tr('screens_forgot_password_screen.030');
    }
    if (username.length < 3 || username.length > 64) {
      return l.tr('screens_forgot_password_screen.031');
    }
    if (!_usernamePattern.hasMatch(username)) {
      return l.tr('screens_forgot_password_screen.032');
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
      return l.tr('screens_forgot_password_screen.033');
    }
    if (nationalId.length > 32 || !_nationalIdPattern.hasMatch(nationalId)) {
      return l.tr('screens_forgot_password_screen.034');
    }
    if (!_datePattern.hasMatch(birthDate)) {
      return l.tr('screens_forgot_password_screen.035');
    }
    final parsedBirthDate = DateTime.tryParse(birthDate);
    if (parsedBirthDate == null || _formatDate(parsedBirthDate) != birthDate) {
      return l.tr('screens_forgot_password_screen.001');
    }
    if (normalizedWhatsapp.length < 6 || normalizedWhatsapp.length > 15) {
      return l.tr('screens_forgot_password_screen.002');
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
      return l.tr('screens_forgot_password_screen.003');
    }
    if (newPassword.length < 8 || newPassword.length > 64) {
      return l.tr('screens_forgot_password_screen.036');
    }
    if (!_passwordLetterPattern.hasMatch(newPassword) ||
        !_passwordDigitPattern.hasMatch(newPassword)) {
      return l.tr('screens_forgot_password_screen.037');
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
      helpText: l.tr('screens_forgot_password_screen.004'),
      cancelText: l.tr('screens_forgot_password_screen.005'),
      confirmText: l.tr('screens_forgot_password_screen.006'),
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
        title: l.tr('screens_forgot_password_screen.007'),
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
        title: l.tr('screens_forgot_password_screen.008'),
        message: l.tr('screens_forgot_password_screen.038'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_forgot_password_screen.009'),
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
        title: l.tr('screens_forgot_password_screen.010'),
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
        title: l.tr('screens_forgot_password_screen.011'),
        message: l.tr(
          'screens_forgot_password_screen.039',
          params: {'username': _usernameController.text},
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_forgot_password_screen.012'),
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
        title: l.tr('screens_forgot_password_screen.013'),
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
        title: l.tr('screens_forgot_password_screen.014'),
        message: l.tr('screens_forgot_password_screen.040'),
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
        title: l.tr('screens_forgot_password_screen.015'),
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
      appBar: AppBar(title: Text(l.tr('screens_forgot_password_screen.016'))),
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
                        l.tr('screens_forgot_password_screen.017'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.tr('screens_forgot_password_screen.041'),
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
                          title: l.tr('screens_forgot_password_screen.018'),
                          message: l.tr('screens_forgot_password_screen.042'),
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
                              l.tr('screens_forgot_password_screen.043'),
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
                                labelText: l.tr(
                                  'screens_forgot_password_screen.019',
                                ),
                                prefixIcon: const Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _birthDateController,
                              readOnly: true,
                              onTap: _pickBirthDate,
                              decoration: InputDecoration(
                                labelText: l.tr(
                                  'screens_forgot_password_screen.020',
                                ),
                                helperText: l.tr(
                                  'screens_forgot_password_screen.044',
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
                                labelText: l.tr(
                                  'screens_forgot_password_screen.021',
                                ),
                                prefixIcon: const Icon(Icons.public_rounded),
                              ),
                              items: PhoneNumberService.countries
                                  .map(
                                    (
                                      country,
                                    ) => DropdownMenuItem<CountryOption>(
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
                                labelText: l.tr(
                                  'screens_forgot_password_screen.022',
                                ),
                                prefixIcon: const Icon(Icons.phone_rounded),
                                prefixText: '+${_selectedCountry.dialCode}  ',
                              ),
                            ),
                            const SizedBox(height: 12),
                            ShwakelButton(
                              label: _isLookingUp
                                  ? l.tr('screens_forgot_password_screen.023')
                                  : l.tr('screens_forgot_password_screen.024'),
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
                          labelText: l.tr('screens_forgot_password_screen.045'),
                          helperText: l.tr(
                            'screens_forgot_password_screen.046',
                          ),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ShwakelButton(
                        label: _isRequesting
                            ? l.tr('screens_forgot_password_screen.025')
                            : l.tr('screens_forgot_password_screen.026'),
                        icon: Icons.mark_chat_read_rounded,
                        onPressed: _isRequesting ? null : _requestOtp,
                        isLoading: _isRequesting,
                        width: double.infinity,
                      ),
                      if ((_debugOtpCode ?? '').isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          l.tr(
                            'screens_forgot_password_screen.047',
                            params: {'code': _debugOtpCode ?? ''},
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
                          labelText: l.tr('screens_forgot_password_screen.027'),
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l.tr('screens_forgot_password_screen.048'),
                          prefixIcon: const Icon(Icons.password_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ShwakelButton(
                        label: _isResetting
                            ? l.tr('screens_forgot_password_screen.028')
                            : l.tr('screens_forgot_password_screen.049'),
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
            l.tr('screens_forgot_password_screen.029'),
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_forgot_password_screen.050'),
            style: AppTheme.bodyAction.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
