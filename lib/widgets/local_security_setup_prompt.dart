import 'package:flutter/material.dart';

import '../localization/index.dart';
import '../services/local_security_service.dart';

/// Offers local device protection without blocking a successful login.
Future<bool> showOptionalLocalSecuritySetupPrompt(BuildContext context) async {
  if (await LocalSecurityService.hasConfiguredLocalSecurity() ||
      !await LocalSecurityService.shouldPromptLocalSecuritySetupReminder()) {
    return false;
  }
  if (!context.mounted) {
    return false;
  }

  final l = context.loc;
  final openSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: Text(l.text('حماية الدخول على هذا الجهاز', 'Protect this device')),
      content: Text(
        l.text(
          'يمكنك تفعيل البصمة أو PIN لتسهيل الدخول لاحقًا. هذا اختياري ويمكنك المتابعة الآن دون تفعيله.',
          'You can enable biometrics or a PIN for easier access later. This is optional and you can continue without it.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.text('إلغاء والمتابعة', 'Cancel and continue')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l.text('الانتقال', 'Open settings')),
        ),
      ],
    ),
  );
  await LocalSecurityService.markLocalSecuritySetupReminderShown();
  return openSettings == true;
}
