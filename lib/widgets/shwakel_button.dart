import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ShwakelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final Gradient? gradient;
  final bool isLoading;
  final bool isSecondary;
  final bool isDanger;
  final double? width;
  final double height;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final bool iconAtEnd;

  const ShwakelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
    this.gradient,
    this.isLoading = false,
    this.isSecondary = false,
    this.isDanger = false,
    this.width,
    this.height = 54,
    this.padding,
    this.fontSize,
    this.iconAtEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = AppTheme.isPhone(context);
    var backgroundColor =
        color ?? (isSecondary ? Colors.white : AppTheme.primary);
    var foregroundColor = isSecondary ? AppTheme.primary : Colors.white;
    var borderColor = isSecondary ? AppTheme.primary : Colors.transparent;

    if (isDanger) {
      backgroundColor = AppTheme.error;
      foregroundColor = Colors.white;
      borderColor = Colors.transparent;
    }

    if (onPressed == null) {
      backgroundColor = AppTheme.border;
      foregroundColor = AppTheme.textSecondary;
      borderColor = Colors.transparent;
    }

    final safeGradient = AppTheme.webSafeGradient(gradient);
    final isGradient = safeGradient != null && onPressed != null;
    if (!isGradient && gradient != null && onPressed != null && !isSecondary) {
      backgroundColor = AppTheme.webSafeGradientFallback(
        gradient,
        fallback: backgroundColor,
      );
    }
    final borderRadius = AppTheme.radiusMd;

    final content = isLoading
        ? SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (icon != null) ...[
                if (!iconAtEnd) ...[
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                ],
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize ?? (isPhone ? 15 : 16),
                    fontWeight: FontWeight.w900,
                    fontFamily: 'NotoSansArabic',
                  ),
                ),
              ),
              if (icon != null && iconAtEnd) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 22),
              ],
            ],
          );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isGradient ? null : backgroundColor,
        gradient: isGradient ? safeGradient : null,
        borderRadius: borderRadius,
        boxShadow: (onPressed != null && !isSecondary)
            ? AppTheme.softShadow
            : null,
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: foregroundColor,
          shadowColor: Colors.transparent,
          elevation: 0,
          side: isSecondary ? BorderSide(color: borderColor, width: 1.5) : null,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          padding:
              padding ??
              EdgeInsets.symmetric(
                horizontal: isPhone ? 18 : AppTheme.spacingLg,
              ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: content,
      ),
    );
  }
}
