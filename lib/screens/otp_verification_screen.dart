import 'dart:async';

import 'package:flutter/material.dart';

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

  final String fullName;
  final String username;
  final String password;
  final bool termsAccepted;
  final String? whatsapp;
  final String? countryCode;
  final String? nationalId;
  final String? birthDate;
  final String? referralPhone;
  final String? pendingRegistrationId;
  final String purpose;
  final String? initialDebugOtpCode;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _isResending = false;
  String? _debugCode;
  int _cooldown = 60;
  Timer? _timer;

  bool get _isRegisterFlow => widget.purpose == 'register';

  @override
  void initState() {
    super.initState();
    _debugCode = widget.initialDebugOtpCode;
    _startTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _cooldown <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _verify() async {
    final l = context.loc;
    if (_otpController.text.trim().length < 4) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_otp_verification_screen.001'),
        message: l.text(
          'أدخل رمز التحقق كاملًا للمتابعة.',
          'Please enter the full verification code to continue.',
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isRegisterFlow) {
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
          otpCode: _otpController.text.trim(),
          otpPurpose: 'register',
        );
        if (!mounted) {
          return;
        }
        await AppAlertService.showSuccess(
          context,
          title: l.tr('screens_otp_verification_screen.002'),
          message: l.text(
            'تم إنشاء الحساب بنجاح. يمكنك الآن تسجيل الدخول.',
            'Your account has been created successfully. You can log in now.',
          ),
        );
        if (!mounted) {
          return;
        }
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }

      await _authService.login(
        username: widget.username,
        password: widget.password,
        otpCode: _otpController.text.trim(),
      );
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      await LocalSecurityService.markDeviceTrusted(
        widget.username.trim().toLowerCase(),
      );
      await RealtimeNotificationService.start();
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_otp_verification_screen.003'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) {
      return;
    }

    final l = context.loc;
    setState(() => _isResending = true);
    try {
      final response = await _authService.requestOtp(
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
      if (!mounted) {
        return;
      }
      setState(() => _debugCode = response.debugOtpCode);
      _startTimer();
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_otp_verification_screen.004'),
        message: l.text(
          'تم إرسال رمز تحقق جديد إلى واتساب.',
          'A new verification code has been sent to WhatsApp.',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_otp_verification_screen.005'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
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
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _buildMainCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 76,
            height: 76,
            margin: const EdgeInsets.symmetric(horizontal: 0),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 38,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.tr('screens_otp_verification_screen.006'),
            style: AppTheme.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _isRegisterFlow
                ? l.text(
                    'أدخل رمز التحقق المرسل إلى واتساب لإكمال إنشاء الحساب.',
                    'Enter the code sent to your WhatsApp to complete registration.',
                  )
                : l.text(
                    'أدخل رمز التحقق المرسل إلى واتساب لتسجيل الدخول بأمان.',
                    'Enter the code sent to your WhatsApp to sign in securely.',
                  ),
            textAlign: TextAlign.center,
            style: AppTheme.bodyAction.copyWith(height: 1.6),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: AppTheme.radiusMd,
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_otp_verification_screen.007'),
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 4),
                Text(widget.username, style: AppTheme.bodyBold),
                if ((widget.whatsapp ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.tr('screens_otp_verification_screen.008'),
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(widget.whatsapp!, style: AppTheme.bodyAction),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: AppTheme.h1.copyWith(
              letterSpacing: 10,
              color: AppTheme.primary,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              labelText: l.tr('screens_otp_verification_screen.009'),
            ),
          ),
          if (_debugCode != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.07),
                borderRadius: AppTheme.radiusMd,
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                l.tr(
                  'screens_otp_verification_screen.010',
                  params: {'debugCode': _debugCode ?? ''},
                ),
                textAlign: TextAlign.center,
                style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ShwakelButton(
            label: _isRegisterFlow
                ? l.tr('screens_otp_verification_screen.011')
                : l.tr('screens_otp_verification_screen.012'),
            icon: Icons.verified_rounded,
            onPressed: _verify,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: AppTheme.radiusMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _cooldown > 0
                        ? l.text(
                            'يمكنك إعادة الإرسال خلال $_cooldown ثانية',
                            'You can resend the code in $_cooldown seconds',
                          )
                        : l.text(
                            'لم يصلك الرمز بعد؟',
                            "Didn't receive the code yet?",
                          ),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: (_cooldown > 0 || _isResending) ? null : _resend,
                  child: Text(
                    _isResending
                        ? l.tr('screens_otp_verification_screen.013')
                        : l.tr('screens_otp_verification_screen.014'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecor() {
    return Stack(
      children: [
        Positioned(
          top: -50,
          right: -50,
          child: CircleAvatar(
            radius: 100,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.05),
          ),
        ),
        Positioned(
          bottom: -30,
          left: -30,
          child: CircleAvatar(
            radius: 80,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.05),
          ),
        ),
      ],
    );
  }
}
