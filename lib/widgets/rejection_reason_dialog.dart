import 'package:flutter/material.dart';

import '../services/index.dart';

Future<String?> showRejectionReasonDialog(
  BuildContext context, {
  required String title,
  required String confirmText,
  String? labelText,
  String? hintText,
  String? emptyMessage,
  String initialValue = '',
}) async {
  final l = context.loc;
  final controller = TextEditingController(text: initialValue);
  var errorText = '';

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: labelText ?? l.tr('shared.rejection_reason_label'),
              hintText: hintText ?? l.tr('shared.rejection_reason_hint'),
              errorText: errorText.isEmpty ? null : errorText,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                setDialogState(() {
                  errorText =
                      emptyMessage ?? l.tr('shared.rejection_reason_required');
                });
                return;
              }

              Navigator.pop(dialogContext, value);
            },
            child: Text(confirmText),
          ),
        ],
      ),
    ),
  );

  controller.dispose();
  return result;
}
