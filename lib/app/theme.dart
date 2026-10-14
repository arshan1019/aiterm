import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'icons.dart';

/// The palette (docs/DESIGN.md, "Color"), generated in OKLCH from three
/// inputs: the accent hue (teal, 172°), neutrals tinted toward it (190°,
/// chroma ≤ 0.012) and the contrast level. Every token has one job; the
/// accent is rationed to the primary action, focus, the cursor and
/// selection, the selected navigation item and a working agent. Success is
/// its own green, never the accent. Contrast is enforced by
/// test/contrast_test.dart.
///
/// As a [ThemeExtension] it interpolates, so switching light/dark
/// cross-fades every color instead of snapping.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// The app background and the terminal.
  final Color bg;

  /// One tone step up: grouped rows, cards.
  final Color surface;

  /// Another step: input fills, blocks, pressed rows.
  final Color surfaceAlt;

  /// Decorative edges: dividers, hairlines.
  final Color border;

  /// Edges that identify a control (text fields, outlined buttons,
  /// checkboxes): 3:1 against the surfaces, as WCAG 1.4.11 asks.
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color accent;

  /// Selected pills (the navigation indicator) and what's on them.
  final Color accentContainer;
  final Color onAccentContainer;
  final Color danger;

  /// Done, added lines, a clean tree: never the accent.
  final Color success;
  final Color warning;

  /// Diff line backgrounds.
  final Color diffAdded;
  final Color diffRemoved;

  /// High contrast: text and status colors at 7:1, control outlines at
  /// 4.5:1, and groups get a visible edge instead of a tone step.
  final bool highContrast;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.danger,
    required this.success,
    required this.warning,
    required this.diffAdded,
    required this.diffRemoved,
    this.highContrast = false,
  });

  /// "Phosphor graphite": a near-black tinted toward the accent.
  static const dark = AppColors(
    bg: Color(0xFF0B0F0F),
    surface: Color(0xFF111616),
    surfaceAlt: Color(0xFF171C1C),
    border: Color(0xFF282F2F),
    outline: Color(0xFF6D7776),
    text: Color(0xFFE6EBEA),
    textMuted: Color(0xFF9EA7A6),
    accent: Color(0xFF5CC8A9),
    accentContainer: Color(0xFF12352B),
    onAccentContainer: Color(0xFF9AE3CB),
    danger: Color(0xFFED756A),
    success: Color(0xFF7BC772),
    warning: Color(0xFFEEB154),
    diffAdded: Color(0xFF182917),
    diffRemoved: Color(0xFF391917),
  );

  /// High contrast on dark (WCAG AAA text).
  static const darkHigh = AppColors(
    bg: Color(0xFF0B0F0F),
    surface: Color(0xFF111616),
    surfaceAlt: Color(0xFF171C1C),
    border: Color(0xFF5B6564),
    outline: Color(0xFF9AA4A3),
    text: Color(0xFFF2F5F5),
    textMuted: Color(0xFFC5CDCC),
    accent: Color(0xFF7ADDC0),
    accentContainer: Color(0xFF0D2B22),
    onAccentContainer: Color(0xFFB4F0DD),
    danger: Color(0xFFFF9A90),
    success: Color(0xFF98DB8F),
    warning: Color(0xFFF5C878),
    diffAdded: Color(0xFF15261A),
    diffRemoved: Color(0xFF331616),
    highContrast: true,
  );

  /// High contrast on light (WCAG AAA text).
  static const lightHigh = AppColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF2F1),
    border: Color(0xFF8E9998),
    outline: Color(0xFF56615F),
    text: Color(0xFF0A1010),
    textMuted: Color(0xFF37413F),
    accent: Color(0xFF005440),
    accentContainer: Color(0xFFC9EDE0),
    onAccentContainer: Color(0xFF002A1F),
    danger: Color(0xFF8E1F1A),
    success: Color(0xFF1B5A22),
    warning: Color(0xFF6E4306),
    diffAdded: Color(0xFFD9F4D8),
    diffRemoved: Color(0xFFFBE3E1),
    highContrast: true,
  );

  static const light = AppColors(
    bg: Color(0xFFF7FAF9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F3F3),
    border: Color(0xFFDEE3E3),
    outline: Color(0xFF7E8988),
    text: Color(0xFF181E1E),
    textMuted: Color(0xFF5C6665),
    accent: Color(0xFF08745D),
    accentContainer: Color(0xFFD2F0E5),
    onAccentContainer: Color(0xFF033D2F),
    danger: Color(0xFFBA3630),
    success: Color(0xFF2E7C35),
    warning: Color(0xFFA46311),
    diffAdded: Color(0xFFDFF6DE),
    diffRemoved: Color(0xFFFCEAE8),
  );

  @override
  AppColors copyWith({Color? bg, Color? surface, Color? surfaceAlt, Color? border, Color? outline, Color? text, Color? textMuted, Color? accent, Color? accentContainer, Color? onAccentContainer, Color? danger, Color? success, Color? warning, Color? diffAdded, Color? diffRemoved}) => AppColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        outline: outline ?? this.outline,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accentContainer: accentContainer ?? this.accentContainer,
        onAccentContainer: onAccentContainer ?? this.onAccentContainer,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        diffAdded: diffAdded ?? this.diffAdded,
        diffRemoved: diffRemoved ?? this.diffRemoved,
        highContrast: highContrast,
      );

  /// These colors with the accent roles taken from [seed] (the wallpaper's
  /// color): its hue at the tones and chroma the built-in teal uses, so
  /// every contrast pairing holds whatever the wallpaper.
  AppColors seeded(Color seed) {
    final dark = bg.computeLuminance() < 0.5;
    final palette = TonalPalette.of(Hct.fromInt(seed.toARGB32()).hue, 36);
    Color tone(int t) => Color(palette.get(t));
    return copyWith(
      accent: tone(switch ((dark, highContrast)) { (true, false) => 76, (false, false) => 42, (true, true) => 84, (false, true) => 30 }),
      accentContainer: tone(switch ((dark, highContrast)) { (true, false) => 20, (false, false) => 92, (true, true) => 15, (false, true) => 92 }),
      onAccentContainer: tone(switch ((dark, highContrast)) { (true, false) => 86, (false, false) => 20, (true, true) => 92, (false, true) => 10 }),
    );
  }

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
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      danger: l(danger, other.danger),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      diffAdded: l(diffAdded, other.diffAdded),
      diffRemoved: l(diffRemoved, other.diffRemoved),
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }

  List<Color> get _all => [
        bg, surface, surfaceAlt, border, outline, text, textMuted, accent, accentContainer, onAccentContainer, danger,
        success, warning, diffAdded, diffRemoved,
      ];

  @override
  bool operator ==(Object other) {
    if (other is! AppColors || other.highContrast != highContrast) return false;
    final a = _all, b = other._all;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_all);
}

