import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _contact;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final contact = await ContactInfoService.getContactInfo(refresh: true);
      if (mounted) {
        setState(() {
          _contact = contact;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _contact = ContactInfoService.fallbackContact();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final contact = _contact ?? ContactInfoService.fallbackContact();
    final title = ContactInfoService.title(contact);
    final whatsapp = ContactInfoService.supportWhatsapp(contact);
    final email = ContactInfoService.supportEmail(contact);
    final address = ContactInfoService.address(contact);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              _buildSupportHero(),
              const SizedBox(height: 24),
              _buildContactItem(
                icon: Icons.chat_rounded,
                label: l.tr('screens_contact_us_screen.001'),
                value: whatsapp,
                url: whatsapp.isEmpty ? null : 'https://wa.me/$whatsapp',
                color: AppTheme.success,
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                icon: Icons.email_rounded,
                label: l.tr('screens_contact_us_screen.002'),
                value: email,
                url: email.isEmpty ? null : 'mailto:$email',
                color: AppTheme.primary,
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                icon: Icons.location_on_rounded,
                label: l.tr('screens_contact_us_screen.003'),
                value: address,
                url: null,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 24),
              ShwakelCard(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l.tr('screens_contact_us_screen.004'),
                        style: AppTheme.bodyBold,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.tr('screens_contact_us_screen.005'),
                        textAlign: TextAlign.center,
                        style: AppTheme.caption.copyWith(height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupportHero() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(30),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 640;
          final iconBox = Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 38,
            ),
          );
          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_contact_us_screen.006'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_contact_us_screen.007'),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [iconBox, const SizedBox(height: 18), content],
            );
          }

          return Row(children: [iconBox, const SizedBox(width: 20), content]);
        },
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String label,
    required String value,
    required String? url,
    required Color color,
  }) {
    return ShwakelCard(
      onTap: url == null
          ? null
          : () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.10),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodyBold),
                const SizedBox(height: 4),
                Text(value, style: AppTheme.caption.copyWith(height: 1.5)),
              ],
            ),
          ),
          if (url != null)
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppTheme.textTertiary,
            ),
        ],
      ),
    );
  }
}
