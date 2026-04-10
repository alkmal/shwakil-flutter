import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import 'otp_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final RegExp _usernamePattern = RegExp(
    r'^[\p{L}\p{M}\p{N}._@+\-\s]+$',
    unicode: true,
  );

  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final TextEditingController _usernameController = TextEditingController(
    text: kDebugMode ? 'debug_admin' : '',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: kDebugMode ? '1234' : '',
  );
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _registrationEnabled = true;
  String? _supportWhatsapp;

  @override
  void initState() {
    super.initState();
    _loadAuthSettings();
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthSettings() async {
    try {
      final authSettings = await _apiService.getAuthSettings();
      final contact = await ContactInfoService.getContactInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _registrationEnabled = authSettings['registrationEnabled'] == true;
        _supportWhatsapp = ContactInfoService.supportWhatsapp(contact);
      });
    } catch (_) {}
  }

  String? _validateLoginInputs({
    required String username,
    required String password,
  }) {
    final l = context.loc;
    if (username.isEmpty || password.isEmpty) {
      return l.tr('screens_login_screen.009');
    }
    if (username.length < 3 || username.length > 64) {
      return l.tr('screens_login_screen.010');
    }
    if (!_usernamePattern.hasMatch(username)) {
      return l.tr('screens_login_screen.011');
    }
    if (password.length > 255) {
      return l.tr('screens_login_screen.001');
    }
    return null;
  }

  Future<void> _continueToOtp() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final validationMessage = _validateLoginInputs(
      username: username,
      password: password,
    );
    if (validationMessage != null) {
      await _showMessage(validationMessage, isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final isTrustedDevice = await _isTrustedDeviceForUsername(username);
      if (isTrustedDevice) {
        await _authService.login(
          username: username,
          password: password,
          otpCode: '',
        );
        if (!mounted) {
          return;
        }
        await _finishLogin(username);
        return;
      }

      final otpResult = await _authService.requestOtp(
        purpose: 'login',
        username: username,
        password: password,
      );
      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
      if (otpResult.otpRequired == false) {
        await _authService.login(
          username: username,
          password: password,
          otpCode: '',
        );
        if (!mounted) {
          return;
        }
        await _finishLogin(username);
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: '',
            username: username,
            password: password,
            initialDebugOtpCode: otpResult.debugOtpCode,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await _showMessage(
        ErrorMessageService.sanitize(error),
        isError: true,
        username: username,
      );
    }
  }

  void _submitFromUsername() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty) {
      return;
    }
    if (password.isEmpty) {
      _passwordFocusNode.requestFocus();
      return;
    }
    _continueToOtp();
  }

  void _submitFromPassword() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      return;
    }
    _continueToOtp();
  }

  Future<void> _finishLogin(String username) async {
    await LocalSecurityService.clearRelockRequirement();
    await LocalSecurityService.skipNextUnlock();
    await RealtimeNotificationService.start();
    final localSecurityReady = await _setupLocalSecurityIfNeeded(username);
    if (!mounted) {
      return;
    }
    if (!localSecurityReady) {
      await _authService.logout();
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      return;
    }
    setState(() => _isLoading = false);
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  Future<bool> _isTrustedDeviceForUsername(String username) async {
    final trustedDevice = await LocalSecurityService.isTrustedDevice();
    final trustedUsername =
        (await LocalSecurityService.trustedUsername())?.trim().toLowerCase() ??
        '';
    return trustedDevice && trustedUsername == username.trim().toLowerCase();
  }

  Future<bool> _setupLocalSecurityIfNeeded(String username) async {
    final canUseBiometrics = await LocalSecurityService.canUseBiometrics();
    final biometricEnabled = await LocalSecurityService.isBiometricEnabled();
    if (!mounted) {
      return false;
    }
    if (biometricEnabled && !canUseBiometrics) {
      await LocalSecurityService.setBiometricEnabled(false);
    }
    await LocalSecurityService.markDeviceTrusted(username.trim().toLowerCase());
    return true;
  }

  Future<void> _showMessage(
    String text, {
    bool isError = false,
    String? username,
  }) {
    final l = context.loc;
    final message = isError && username != null && username.trim().isNotEmpty
        ? l.tr(
            'screens_login_screen.012',
            params: {'username': username.trim(), 'message': text},
          )
        : text;
    return isError
        ? AppAlertService.showError(
            context,
            title: l.tr('screens_login_screen.002'),
            message: message,
            extraContext: {
              'username': username ?? _usernameController.text.trim(),
            },
          )
        : AppAlertService.showSuccess(
            context,
            title: l.tr('screens_login_screen.003'),
            message: message,
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              const Color(0xFFF3FAF8),
              AppTheme.primarySoft.withValues(alpha: 0.8),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ResponsiveScaffoldContainer(
            maxWidth: 520,
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _buildFormCard(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(AppTheme.spacingXl),
      shadowLevel: ShwakelShadowLevel.premium,
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: ShwakelLogo(size: 82, framed: true)),
          const SizedBox(height: 18),
          Text(
            l.tr('screens_login_screen.004'),
            style: AppTheme.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            l.tr('screens_login_screen.013'),
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          TextField(
            focusNode: _usernameFocusNode,
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submitFromUsername(),
            decoration: InputDecoration(
              labelText: l.tr('screens_login_screen.005'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            focusNode: _passwordFocusNode,
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitFromPassword(),
            decoration: InputDecoration(
              labelText: l.tr('screens_login_screen.006'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          ShwakelButton(
            label: l.tr('screens_login_screen.007'),
            isLoading: _isLoading,
            onPressed: _continueToOtp,
            icon: Icons.login_rounded,
            gradient: AppTheme.primaryGradient,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ShwakelButton(
              label: l.tr('screens_login_screen.008'),
              onPressed: () => Navigator.pushNamed(context, '/register'),
              isSecondary: true,
            ),
          ),
          if (!_registrationEnabled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_login_screen.014'),
                          style: AppTheme.bodyBold,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (_supportWhatsapp ?? '').isNotEmpty
                              ? l.tr(
                                  'screens_login_screen.015',
                                  params: {'whatsapp': _supportWhatsapp ?? ''},
                                )
                              : l.tr('screens_login_screen.016'),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
