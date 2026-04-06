import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/app_theme.dart';

class SupportContactCard extends StatelessWidget {
  const SupportContactCard({
    super.key,
    required this.phoneNumber,
    this.message,
    this.title = 'الدعم والتواصل',
  });

  final String phoneNumber;
  final String? message;
  final String title;

  Future<void> _copyNumber(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phoneNumber));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم نسخ رقم الدعم')));
  }

  Future<void> _openWhatsapp(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/$phoneNumber');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب على هذا الجهاز')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF0FDFA)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBEEAE1)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFF0F766E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            phoneNumber,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF115E59),
            ),
          ),
          if ((message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openWhatsapp(context),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('فتح واتساب'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyNumber(context),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ الرقم'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
