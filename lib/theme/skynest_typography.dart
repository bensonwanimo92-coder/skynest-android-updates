import 'package:flutter/material.dart';

/// Shared, restrained typography for SkyNest screens.
///
/// The scale keeps headings compact, body copy comfortably readable and
/// secondary labels visibly subordinate without relying on a bundled font.
TextTheme buildSkyNestTextTheme(ColorScheme scheme) {
  final primary = scheme.onSurface;
  final secondary = scheme.onSurfaceVariant;

  return TextTheme(
    displayLarge: TextStyle(
      color: primary,
      fontSize: 32,
      height: 1.16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.7,
    ),
    displayMedium: TextStyle(
      color: primary,
      fontSize: 28,
      height: 1.18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.45,
    ),
    displaySmall: TextStyle(
      color: primary,
      fontSize: 24,
      height: 1.22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
    ),
    headlineLarge: TextStyle(
      color: primary,
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    headlineMedium: TextStyle(
      color: primary,
      fontSize: 21,
      height: 1.28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    headlineSmall: TextStyle(
      color: primary,
      fontSize: 19,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      color: primary,
      fontSize: 18,
      height: 1.32,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.05,
    ),
    titleMedium: TextStyle(
      color: primary,
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    titleSmall: TextStyle(
      color: primary,
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyLarge: TextStyle(
      color: primary,
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    ),
    bodyMedium: TextStyle(
      color: primary,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
    ),
    bodySmall: TextStyle(
      color: secondary,
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    ),
    labelLarge: TextStyle(
      color: primary,
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      color: secondary,
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelSmall: TextStyle(
      color: secondary,
      fontSize: 11,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );
}
