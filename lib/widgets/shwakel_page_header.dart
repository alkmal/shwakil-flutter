import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'shwakel_card.dart';

class ShwakelPageHeader extends StatelessWidget {
  const ShwakelPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing,
    this.badges = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? trailing;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final hasTrailing = trailing != null;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFF4FFFC), Color(0xFFF7FBFF)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      shadowLevel: ShwakelShadowLevel.medium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760 || !hasTrailing;
          final content = _buildContent(context);
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                if (hasTrailing) ...[const SizedBox(height: 18), trailing!],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: trailing!,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final titleSize = AppTheme.fluid(
      context,
      mobile: 24,
      tablet: 27,
      desktop: 30,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: AppTheme.radiusMd,
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              eyebrow!,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          title,
          style: AppTheme.h1.copyWith(fontSize: titleSize, height: 1.15),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: AppTheme.bodyAction.copyWith(
            height: 1.65,
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: badges),
        ],
      ],
    );
  }
}

class ShwakelInfoBadge extends StatelessWidget {
  const ShwakelInfoBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = AppTheme.primary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
