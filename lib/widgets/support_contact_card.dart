import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/index.dart';
import '../services/app_alert_service.dart';
import '../utils/app_theme.dart';

class SupportContactCard extends StatelessWidget {
  const SupportContactCard({
    super.key,
    required this.phoneNumber,
    this.message,
    this.title,
  });

  final String phoneNumber;
  final String? message;
  final String? title;

  Future<void> _copyNumber(BuildContext context) async {
    final l = context.loc;
    await Clipboard.setData(ClipboardData(text: phoneNumber));
    if (!context.mounted) {
      return;
    }
    AppAlertService.showSnack(
      context,
      message: l.tr('widgets_support_contact_card.001'),
      type: AppAlertType.success,
    );
  }

  Future<void> _openWhatsapp(BuildContext context) async {
    final l = context.loc;
    final uri = Uri.parse('https://wa.me/$phoneNumber');
    var opened = false;
    try {
      opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      opened = false;
    }
    if (!context.mounted) return;
    if (!opened) {
      AppAlertService.showSnack(
        context,
        message: l.tr('widgets_support_contact_card.002'),
        type: AppAlertType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.cardHighlightGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.support_agent_rounded,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title ?? l.tr('widgets_support_contact_card.003'),
                    style: AppTheme.bodyBold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            phoneNumber,
            style: AppTheme.h2.copyWith(
              fontSize: 20,
              color: AppTheme.primaryDark,
            ),
          ),
          if ((message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: AppTheme.caption.copyWith(
                color: AppTheme.textSecondary,
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
                label: Text(l.tr('widgets_support_contact_card.004')),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyNumber(context),
                icon: const Icon(Icons.copy_rounded),
                label: Text(l.tr('widgets_support_contact_card.005')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
