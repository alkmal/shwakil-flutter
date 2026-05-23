import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/auth_screen_shell.dart';
import '../widgets/shwakel_button.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.fullName,
    required this.username,
    this.password,
    this.termsAccepted = false,
    this.whatsapp,
    this.countryCode,
    this.nationalId,
    this.birthDate,
    this.referralPhone,
    this.pendingRegistrationId,
    this.purpose = 'login',
    this.redirectRoute,
    this.offlineMode = false,
    this.initialDebugOtpCode,
    this.statusMessage,
  });

  final String fullName;
  final String username;
  final String? password;
  final bool termsAccepted;
  final String? whatsapp;
  final String? countryCode;
  final String? nationalId;
  final String? birthDate;
  final String? referralPhone;
  final String? pendingRegistrationId;
  final String purpose;
  final String? redirectRoute;
  final bool offlineMode;
  final String? initialDebugOtpCode;
  final String? statusMessage;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final AuthService _authService = AuthService();

  String? _pendingRegistrationId;
  bool _isLoading = false;
  bool _isResending = false;
  String? _debugCode;
  String? _statusMessage;
  int _cooldown = 60;
  Timer? _timer;

  bool get _isRegisterFlow => widget.purpose == 'register';
  String get _postAuthRoute => widget.redirectRoute?.trim().isNotEmpty == true
      ? widget.redirectRoute!.trim()
      : '/home';

  @override
  void initState() {
    super.initState();
    if (_isRegisterFlow) {
      OfflineSessionService.setOfflineMode(false);
      unawaited(_authService.logout());
    }
    _pendingRegistrationId = widget.pendingRegistrationId;
    _debugCode = widget.initialDebugOtpCode;
    _statusMessage = widget.statusMessage?.trim();
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
        message: l.tr('screens_otp_verification_screen.015'),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isRegisterFlow) {
        final response = await _authService.register(
          fullName: widget.fullName,
          username: widget.username,
          whatsapp: widget.whatsapp,
          countryCode: widget.countryCode,
          nationalId: widget.nationalId,
          birthDate: widget.birthDate,
          termsAccepted: widget.termsAccepted,
          referralPhone: widget.referralPhone,
          pendingRegistrationId: _pendingRegistrationId ?? '',
          otpCode: _otpController.text.trim(),
          otpPurpose: 'register',
        );
        if (!mounted) {
          return;
        }
        await AppAlertService.showSuccess(
          context,
          title: l.tr('screens_otp_verification_screen.002'),
          message:
              response['message']?.toString() ??
              l.tr('screens_otp_verification_screen.016'),
        );
        if (!mounted) {
          return;
        }
        await ReferralAttributionService.clearPendingReferralCode();
        if (!mounted) {
          return;
        }
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }

      await _authService.login(
        username: widget.username,
        password: widget.password ?? '',
        otpCode: _otpController.text.trim(),
      );
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.clearSecuritySetupRequirement();
      await LocalSecurityService.skipNextUnlock();
      await LocalSecurityService.markDeviceTrusted(
        widget.username.trim().toLowerCase(),
      );
      OfflineSessionService.setOfflineMode(widget.offlineMode);
      if (!widget.offlineMode) {
        await RealtimeNotificationService.start();
      }
      if (!mounted) {
        return;
      }
      final navigator = Navigator.of(context);
      if (!await LocalSecurityService.hasConfiguredLocalSecurity()) {
        await LocalSecurityService.markLocalSecuritySetupReminderShown();
        if (!mounted) {
          return;
        }
        navigator.pushNamedAndRemoveUntil(
          '/security-settings',
          (route) => false,
          arguments: const {'showSetupHint': true},
        );
        return;
      }
      if (widget.redirectRoute?.trim().isNotEmpty == true) {
        if (widget.offlineMode) {
          navigator.pushNamedAndRemoveUntil(
            widget.redirectRoute!,
            (route) => false,
          );
          return;
        }
      }
      navigator.pushNamedAndRemoveUntil(_postAuthRoute, (route) => false);
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
        pendingRegistrationId: _pendingRegistrationId,
        termsAccepted: widget.termsAccepted,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _debugCode = response.debugOtpCode;
        _statusMessage = response.message?.trim();
        if ((response.pendingRegistrationId ?? '').trim().isNotEmpty) {
          _pendingRegistrationId = response.pendingRegistrationId!.trim();
        }
      });
      _startTimer();
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_otp_verification_screen.004'),
        message: response.message?.toString().trim().isNotEmpty == true
            ? response.message!.trim()
            : l.tr('screens_otp_verification_screen.017'),
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

  String _subtitle(AppLocalizer l) {
    return _isRegisterFlow
        ? l.tr('screens_otp_verification_screen.018')
        : l.tr('screens_otp_verification_screen.019');
  }

  String _resendLabel(AppLocalizer l) {
    if (_cooldown > 0) {
      return l.tr(
        'screens_otp_verification_screen.020',
        params: {'count': '$_cooldown'},
      );
    }
    return l.tr('screens_otp_verification_screen.021');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return AuthScreenShell(
      title: l.tr('screens_otp_verification_screen.006'),
      subtitle: _subtitle(l),
      maxFormWidth: 500,
      child: _buildMainCard(),
    );
  }

  Widget _buildMainCard() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 32,
              color: AppTheme.primary,
            ),
          ),
        ),
        if ((_statusMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: AppTheme.radiusMd,
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _buildDestinationLine(l),
        const SizedBox(height: 18),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: AppTheme.h1.copyWith(
            letterSpacing: 0,
            color: AppTheme.primary,
          ),
          decoration: InputDecoration(
            hintText: '••••••',
            counterText: '',
            labelText: l.tr('screens_otp_verification_screen.009'),
          ),
        ),
        if (_debugCode != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              style: AppTheme.caption.copyWith(
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _resendLabel(l),
                style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
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
      ],
    );
  }

  Widget _buildDestinationLine(AppLocalizer l) {
    final phone = (widget.whatsapp ?? '').trim();
    final value = phone.isNotEmpty
        ? PhoneNumberService.localDisplay(phone)
        : (widget.username.trim().isEmpty
              ? l.tr('screens_otp_verification_screen.022')
              : widget.username);

    return Text(
      value,
      textAlign: TextAlign.center,
      style: AppTheme.bodyBold.copyWith(color: AppTheme.textSecondary),
    );
  }
}
