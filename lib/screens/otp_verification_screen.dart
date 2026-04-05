import 'package:flutter/material.dart';
import 'dart:async';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.fullName,
    required this.username,
    required this.password,
    this.termsAccepted = false,
    this.whatsapp,
    this.countryCode,
    this.nationalId,
    this.birthDate,
    this.referralPhone,
    this.pendingRegistrationId,
    this.purpose = 'login',
    this.initialDebugOtpCode,
  });
  final String fullName, username, password;
  final bool termsAccepted;
  final String? whatsapp,
      countryCode,
      nationalId,
      birthDate,
      referralPhone,
      pendingRegistrationId;
  final String purpose;
  final String? initialDebugOtpCode;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpC = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isResending = false;
  String? _debugCode;
  int _cooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _debugCode = widget.initialDebugOtpCode;
    _startTimer();
  }

  @override
  void dispose() {
    _otpC.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 0) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _verify() async {
    if (_otpC.text.length < 4) return;
    setState(() => _isLoading = true);
    try {
      if (widget.purpose == 'register') {
        await _authService.register(
          fullName: widget.fullName,
          username: widget.username,
          password: widget.password,
          whatsapp: widget.whatsapp,
          countryCode: widget.countryCode,
          nationalId: widget.nationalId,
          birthDate: widget.birthDate,
          termsAccepted: widget.termsAccepted,
          referralPhone: widget.referralPhone,
          pendingRegistrationId: widget.pendingRegistrationId ?? '',
          otpCode: _otpC.text,
          otpPurpose: 'register',
        );
        if (mounted) {
          AppAlertService.showSuccess(
            context,
            message: 'تم إنشاء الحساب بنجاح. يمكنك الآن تسجيل الدخول.',
          );
          Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
        }
      } else {
        await _authService.login(
          username: widget.username,
          password: widget.password,
          otpCode: _otpC.text,
        );
        await LocalSecurityService.markDeviceTrusted(widget.username);
        if (mounted)
          Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      }
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(e),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    setState(() => _isResending = true);
    try {
      final res = await _authService.requestOtp(
        purpose: widget.purpose,
        username: widget.username,
        password: widget.password,
        fullName: widget.fullName,
        whatsapp: widget.whatsapp,
        countryCode: widget.countryCode,
        nationalId: widget.nationalId,
        birthDate: widget.birthDate,
        referralPhone: widget.referralPhone,
        termsAccepted: widget.termsAccepted,
      );
      setState(() => _debugCode = res.debugOtpCode);
      _startTimer();
      if (mounted)
        AppAlertService.showSuccess(
          context,
          message: 'تم إرسال رمز تحقق جديد إلى واتساب.',
        );
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(e),
        );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildDecor(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read_rounded,
                        size: 64,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(height: 32),
                      _buildMainCard(),
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

  Widget _buildMainCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        children: [
          Text('تأكيد الرمز', style: AppTheme.h2),
          const SizedBox(height: 12),
          Text(
            'أدخل رمز التحقق المكوّن من 6 أرقام المرسل إلى حساب الواتساب الخاص بك.',
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _otpC,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: AppTheme.h1.copyWith(
              letterSpacing: 12,
              color: AppTheme.primary,
            ),
            decoration: const InputDecoration(
              hintText: '••••••',
              counterText: '',
            ),
          ),
          if (_debugCode != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.05),
                borderRadius: AppTheme.radiusMd,
              ),
              child: Text(
                'رمز تجريبي: $_debugCode',
                style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
              ),
            ),
          ],
          const SizedBox(height: 40),
          ShwakelButton(
            label: 'تحقق الآن',
            icon: Icons.verified_rounded,
            onPressed: _verify,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _cooldown > 0
                    ? 'يمكنك إعادة الإرسال خلال $_cooldown ثانية'
                    : 'لم يصلك الرمز؟',
                style: AppTheme.caption,
              ),
              if (_cooldown == 0)
                TextButton(
                  onPressed: _resend,
                  child: Text(
                    _isResending ? 'جارٍ الإرسال...' : 'أرسل مرة أخرى',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDecor() => Stack(
    children: [
      Positioned(
        top: -50,
        right: -50,
        child: CircleAvatar(
          radius: 100,
          backgroundColor: AppTheme.primary.withOpacity(0.05),
        ),
      ),
      Positioned(
        bottom: -30,
        left: -30,
        child: CircleAvatar(
          radius: 80,
          backgroundColor: AppTheme.accent.withOpacity(0.05),
        ),
      ),
    ],
  );
}
