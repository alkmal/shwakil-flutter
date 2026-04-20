import 'package:flutter/material.dart';

import '../localization/index.dart';

class ShwakelLogo extends StatelessWidget {
  const ShwakelLogo({
    super.key,
    this.size = 84,
    this.showLabel = false,
    this.labelColor = const Color(0xFF0F766E),
    this.framed = false,
    this.framePadding,
    this.frameColor = const Color(0x14FFFFFF),
    this.frameBorderColor = const Color(0x22FFFFFF),
  });
  final double size;
  final bool showLabel;
  final Color labelColor;
  final bool framed;
  final EdgeInsetsGeometry? framePadding;
  final Color frameColor;
  final Color frameBorderColor;
  @override
  Widget build(BuildContext context) {
    final resolvedFramePadding = (framePadding ?? EdgeInsets.all(size * 0.12))
        .resolve(Directionality.of(context));
    final framedLogoWidth = (size - resolvedFramePadding.horizontal).clamp(
      0.0,
      size,
    );
    final framedLogoHeight = (size - resolvedFramePadding.vertical).clamp(
      0.0,
      size,
    );

    Widget buildLogo(double width, double height) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/images/shwakel_app_icon.png',
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (framed)
          SizedBox(
            width: size,
            height: size,
            child: Container(
              padding: resolvedFramePadding,
              decoration: BoxDecoration(
                color: frameColor,
                borderRadius: BorderRadius.circular(size * 0.32),
                border: Border.all(color: frameBorderColor),
              ),
              child: SizedBox(
                width: framedLogoWidth,
                height: framedLogoHeight,
                child: buildLogo(framedLogoWidth, framedLogoHeight),
              ),
            ),
          )
        else
          SizedBox(width: size, height: size, child: buildLogo(size, size)),
        if (showLabel) ...[
          const SizedBox(height: 10),
          Text(
            context.loc.tr('widgets_shwakel_logo.001'),
            style: TextStyle(
              color: labelColor,
              fontSize: size * 0.24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}
