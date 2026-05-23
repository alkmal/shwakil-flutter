import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'shwakel_button.dart';
import 'support_contact_card.dart';

class SupportTicketActions extends StatelessWidget {
  const SupportTicketActions({super.key, required this.supportWhatsapp});

  final String supportWhatsapp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final openButton = ShwakelButton(
              label: 'فتح تذكرة للتواصل',
              onPressed: () => _openSupportTickets(context),
              icon: Icons.add_comment_rounded,
            );
            final trackingButton = ShwakelButton(
              label: 'متابعة تذكرة',
              onPressed: () => _openSupportTickets(context, tracking: true),
              icon: Icons.forum_rounded,
              isSecondary: true,
            );

            if (constraints.maxWidth < 430) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  openButton,
                  const SizedBox(height: 10),
                  trackingButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: openButton),
                const SizedBox(width: 10),
                Expanded(child: trackingButton),
              ],
            );
          },
        ),
        if (supportWhatsapp.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showWhatsappDetails(context),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('تواصل مباشر عبر واتس اب'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: AppTheme.success,
            ),
          ),
        ],
      ],
    );
  }

  void _openSupportTickets(BuildContext context, {bool tracking = false}) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == '/support-tickets') {
      return;
    }

    Navigator.pushNamed(
      context,
      '/support-tickets',
      arguments: tracking ? const {'tracking': true} : null,
    );
  }

  Future<void> _showWhatsappDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SupportContactCard(
              phoneNumber: supportWhatsapp,
              title: 'التواصل المباشر عبر واتس اب',
              message:
                  'يمكنك التواصل مباشرة أو فتح تذكرة لمتابعة الشات داخل التطبيق.',
            ),
          ),
        ),
      ),
    );
  }
}
