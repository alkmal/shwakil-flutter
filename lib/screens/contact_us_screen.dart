import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/index.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
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
      final c = await ContactInfoService.getContactInfo(refresh: true);
      if (mounted)
        setState(() {
          _contact = c;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _contact = ContactInfoService.fallbackContact();
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final c = _contact ?? ContactInfoService.fallbackContact();
    final title = ContactInfoService.title(c);
    final whatsapp = ContactInfoService.supportWhatsapp(c);
    final email = ContactInfoService.supportEmail(c);
    final address = ContactInfoService.address(c);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(title)),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              _buildSupportHero(),
              const SizedBox(height: 24),
              _buildContactItem(
                Icons.chat_rounded,
                'واتساب الدعم المباشر',
                whatsapp,
                'https://wa.me/$whatsapp',
                AppTheme.success,
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                Icons.email_rounded,
                'البريد الرسمي',
                email,
                'mailto:$email',
                AppTheme.primary,
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                Icons.location_on_rounded,
                'المقر الرئيسي',
                address,
                '',
                AppTheme.accent,
              ),
              const SizedBox(height: 32),
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
                        'ساعات العمل: 9:00 ص - 9:00 م',
                        style: AppTheme.bodyBold,
                      ),
                      Text(
                        'نحن جاهزون لخدمتكم طوال أيام الأسبوع، باستثناء العطل الرسمية.',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption,
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
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      child: Row(
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مركز مساعدة شواكل',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                Text(
                  'فريقنا جاهز للرد على استفساراتكم ومعالجة المشكلات التقنية بأسرع وقت.',
                  style: AppTheme.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(
    IconData icon,
    String label,
    String value,
    String url,
    Color color,
  ) {
    return ShwakelCard(
      onTap: url.isEmpty
          ? null
          : () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.bodyBold),
                Text(value, style: AppTheme.caption),
              ],
            ),
          ),
          if (url.isNotEmpty)
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
