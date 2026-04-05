import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    r"^[\p{L}\p{M}\p{N}._@+\-\s]+$",
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
      if (!mounted) return;
      setState(() {
        _registrationEnabled = authSettings['registrationEnabled'] == true;
      });
    } catch (_) {}
  }

  String? _validateLoginInputs({
    required String username,
    required String password,
  }) {
    if (username.isEmpty || password.isEmpty) {
      return 'يرجى إدخال اسم المستخدم وكلمة المرور.';
    }
    if (username.length < 3 || username.length > 64) {
      return 'اسم المستخدم يجب أن يكون بين 3 و64 حرفًا.';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'اسم المستخدم يحتوي على أحرف غير مسموح بها.';
    }
    if (password.length > 255) {
      return 'كلمة المرور طويلة جدًا.';
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
        if (!mounted) return;
        await _finishLogin(username);
        return;
      }

      final otpResult = await _authService.requestOtp(
        purpose: 'login',
        username: username,
        password: password,
      );
      if (!mounted) return;

      setState(() => _isLoading = false);
      if (otpResult.otpRequired == false) {
        await _authService.login(
          username: username,
          password: password,
          otpCode: '',
        );
        if (!mounted) return;
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
      if (!mounted) return;
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
    if (username.isEmpty) return;
    if (password.isEmpty) {
      _passwordFocusNode.requestFocus();
      return;
    }
    _continueToOtp();
  }

  void _submitFromPassword() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
    _continueToOtp();
  }

  Future<void> _finishLogin(String username) async {
    await LocalSecurityService.clearRelockRequirement();
    await LocalSecurityService.skipNextUnlock();
    await RealtimeNotificationService.start();
    final localSecurityReady = await _setupLocalSecurityIfNeeded(username);
    if (!mounted) return;
    if (!localSecurityReady) {
      await _authService.logout();
      if (!mounted) return;
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
    if (!mounted) return false;
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
    final message = isError && username != null && username.trim().isNotEmpty
        ? 'للمستخدم ${username.trim()}: $text'
        : text;
    return isError
        ? AppAlertService.showError(
            context,
            title: 'خطأ',
            message: message,
            extraContext: {
              'username': username ?? _usernameController.text.trim(),
            },
          )
        : AppAlertService.showSuccess(context, title: 'نجاح', message: message);
  }

  Future<void> _openAndroidDownload() async {
    final apkUri = Uri.base.resolve('downloads/app-release.apk');
    final opened = await launchUrl(
      apkUri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    if (!opened && mounted) {
      await AppAlertService.showInfo(
        context,
        title: 'التنزيل',
        message: 'تعذر فتح رابط التنزيل الآن. حاول مرة أخرى لاحقًا.',
      );
    }
  }

  Future<void> _showIosComingSoon() {
    return AppAlertService.showInfo(
      context,
      title: 'iOS قريبًا',
      message: 'نسخة iPhone وiPad ستتوفر لاحقًا.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFFEFFCF9), Color(0xFFF8FAFC)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -90,
              right: -70,
              child: _softOrb(AppTheme.primary.withValues(alpha: 0.10), 240),
            ),
            Positioned(
              bottom: -80,
              left: -50,
              child: _softOrb(AppTheme.accent.withValues(alpha: 0.08), 190),
            ),
            SafeArea(
              child: ResponsiveScaffoldContainer(
                maxWidth: 1080,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingLg,
                  vertical: AppTheme.spacingLg,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 920;
                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(child: _buildIntroPanel()),
                          const SizedBox(width: 36),
                          SizedBox(width: 430, child: _buildFormCard()),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          _buildIntroPanel(isCenter: true),
                          const SizedBox(height: 28),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _buildFormCard(),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _softOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildIntroPanel({bool isCenter = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCenter ? 0 : 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isCenter
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: isCenter ? Alignment.center : Alignment.centerRight,
            child: const ShwakelLogo(size: 94, framed: true),
          ),
          const SizedBox(height: 28),
          Text(
            'شواكل',
            textAlign: isCenter ? TextAlign.center : TextAlign.start,
            style: AppTheme.h1.copyWith(fontSize: 34),
          ),
          const SizedBox(height: 10),
          Text(
            'دخول سريع إلى حسابك',
            textAlign: isCenter ? TextAlign.center : TextAlign.start,
            style: AppTheme.h2.copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'أدخل بياناتك وابدأ مباشرة.',
            textAlign: isCenter ? TextAlign.center : TextAlign.start,
            style: AppTheme.bodyAction.copyWith(height: 1.5),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: isCenter ? WrapAlignment.center : WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: const [
              _LoginBadge(icon: Icons.lock_outline_rounded, label: 'دخول آمن'),
              _LoginBadge(icon: Icons.bolt_rounded, label: 'وصول سريع'),
              _LoginBadge(
                icon: Icons.qr_code_scanner_rounded,
                label: 'فحص البطاقات',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(AppTheme.spacingXl),
      shadowLevel: ShwakelShadowLevel.premium,
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تسجيل الدخول', style: AppTheme.h2, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'ادخل بيانات حسابك.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyAction.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 28),
          TextField(
            focusNode: _usernameFocusNode,
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submitFromUsername(),
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم أو الجوال',
              prefixIcon: Icon(Icons.person_outline_rounded),
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
              labelText: 'كلمة المرور',
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
          const SizedBox(height: 22),
          ShwakelButton(
            label: 'دخول',
            isLoading: _isLoading,
            onPressed: _continueToOtp,
            icon: Icons.login_rounded,
            gradient: AppTheme.primaryGradient,
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: _registrationEnabled
                ? 'إنشاء حساب جديد'
                : 'التسجيل متوقف حاليًا',
            onPressed: _registrationEnabled
                ? () => Navigator.pushNamed(context, '/register')
                : null,
            isSecondary: true,
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 22),
            Divider(color: AppTheme.border.withValues(alpha: 0.6)),
            const SizedBox(height: 18),
            _buildWebDownloadSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildWebDownloadSection() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      color: AppTheme.surfaceVariant,
      shadowLevel: ShwakelShadowLevel.none,
      withBorder: false,
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تحميل التطبيق', style: AppTheme.h3.copyWith(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'لتجربة أفضل ثبّت التطبيق على جهازك.',
            style: AppTheme.caption.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ShwakelButton(
                  label: 'Android',
                  icon: Icons.android_rounded,
                  onPressed: _openAndroidDownload,
                  height: 44,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ShwakelButton(
                  label: 'iOS',
                  icon: Icons.apple_rounded,
                  onPressed: _showIosComingSoon,
                  isSecondary: true,
                  height: 44,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginBadge extends StatelessWidget {
  const _LoginBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