/// The terminal's ANSI colors, from the same OKLCH generator (normal at
/// L 72%, bright at L 84% in dark; L 50% / 42% in light), all ≥ 5:1 on bg,
/// so the terminal doesn't look pasted into the app.
class TerminalPalette {
  const TerminalPalette({
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
  });

  final Color red, green, yellow, blue, magenta, cyan;
  final Color brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan;

  static const dark = TerminalPalette(
    red: Color(0xFFE6867B),
    green: Color(0xFF77B870),
    yellow: Color(0xFFC2A140),
    blue: Color(0xFF6FA7EE),
    magenta: Color(0xFFCF88C8),
    cyan: Color(0xFF16BBBC),
    brightRed: Color(0xFFFFB4AB),
    brightGreen: Color(0xFFA9DAA4),
    brightYellow: Color(0xFFE1C885),
    brightBlue: Color(0xFFA3CEFF),
    brightMagenta: Color(0xFFEDB6E7),
    brightCyan: Color(0xFF7FDDDD),
  );

  static const light = TerminalPalette(
    red: Color(0xFFA04038),
    green: Color(0xFF30752A),
    yellow: Color(0xFF805E00),
    blue: Color(0xFF2863AB),
    magenta: Color(0xFF8B4486),
    cyan: Color(0xFF00787A),
    brightRed: Color(0xFF822C27),
    brightGreen: Color(0xFF1D5C17),
    brightYellow: Color(0xFF664800),
    brightBlue: Color(0xFF154D8C),
    brightMagenta: Color(0xFF70306C),
    brightCyan: Color(0xFF005F61),
  );

  static TerminalPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Shared animation timing, so every transition in the app feels related.
/// With the system's "Remove animations" setting on ([reduced], from
/// MediaQuery.disableAnimations), the app's own transitions are instant.
abstract final class Motion {
  static bool reduced = false;

  /// State changes on a control (pressed, toggled, selected).
  static Duration get quick => reduced ? Duration.zero : const Duration(milliseconds: 120);

