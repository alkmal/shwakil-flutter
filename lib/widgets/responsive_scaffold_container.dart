import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ResponsiveScaffoldContainer extends StatelessWidget {
  const ResponsiveScaffoldContainer({
    super.key,
    required this.child,
    this.maxWidth = 1200,
    this.padding = const EdgeInsets.symmetric(vertical: 20),
    this.useSafeArea = true,
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  final bool useSafeArea;
  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPadding = width >= 1440
            ? 48.0
            : width >= 1100
            ? 32.0
            : width >= 720
            ? 24.0
            : 16.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding.add(
                EdgeInsets.symmetric(horizontal: horizontalPadding),
              ),
              child: child,
            ),
          ),
        );
      },
    );
    if (!useSafeArea) {
      return content;
    }
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.pageBackgroundGradient,
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: -30,
            child: IgnorePointer(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.highlight.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(36),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -40,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }
}
