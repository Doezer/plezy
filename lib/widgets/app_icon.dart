import 'package:flutter/material.dart';
import '../theme/app_icon_theme.dart';

/// Wrapper around [Icon] that centralizes our Material Symbols defaults.
/// Defaults are now managed by [AppIconTheme] to allow for const constructors
/// and better performance.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();

    // Grab the theme extension for default values
    final AppIconTheme? appIconTheme = Theme.of(context).extension<AppIconTheme>();

    return Icon(
      icon,
      size: size,
      color: color ?? appIconTheme?.color,
      fill: fill ?? appIconTheme?.fill,
      weight: weight ?? appIconTheme?.weight,
      grade: grade ?? appIconTheme?.grade,
      opticalSize: opticalSize ?? appIconTheme?.opticalSize,
      shadows: shadows ?? appIconTheme?.shadows,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
}
