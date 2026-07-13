import 'dart:math' as math;

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
            : 14.0;
        // The responsive gutter is a minimum, not an extra inset. Several
        // screens pass their own page padding; adding both values made mobile
        // content unnecessarily narrow (for example 24 + 14 on each side).
        final effectivePadding = EdgeInsets.fromLTRB(
          math.max(horizontalPadding, padding.left),
          padding.top + (width < 720 ? 2 : 0),
          math.max(horizontalPadding, padding.right),
          padding.bottom + (width < 720 ? 2 : 0),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width.isFinite ? math.min(width, maxWidth) : maxWidth,
            child: Padding(padding: effectivePadding, child: child),
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
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.background,
                gradient: AppTheme.webSafeGradient(
                  AppTheme.pageBackgroundGradient,
                ),
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
            top: 32,
            left: -48,
            child: IgnorePointer(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(42),
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
