import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every colour, radius and spacing value of the app lives here (architecture rule 8).
/// Feature code reads colours with `context.pal` and sizes from [AppTheme].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.card,
    required this.tile,
    required this.primary,
    required this.onPrimary,
    required this.link,
    required this.amber,
    required this.green,
    required this.greenFill,
    required this.red,
    required this.text,
    required this.muted,
    required this.faint,
    required this.divider,
  });

  final Color bg; // page background
  final Color card; // card surface
  final Color tile; // tiles, fields and unselected buttons inside cards
  final Color primary; // main buttons and selected pills
  final Color onPrimary;
  final Color link; // links, charts and highlighted values
  final Color amber; // "Sample values" badge and warnings
  final Color green; // done, saved
  final Color greenFill;
  final Color red; // errors and destructive text
  final Color text;
  final Color muted;
  final Color faint;
  final Color divider;

  static const dark = AppPalette(
    bg: Color(0xFF0B111D),
    card: Color(0xFF161F2E),
    tile: Color(0xFF1E2B3E),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    link: Color(0xFF60A5FA),
    amber: Color(0xFFF59E0B),
    green: Color(0xFF22C55E),
    greenFill: Color(0xFF173B2B),
    red: Color(0xFFF87171),
    text: Color(0xFFF8FAFC),
    muted: Color(0xFF94A3B8),
    faint: Color(0xFF52607A),
    divider: Color(0xFF243247),
  );

  static const light = AppPalette(
    bg: Color(0xFFF3F6FB),
    card: Color(0xFFFFFFFF),
    tile: Color(0xFFEAF0F8),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    link: Color(0xFF2563EB),
    amber: Color(0xFFD97706),
    green: Color(0xFF16A34A),
    greenFill: Color(0xFFDCFCE7),
    red: Color(0xFFDC2626),
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    faint: Color(0xFF94A3B8),
    divider: Color(0xFFE2E8F0),
  );

  @override
  AppPalette copyWith({Color? bg}) => AppPalette(
        bg: bg ?? this.bg,
        card: card,
        tile: tile,
        primary: primary,
        onPrimary: onPrimary,
        link: link,
        amber: amber,
        green: green,
        greenFill: greenFill,
        red: red,
        text: text,
        muted: muted,
        faint: faint,
        divider: divider,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppPalette(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      tile: l(tile, other.tile),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      link: l(link, other.link),
      amber: l(amber, other.amber),
      green: l(green, other.green),
      greenFill: l(greenFill, other.greenFill),
      red: l(red, other.red),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      divider: l(divider, other.divider),
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

/// Theme choice from Settings. The designs are dark, so dark is the default.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class AppTheme {
  AppTheme._();

  static const double radius = 16; // fields, tiles, buttons
  static const double cardRadius = 24;
  static const double gap = 16; // between cards
  static const double pagePadding = 20;
  static const double cardPadding = 20;

  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.link,
      onSecondary: p.onPrimary,
      tertiary: p.amber,
      error: p.red,
      onError: p.onPrimary,
      surface: p.card,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      surfaceContainerHigh: p.card,
      surfaceContainerHighest: p.tile,
      outline: p.faint,
      outlineVariant: p.divider,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide.none,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      extensions: [p],
      dividerColor: p.divider,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.tile,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: p.muted),
        hintStyle: TextStyle(color: p.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: p.link)),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.tile,
        contentTextStyle: TextStyle(color: p.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.text),
    );
  }
}