  /// Things appearing, moving or switching.
  static Duration get standard => reduced ? Duration.zero : const Duration(milliseconds: 220);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.easeInOutCubic;
}

extension ThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Two voices (docs/DESIGN.md): the app speaks in a sans; anything literal,
/// that could be pasted into a shell (paths, branches, hashes, commands,
/// code, logs), is mono. Mono is information here, never decoration.
abstract final class AppFonts {
  static const sans = 'IBMPlexSans';
  static const mono = 'JetBrainsMono';
}

/// Machine text inside UI: paths, branches, hashes, commands (13/20 mono,
/// tabular figures). [size] for the occasional larger code (a sign-in code).
TextStyle codeStyle(Color color, {double size = 13, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: size,
      height: size <= 13 ? 20 / 13 : 1.3,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A card or group's shape: tone alone sets it apart, plus an edge in high
/// contrast.
ShapeBorder cardShape(AppColors c, {double radius = Radii.large}) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: c.highContrast ? BorderSide(color: c.border) : BorderSide.none,
    );

/// Radii: four values plus full (M3 shape tokens), nested concentrically.
abstract final class Radii {
  static const small = 4.0; // checkboxes, inline code, diff hunks
  static const medium = 8.0; // buttons, inputs, chips, selected rows
  static const large = 12.0; // cards, blocks, menus, snackbars
  static const sheet = 20.0; // sheet top corners, dialogs
}

/// The type ramp (M3's sizes; every line height a multiple of 4; weights
/// 400/500/600 only; no letter-spacing).
TextTheme _textTheme(AppColors c) {
  TextStyle t(double size, double line, FontWeight w, [Color? color]) => TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: size,
        height: line / size,
        fontWeight: w,
        letterSpacing: 0,
        color: color ?? c.text,
      );
  return TextTheme(
    headlineSmall: t(24, 32, FontWeight.w600),
    titleLarge: t(22, 28, FontWeight.w600),
    titleMedium: t(16, 24, FontWeight.w600),
    titleSmall: t(14, 20, FontWeight.w600),
    bodyLarge: t(16, 24, FontWeight.w400),
    bodyMedium: t(14, 20, FontWeight.w400),
    bodySmall: t(12, 16, FontWeight.w400, c.textMuted),
    labelLarge: t(14, 20, FontWeight.w500),
    labelMedium: t(12, 16, FontWeight.w500),
    labelSmall: t(11, 16, FontWeight.w500),
  );
}

/// The app's theme. [seed] replaces the teal accent (Wallpaper colors);
/// [compact] shortens list rows to 48/64dp (hit areas stay ≥ 48dp);
/// [highContrast] uses the AAA palettes.
ThemeData buildTheme({required bool dark, Color? seed, bool compact = false, bool highContrast = false}) {
  final base = switch ((dark, highContrast)) {
    (true, false) => AppColors.dark,
    (false, false) => AppColors.light,
    (true, true) => AppColors.darkHigh,
    (false, true) => AppColors.lightHigh,
  };
  final c = seed == null ? base : base.seeded(seed);
  final brightness = dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: AppFonts.sans,
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
    textTheme: _textTheme(c),
    // Material Symbols' axes: regular weight, outlined (fill is for
    // selection and status), slightly lighter grade on dark so light-on-
    // dark strokes don't bloom.
    iconTheme: IconThemeData(color: c.textMuted, size: 20, fill: 0, weight: 400, grade: dark ? -25 : 0, opticalSize: 20),
    // Back and close buttons in the same icon set as everything else.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(AppIcons.arrowBack, size: 24, opticalSize: 24),
      closeButtonIconBuilder: (_) => const Icon(AppIcons.close, size: 24, opticalSize: 24),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Titles start right after the back arrow on every page.
      titleSpacing: 0,
      titleTextStyle: _textTheme(c).titleMedium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: true,
      dragHandleColor: c.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.large), side: BorderSide(color: c.border)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceAlt,
      contentTextStyle: _textTheme(c).bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.large)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.textMuted,
      textColor: c.text,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    ),
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.medium), borderSide: BorderSide(color: c.danger)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    // One button shape everywhere: 10px corners, 44px tall.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.bg,
        disabledBackgroundColor: c.surfaceAlt,
        disabledForegroundColor: c.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        disabledForegroundColor: c.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: c.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
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
    // Bottom navigation: the selected destination in the accent (icon on a
    // tinted pill, bold label), the rest muted; both pass contrast.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.onAccentContainer : c.textMuted, size: 24, opticalSize: 24),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => _textTheme(c).labelMedium!.copyWith(
          color: s.contains(WidgetState.selected) ? c.text : c.textMuted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.outline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.medium)),
      labelStyle: _textTheme(c).labelLarge,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
    ),
  );
}
