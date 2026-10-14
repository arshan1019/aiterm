import 'package:flutter/material.dart';

/// A deliberately small, neutral palette: one accent, two surfaces, text.
/// Every screen draws from these tokens via `context.colors`.
///
/// As a [ThemeExtension] it interpolates, so switching light/dark
/// cross-fades every color instead of snapping.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  /// Decorative edges: cards, dividers.
  final Color border;

  /// Edges that identify a control (text fields, outlined buttons,
  /// checkboxes): 3:1 against the surfaces, as WCAG 1.4.11 asks.
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color danger;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.outline,
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
    outline: Color(0xFF6A6E77),
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
    outline: Color(0xFF868A93),
    text: Color(0xFF17181C),
    textMuted: Color(0xFF64676F),
    accent: Color(0xFF1F7A64),
    danger: Color(0xFFC0392B),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      outline: l(outline, other.outline),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      danger: l(danger, other.danger),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppColors &&
      other.bg == bg &&
      other.surface == surface &&
      other.surfaceAlt == surfaceAlt &&
      other.border == border &&
      other.outline == outline &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.accent == accent &&
      other.danger == danger;

  @override
  int get hashCode => Object.hash(bg, surface, surfaceAlt, border, outline, text, textMuted, accent, danger);
}

/// Shared animation timing, so every transition in the app feels related.
abstract final class Motion {
  /// State changes on a control (pressed, toggled, selected).
  static const quick = Duration(milliseconds: 120);

  /// Things appearing, moving or switching.
  static const standard = Duration(milliseconds: 220);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.easeInOutCubic;
}

extension ThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme({required bool dark}) {
  final c = dark ? AppColors.dark : AppColors.light;
  final brightness = dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'JetBrainsMono',
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.border,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
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
      surfaceContainerHighest: c.surfaceAlt,
      outline: c.outline,
      outlineVariant: c.border,
    ),
    textTheme: (dark ? Typography.whiteMountainView : Typography.blackMountainView).apply(
      bodyColor: c.text,
      displayColor: c.text,
      fontFamily: 'JetBrainsMono',
    ),
    iconTheme: IconThemeData(color: c.textMuted, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Titles start right after the back arrow on every page.
      titleSpacing: 0,
      titleTextStyle: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'JetBrainsMono'),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceAlt,
      contentTextStyle: TextStyle(color: c.text, fontFamily: 'JetBrainsMono', fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.textMuted, textColor: c.text),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.bg : c.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.surfaceAlt),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.3),
      selectionHandleColor: c.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      hintStyle: TextStyle(color: c.textMuted),
      // A visible edge identifies the field (WCAG 1.4.11); focus thickens it.
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.danger)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    // One button shape everywhere: 10px corners, 44px tall.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.bg,
        disabledBackgroundColor: c.surfaceAlt,
        disabledForegroundColor: c.textMuted,
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        disabledForegroundColor: c.textMuted,
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: c.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.bg,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.outline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: c.text, fontSize: 13, fontFamily: 'JetBrainsMono'),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}
