import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import 'responsive_scaffold_container.dart';
import 'shwakel_card.dart';
import 'shwakel_logo.dart';

class AuthScreenShell extends StatelessWidget {
  const AuthScreenShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.maxFormWidth = 520,
    this.showBrandPanel = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double maxFormWidth;
  final bool showBrandPanel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.pageBackgroundGradient,
        ),
        child: SafeArea(
          child: ResponsiveScaffoldContainer(
            maxWidth: 1080,
            padding: AppTheme.pagePadding(context, top: 18),
            child: Center(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 780;
                    if (isWide && showBrandPanel) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: _BrandPanel(subtitle: subtitle)),
                          const SizedBox(width: 28),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: _AuthCard(
                                title: title,
                                maxWidth: maxFormWidth,
                                child: child,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxFormWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CompactBrand(subtitle: subtitle),
                          const SizedBox(height: 22),
                          _AuthCard(title: title, child: child),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.title, required this.child, this.maxWidth});

  final String title;
  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final padding = AppTheme.isPhone(context) ? 22.0 : 30.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: ShwakelCard(
        padding: EdgeInsets.all(padding),
        shadowLevel: ShwakelShadowLevel.medium,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTheme.h1, textAlign: TextAlign.start),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShwakelLogo(
            size: 86,
            framed: true,
            frameColor: Colors.white,
            frameBorderColor: AppTheme.border,
          ),
          const SizedBox(height: 20),
          Text(l.tr('main.001'), style: AppTheme.h1.copyWith(fontSize: 36)),
          const SizedBox(height: 8),
          Text(
            subtitle?.trim().isNotEmpty == true
                ? subtitle!.trim()
                : l.tr('main.006'),
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand({this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Column(
      children: [
        const ShwakelLogo(
          size: 76,
          framed: true,
          frameColor: Colors.white,
          frameBorderColor: AppTheme.border,
        ),
        const SizedBox(height: 12),
        Text(l.tr('main.001'), style: AppTheme.h2, textAlign: TextAlign.center),
        if (subtitle?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!.trim(),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
