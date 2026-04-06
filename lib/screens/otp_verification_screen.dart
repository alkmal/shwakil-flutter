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
    if (_otpController.text.trim().length < 4) {
      await AppAlertService.showError(
        context,
        title: 'رمز غير مكتمل',
        message: 'أدخل رمز التحقق كاملًا للمتابعة.',
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
          title: 'تم التفعيل',
          message: 'تم إنشاء الحساب بنجاح. يمكنك الآن تسجيل الدخول.',
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
        title: 'تعذر التحقق',
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
        title: 'تمت إعادة الإرسال',
        message: 'تم إرسال رمز تحقق جديد إلى واتساب.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر الإرسال',
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
          Text('تأكيد الرمز', style: AppTheme.h2, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            _isRegisterFlow
                ? 'أدخل رمز التحقق المرسل إلى واتساب لإكمال إنشاء الحساب.'
                : 'أدخل رمز التحقق المرسل إلى واتساب لتسجيل الدخول بأمان.',
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
                Text('اسم المستخدم', style: AppTheme.caption),
                const SizedBox(height: 4),
                Text(widget.username, style: AppTheme.bodyBold),
                if ((widget.whatsapp ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('واتساب', style: AppTheme.caption),
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
            decoration: const InputDecoration(
              hintText: '••••••',
              counterText: '',
              labelText: 'رمز التحقق',
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
                'رمز تجريبي: $_debugCode',
                textAlign: TextAlign.center,
                style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ShwakelButton(
            label: _isRegisterFlow ? 'إكمال إنشاء الحساب' : 'تأكيد الدخول',
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
                        ? 'يمكنك إعادة الإرسال خلال $_cooldown ثانية'
                        : 'لم يصلك الرمز بعد؟',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: (_cooldown > 0 || _isResending) ? null : _resend,
                  child: Text(
                    _isResending ? 'جارٍ الإرسال...' : 'إعادة الإرسال',
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
