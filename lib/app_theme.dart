import 'package:flutter/material.dart';

/// A deliberately small, neutral palette. One accent, two surfaces, text.
/// Keep every screen in the app drawing from these tokens instead of
/// inventing new colors inline.
class AppColors {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color danger;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.danger,
  });

  static const dark = AppColors(
    bg: Color(0xFF0E0F12),
    surface: Color(0xFF17181C),
    surfaceAlt: Color(0xFF1F2125),
    border: Color(0xFF2A2C31),
    text: Color(0xFFE6E7EA),
    textMuted: Color(0xFF8A8D96),
    accent: Color(0xFF5EC4A8),
    danger: Color(0xFFE2685A),
  );

  static const light = AppColors(
    bg: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEFF1),
    border: Color(0xFFDDDEE1),
    text: Color(0xFF17181C),
    textMuted: Color(0xFF6B6E76),
    accent: Color(0xFF2E8B74),
    danger: Color(0xFFC0392B),
  );
}

class AiTermTheme {
  static ThemeData build(AppColors c, Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      fontFamily: 'monospace',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.bg,
        secondary: c.accent,
        onSecondary: c.bg,
        error: c.danger,
        onError: c.bg,
        surface: c.surface,
        onSurface: c.text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: c.border,
      iconTheme: IconThemeData(color: c.textMuted),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: c.text,
        displayColor: c.text,
        fontFamily: 'monospace',
      ),
      useMaterial3: true,
    );
  }
}
