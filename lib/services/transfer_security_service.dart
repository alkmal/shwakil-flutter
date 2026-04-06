import 'dart:async';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'local_security_service.dart';

class TransferSecurityResult {
  const TransferSecurityResult({
    required this.isVerified,
    this.method,
    this.otpCode,
  });
  final bool isVerified;
  final String? method;
  final String? otpCode;
}

class TransferSecurityService {
  TransferSecurityService._();
  static Future<TransferSecurityResult> confirmTransfer(
    BuildContext context, {
    bool requireOtpAfterLocalAuth = false,
    bool allowOtpFallback = true,
  }) async {
    final hasPin = await LocalSecurityService.hasPin();
    final biometricEnabled = await LocalSecurityService.isBiometricEnabled();
    final canUseBiometrics =
        biometricEnabled && await LocalSecurityService.canUseBiometrics();
    if (!context.mounted) {
      return const TransferSecurityResult(isVerified: false);
    }
    if (canUseBiometrics) {
      final biometricOk =
          await LocalSecurityService.authenticateWithBiometrics();
      if (biometricOk) {
        if (!context.mounted) {
          return const TransferSecurityResult(isVerified: false);
        }
        if (requireOtpAfterLocalAuth) {
          return _confirmWithOtp(
            context,
            introText:
                'تم التحقق المحلي بالبصمة بنجاح. أكمل الآن بإدخال رمز OTP المرسل إلى واتساب الحساب.',
          );
        }
        return const TransferSecurityResult(
          isVerified: true,
          method: 'biometric',
        );
      }
    }
    if (!context.mounted) {
      return const TransferSecurityResult(isVerified: false);
    }
    if (hasPin) {
      final pinResult = await _confirmWithPin(
        context,
        canUseBiometrics: canUseBiometrics,
      );
      if (!context.mounted) {
        return const TransferSecurityResult(isVerified: false);
      }
      if (pinResult.isVerified && requireOtpAfterLocalAuth) {
        return _confirmWithOtp(
          context,
          introText:
              'تم التحقق المحلي عبر PIN بنجاح. أدخل الآن رمز OTP المرسل إلى واتساب الحساب لإكمال العملية.',
        );
      }
      return pinResult;
    }
    if (!allowOtpFallback) {
      return const TransferSecurityResult(isVerified: false);
    }
    return _confirmWithOtp(context);
  }

  static Future<TransferSecurityResult> _confirmWithPin(
    BuildContext context, {
    required bool canUseBiometrics,
  }) async {
    final pinController = TextEditingController();
    var isChecking = false;
    final result = await showDialog<TransferSecurityResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          Future<void> submitPin() async {
            final pin = pinController.text.trim();
            if (pin.length != 4) {
              return;
            }
            setState(() => isChecking = true);
            final isValid = await LocalSecurityService.verifyPin(pin);
            if (!dialogContext.mounted) {
              return;
            }
            if (isValid) {
              await LocalSecurityService.setLastLocalAuthMethod('pin');
            }
            if (!dialogContext.mounted) {
              return;
            }
            Navigator.pop(
              dialogContext,
              TransferSecurityResult(
                isVerified: isValid,
                method: isValid ? 'pin' : null,
              ),
            );
          }

          Future<void> submitBiometric() async {
            setState(() => isChecking = true);
            final ok = await LocalSecurityService.authenticateWithBiometrics();
            if (!dialogContext.mounted) {
              return;
            }
            if (ok) {
              Navigator.pop(
                dialogContext,
                const TransferSecurityResult(
                  isVerified: true,
                  method: 'biometric',
                ),
              );
              return;
            }
            setState(() => isChecking = false);
          }

          return AlertDialog(
            title: const Text('تأكيد العملية'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  canUseBiometrics
                      ? 'تمت محاولة التحقق بالبصمة أولًا. يمكنك الآن المتابعة باستخدام PIN إذا رغبت.'
                      : 'أدخل رمز PIN لإتمام العملية.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  onSubmitted: (_) => submitPin(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isChecking
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        const TransferSecurityResult(isVerified: false),
                      ),
                child: const Text('إلغاء'),
              ),
              if (canUseBiometrics)
                OutlinedButton.icon(
                  onPressed: isChecking ? null : submitBiometric,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('البصمة'),
                ),
              ElevatedButton(
                onPressed: isChecking ? null : submitPin,
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );
    pinController.dispose();
    return result ?? const TransferSecurityResult(isVerified: false);
  }

  static Future<TransferSecurityResult> _confirmWithOtp(
    BuildContext context, {
    String? introText,
  }) async {
    final apiService = ApiService();
    final codeController = TextEditingController();
    var infoText =
        introText ??
        'هذا الجهاز لا يملك بصمة مفعلة ولا PIN محفوظ، لذلك سنستخدم OTP على واتساب الحساب.';
    var isSending = false;
    var hasSentOtp = false;
    var resendCooldown = 0;
    Timer? resendTimer;
    final result = await showDialog<TransferSecurityResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          void startResendCooldown() {
            resendTimer?.cancel();
            setState(() => resendCooldown = 60);
            resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (!dialogContext.mounted) {
                timer.cancel();
                return;
              }
              if (resendCooldown <= 1) {
                setState(() => resendCooldown = 0);
                timer.cancel();
                return;
              }
              setState(() => resendCooldown -= 1);
            });
          }

          Future<void> sendOtp() async {
            setState(() => isSending = true);
            try {
              final otpResult = await apiService.requestTransferSecurityOtp();
              if (!dialogContext.mounted) {
                return;
              }
              setState(() {
                hasSentOtp = true;
                infoText = otpResult.debugOtpCode == null
                    ? 'تم إرسال الرمز إلى واتساب الحساب. أدخله لإتمام العملية.'
                    : 'تم إرسال الرمز إلى واتساب الحساب. رمز الديبق: ${otpResult.debugOtpCode}';
                isSending = false;
              });
              startResendCooldown();
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setState(() {
                infoText = error.toString();
                isSending = false;
              });
            }
          }

          return AlertDialog(
            title: const Text('تحقق عبر OTP'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(infoText),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رمز التحقق',
                    prefixIcon: Icon(Icons.sms_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSending
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        const TransferSecurityResult(isVerified: false),
                      ),
                child: const Text('إلغاء'),
              ),
              if (!hasSentOtp || resendCooldown == 0)
                OutlinedButton(
                  onPressed: isSending ? null : sendOtp,
                  child: Text(
                    isSending
                        ? 'جارٍ الإرسال...'
                        : hasSentOtp
                        ? 'إعادة إرسال الرمز'
                        : 'إرسال الرمز',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(
                    'يمكنك إعادة الإرسال بعد $resendCooldown ثانية',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ElevatedButton(
                onPressed: () {
                  final code = codeController.text.trim();
                  if (code.isEmpty) {
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    TransferSecurityResult(
                      isVerified: true,
                      method: 'otp',
                      otpCode: code,
                    ),
                  );
                },
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );
    codeController.dispose();
    resendTimer?.cancel();
    return result ?? const TransferSecurityResult(isVerified: false);
  }
}
