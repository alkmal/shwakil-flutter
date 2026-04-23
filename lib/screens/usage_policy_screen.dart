import 'package:flutter/material.dart';

import '../localization/index.dart';
import '../services/api_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class UsagePolicyScreen extends StatefulWidget {
  const UsagePolicyScreen({super.key});

  @override
  State<UsagePolicyScreen> createState() => _UsagePolicyScreenState();
}

class _UsagePolicyScreenState extends State<UsagePolicyScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String _title = '';
  String _content = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = context.loc;
    try {
      final payload = await _apiService.getUsagePolicy();
      if (!mounted) {
        return;
      }
      setState(() {
        _title =
            payload['title']?.toString() ??
            l.tr('screens_usage_policy_screen.001');
        _content = payload['content']?.toString() ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final hasContent = _content.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _title.isEmpty ? l.tr('screens_usage_policy_screen.001') : _title,
        ),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: const AppSidebar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHighlights(),
                    const SizedBox(height: 20),
                    ShwakelCard(
                      padding: const EdgeInsets.all(28),
                      borderRadius: BorderRadius.circular(30),
                      shadowLevel: ShwakelShadowLevel.medium,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.description_rounded,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title.isEmpty
                                          ? l.tr('screens_usage_policy_screen.001')
                                          : _title,
                                      style: AppTheme.h3,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      l.tr('screens_usage_policy_screen.002'),
                                      style: AppTheme.bodyAction.copyWith(
                                        height: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Text(
                              hasContent
                                  ? _content
                                  : l.tr('screens_usage_policy_screen.003'),
                              style: AppTheme.bodyText.copyWith(
                                height: 1.9,
                                fontSize: 15.5,
                                color: hasContent
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLegalHero() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 560;
          final iconBox = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 36),
          );

          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_usage_policy_screen.004'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  l.tr('screens_usage_policy_screen.005'),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
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

          return Row(
            children: [iconBox, const SizedBox(width: 20), content],
          );
        },
      ),
    );
  }

  Widget _buildHighlights() {
    final l = context.loc;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _highlightCard(
          icon: Icons.verified_user_rounded,
          title: l.tr('screens_usage_policy_screen.004'),
          subtitle: l.tr('screens_usage_policy_screen.005'),
          color: AppTheme.primary,
        ),
        _highlightCard(
          icon: Icons.visibility_rounded,
          title: context.loc.tr('screens_usage_policy_screen.006'),
          subtitle: context.loc.tr('screens_usage_policy_screen.007'),
          color: AppTheme.accent,
        ),
      ],
    );
  }

  Widget _highlightCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return SizedBox(
      width: 320,
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        borderRadius: BorderRadius.circular(24),
        shadowLevel: ShwakelShadowLevel.soft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.bodyBold.copyWith(color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTheme.caption.copyWith(height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
