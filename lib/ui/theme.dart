import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LifeOS — "Midnight Instrument".
/// Palette derives from the app icon: deep navy ground, electric-blue / cyan
/// gradient identity, cool paper ink. Design system: design-system/lifeos/MASTER.md
class AppTheme {
  // Ground (sampled from the logo's navy squircle)
  static const bg = Color(0xFF060B16);
  static const surface = Color(0xFF0C1424);
  static const surfaceHigh = Color(0xFF111B2E);

  // Ink
  static const ink = Color(0xFFE8EEFA);
  static const inkDim = Color(0xFF8593AC);

  // Hairlines
  static const line = Color(0xFF1B2740);
  static const lineSoft = Color(0xFF131D31);

  // Brand: the logo's blue -> cyan gradient
  static const accent = Color(0xFF3D7BFF);
  static const accentBright = Color(0xFF4ED2FF);
  static const accentInk = Color(0xFF06101F);
  static const danger = Color(0xFFFF5B6E);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentBright, accent],
  );

  // Motion tokens
  static const durFast = Duration(milliseconds: 120);
  static const durBase = Duration(milliseconds: 200);
  static const durSlow = Duration(milliseconds: 360);
  static const durCinematic = Duration(milliseconds: 520);
  static const easeOut = Cubic(0.16, 1, 0.3, 1);
  static const easeInOut = Cubic(0.65, 0, 0.35, 1);

  static const _cjkFallback = <String>['Noto Sans SC', 'PingFang SC', 'Microsoft YaHei'];

  static TextStyle _display(double size, FontWeight weight, {double? tracking, Color? color}) {
    return GoogleFonts.sora(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      height: 1.06,
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextStyle _body(double size, FontWeight weight, {double? tracking, Color? color, double? height}) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      height: height ?? 1.45,
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextStyle _data(double size, FontWeight weight, {Color? color}) {
    return GoogleFonts.sora(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextTheme get _textTheme {
    final base = ThemeData.dark().textTheme;
    return base.copyWith(
      displayLarge: _display(42, FontWeight.w600, tracking: -0.03),
      displayMedium: _display(32, FontWeight.w600, tracking: -0.02),
      displaySmall: _display(26, FontWeight.w600, tracking: -0.02),
      headlineLarge: _display(26, FontWeight.w600, tracking: -0.02),
      headlineMedium: _display(22, FontWeight.w600, tracking: -0.015),
      headlineSmall: _display(18, FontWeight.w600, tracking: -0.01),
      titleLarge: _display(20, FontWeight.w600, tracking: -0.01),
      titleMedium: _body(16, FontWeight.w600),
      titleSmall: _body(14, FontWeight.w600, tracking: 0.01),
      bodyLarge: _body(15, FontWeight.w400),
      bodyMedium: _body(14, FontWeight.w400),
      bodySmall: _body(12, FontWeight.w400),
      labelLarge: _body(12, FontWeight.w600, tracking: 0.08),
      labelMedium: _body(11, FontWeight.w600, tracking: 0.12),
      labelSmall: _data(10, FontWeight.w500),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      primary: accentBright,
      onPrimary: accentInk,
      secondary: accent,
      onSecondary: ink,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: inkDim,
      outline: line,
      outlineVariant: lineSoft,
      error: danger,
      onError: accentInk,
    );

    final text = _textTheme;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: text,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _display(24, FontWeight.w600, tracking: 0.01, color: ink),
        iconTheme: const IconThemeData(color: inkDim, size: 22),
      ),
      textTheme: text,
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: _body(14, FontWeight.w400, color: inkDim),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentBright,
          foregroundColor: accentInk,
          textStyle: _body(14, FontWeight.w700, tracking: 0.01),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          textStyle: _body(14, FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          textStyle: _body(14, FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        showDragHandle: true,
        dragHandleColor: line,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: _body(13, FontWeight.w500, color: ink),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        labelStyle: _body(12, FontWeight.w500, color: ink),
        side: const BorderSide(color: line),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBright;
          return Colors.transparent;
        }),
        side: const BorderSide(color: inkDim, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentInk;
          return inkDim;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentBright;
          return surfaceHigh;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(line),
      ),
      iconTheme: const IconThemeData(color: inkDim),
      listTileTheme: ListTileThemeData(
        iconColor: inkDim,
        textColor: ink,
        subtitleTextStyle: _body(12, FontWeight.w400, color: inkDim),
        titleTextStyle: _body(15, FontWeight.w500, color: ink),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentBright,
        linearTrackColor: lineSoft,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
