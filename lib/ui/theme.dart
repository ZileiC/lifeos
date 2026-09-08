import 'package:flutter/material.dart';

/// 深色唯一主题。
/// 品味目标：干净、有重量感、排版整齐；拒绝霓虹渐变。
/// 用近黑灰阶 + 单一低饱和强调色（青灰蓝），层次靠表面色阶而非发光。
class AppTheme {
  // 色板：低饱和、有分量
  static const _bg = Color(0xFF111318); // 近黑，带一点冷
  static const _surface = Color(0xFF191C22);
  static const _surfaceHigh = Color(0xFF21252D);
  static const _outline = Color(0xFF2E333D);
  static const _accent = Color(0xFF8FB4CC); // 灰蓝，克制
  static const _accentDim = Color(0xFF5C7A8E);
  static const _onBg = Color(0xFFE4E6EB);
  static const _onBgDim = Color(0xFF9AA0AB);
  static const _danger = Color(0xFFC97676);

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      primary: _accent,
      onPrimary: Color(0xFF10202B),
      secondary: _accentDim,
      onSecondary: _onBg,
      surface: _surface,
      onSurface: _onBg,
      surfaceContainerHighest: _surfaceHigh,
      onSurfaceVariant: _onBgDim,
      outline: _outline,
      outlineVariant: _outline,
      error: _danger,
      onError: Color(0xFF1A0E0E),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      fontFamily: null, // 平台默认（Android: Roboto；Windows: Segoe UI）
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: _onBg,
        displayColor: _onBg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _onBg,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: _onBgDim),
      ),
      navigationDrawerTheme: const NavigationDrawerThemeData(
        backgroundColor: _surface,
        tileHeight: 52,
      ),
      cardTheme: const CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.transparent;
        }),
        side: const BorderSide(color: _onBgDim, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _accent,
        foregroundColor: Color(0xFF10202B),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: _onBgDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(color: _outline, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHigh,
        contentTextStyle: const TextStyle(color: _onBg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: _surface),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _surface,
        modalBackgroundColor: _surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: _surfaceHigh,
        labelStyle: const TextStyle(color: _onBgDim),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      menuTheme: const MenuThemeData(),
      popupMenuTheme: const PopupMenuThemeData(
        color: _surfaceHigh,
        textStyle: TextStyle(color: _onBg, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
