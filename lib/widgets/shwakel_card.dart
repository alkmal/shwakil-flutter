import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

enum ShwakelShadowLevel { none, soft, medium, premium }

class ShwakelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final Color? color;
  final Gradient? gradient;
  final ShwakelShadowLevel shadowLevel;
  final bool withBorder;
  final Color? borderColor;
  final double? borderWidth;
  final double? width;
  final double? height;
  final Function()? onTap;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  const ShwakelCard({
    super.key,
    required this.child,
    this.padding,
    this.alignment,
    this.color,
    this.gradient,
    this.shadowLevel = ShwakelShadowLevel.soft,
    this.withBorder = true,
    this.borderColor,
    this.borderWidth,
    this.width,
    this.height,
    this.onTap,
    this.margin,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  List<BoxShadow>? _getShadows() {
    switch (shadowLevel) {
      case ShwakelShadowLevel.none:
        return null;
      case ShwakelShadowLevel.soft:
        return AppTheme.softShadow;
      case ShwakelShadowLevel.medium:
        return AppTheme.mediumShadow;
      case ShwakelShadowLevel.premium:
        return AppTheme.premiumShadow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeGradient = AppTheme.webSafeGradient(gradient);
    final effectiveRadius = shape == BoxShape.circle
        ? null
        : (borderRadius ?? AppTheme.radiusLg);
    final backgroundColor = safeGradient == null
        ? (color ??
              (gradient == null
                  ? AppTheme.surface
                  : AppTheme.webSafeGradientFallback(gradient)))
        : null;
    final effectiveBorderColor =
        borderColor ??
        (safeGradient == null
            ? AppTheme.border.withValues(alpha: 0.9)
            : AppTheme.glassStroke.withValues(alpha: 0.55));

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: effectiveRadius,
          child: Container(
            width: width,
            height: height,
            alignment: alignment,
            padding: padding ?? const EdgeInsets.all(AppTheme.spacingLg),
            decoration: BoxDecoration(
              color: backgroundColor,
              gradient: safeGradient,
              shape: shape,
              borderRadius: effectiveRadius,
              border: withBorder
                  ? Border.all(
                      color: effectiveBorderColor,
                      width: borderWidth ?? 0.8,
                    )
                  : null,
              boxShadow: _getShadows(),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
