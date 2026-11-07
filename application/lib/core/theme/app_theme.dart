import 'package:flutter/material.dart';

/// PLACEHOLDER theme. The real visual identity is decided later from the owner's references.
/// Keep every colour, radius and spacing value here so the restyle touches one file.
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF2E7D6B);

  static const double radius = 16;
  static const double gap = 12;
  static const double pagePadding = 16;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }
}
