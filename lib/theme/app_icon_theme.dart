import 'package:flutter/material.dart';

class AppIconTheme extends ThemeExtension<AppIconTheme> {
  const AppIconTheme({
    this.fill = 1.0,
    this.weight = 700.0,
    this.grade,
    this.opticalSize,
    this.color,
    this.shadows,
  });

  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final Color? color;
  final List<Shadow>? shadows;

  @override
  AppIconTheme copyWith({
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
  }) {
    return AppIconTheme(
      fill: fill ?? this.fill,
      weight: weight ?? this.weight,
      grade: grade ?? this.grade,
      opticalSize: opticalSize ?? this.opticalSize,
      color: color ?? this.color,
      shadows: shadows ?? this.shadows,
    );
  }

  @override
  AppIconTheme lerp(ThemeExtension<AppIconTheme>? other, double t) {
    if (other is! AppIconTheme) {
      return this;
    }
    return AppIconTheme(
      fill: t < 0.5 ? fill : other.fill,
      weight: t < 0.5 ? weight : other.weight,
      grade: t < 0.5 ? grade : other.grade,
      opticalSize: t < 0.5 ? opticalSize : other.opticalSize,
      color: Color.lerp(color, other.color, t),
      shadows: t < 0.5 ? shadows : other.shadows,
    );
  }
}
