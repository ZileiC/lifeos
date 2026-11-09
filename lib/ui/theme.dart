import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LifeOS dark theme — "editorial dark, racing-calm".
/// Design system: design-system/lifeos/MASTER.md.
class AppTheme {
  // Palette
  static const bg = Color(0xFF08090B);
  static const surface = Color(0xFF101114);
  static const surfaceHigh = Color(0xFF17181C);
  static const ink = Color(0xFFF1EEE8);
  static const inkDim = Color(0xFF8C8B86);
  static const line = Color(0xFF26272C);
  static const lineSoft = Color(0xFF1B1C20);
  static const accent = Color(0xFFD7261E);
  static const accentDim = Color(0xFF7E1712);

  // Motion tokens
  static const durFast = Duration(milliseconds: 120);
  static const durBase = Duration(milliseconds: 200);
  static const durSlow = Duration(milliseconds: 360);
  static const durCinematic = Duration(milliseconds: 520);
  static const easeOut = Cubic(0.16, 1, 0.3, 1);
  static const easeInOut = Cubic(0.65, 0, 0.35, 1);

  static const _cjkFallback = <String>['Noto Sans SC', 'PingFang SC', 'Microsoft YaHei'];

  static TextStyle _display(double size, FontWeight weight, {double? tracking, Color? color}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      height: 1.04,
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextStyle _body(double size, FontWeight weight, {double? tracking, Color? color, double? height}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      height: height ?? 1.45,
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextStyle _mono(double size, FontWeight weight, {Color? color}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.2,
      letterSpacing: 0.04,
      fontFeatures: const [FontFeature.tabularFigures()],
    ).copyWith(fontFamilyFallback: _cjkFallback);
  }

  static TextTheme get _textTheme {
    final base = ThemeData.dark().textTheme;
    return base.copyWith(
      displayLarge: _display(40, FontWeight.w600, tracking: -0.03),
      displayMedium: _display(32, FontWeight.w600, tracking: -0.02),
      displaySmall: _display(26, FontWeight.w600, tracking: -0.02),
      headlineLarge: _display(26, FontWeight.w600, tracking: -0.02),
      headlineMedium: _display(22, FontWeight.w600, tracking: -0.015),
      headlineSmall: _display(18, FontWeight.w600, tracking: -0.01),
      titleLarge: _display(21, FontWeight.w600, tracking: -0.01),
      titleMedium: _body(16, FontWeight.w600, tracking: 0),
      titleSmall: _body(14, FontWeight.w600, tracking: 0.01),
      bodyLarge: _body(15, FontWeight.w400),
      bodyMedium: _body(14, FontWeight.w400),
      bodySmall: _body(12, FontWeight.w400),
      labelLarge: _body(12, FontWeight.w600, tracking: 0.08),
      labelMedium: _body(11, FontWeight.w600, tracking: 0.12),
      labelSmall: _mono(10, FontWeight.w500),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFFFFF7F5),
      secondary: ink,
      onSecondary: bg,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: inkDim,
      outline: line,
      outlineVariant: lineSoft,
      error: accent,
      onError: Color(0xFFFFF7F5),
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
        titleTextStyle: _display(28, FontWeight.w600, tracking: 0.01, color: ink),
        iconTheme: const IconThemeData(color: inkDim, size: 22),
      ),
      textTheme: text,
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
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
          backgroundColor: accent,
          foregroundColor: const Color(0xFFFFF7F5),
          textStyle: _body(14, FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
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
            borderRadius: BorderRadius.all(Radius.circular(14)),
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
        foregroundColor: Color(0xFFFFF7F5),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: _body(13, FontWeight.w500, color: ink),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
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
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        side: const BorderSide(color: inkDim, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return const Color(0xFFFFF7F5);
          return inkDim;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
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
        color: accent,
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
