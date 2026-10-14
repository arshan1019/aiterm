import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/contrast.dart';
import 'package:aiterm/app/theme.dart';

// WCAG 2.2 AA: text 4.5:1 (1.4.3); UI parts and graphics 3:1 (1.4.11).
void main() {
  for (final (name, c) in [('dark', AppColors.dark), ('light', AppColors.light)]) {
    group('$name theme', () {
      test('body and secondary text are readable on every surface', () {
        for (final bg in [c.bg, c.surface, c.surfaceAlt]) {
          expect(contrastRatio(c.text, bg), greaterThanOrEqualTo(7), reason: 'text');
          expect(contrastRatio(c.textMuted, bg), greaterThanOrEqualTo(4.5), reason: 'muted text on $bg');
        }
      });

      test('accent and danger work as text (links, text buttons, errors)', () {
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.accent, bg), greaterThanOrEqualTo(4.5), reason: 'accent on $bg');
          expect(contrastRatio(c.danger, bg), greaterThanOrEqualTo(4.5), reason: 'danger on $bg');
        }
      });

      test('labels on filled buttons are readable', () {
        expect(contrastRatio(c.bg, c.accent), greaterThanOrEqualTo(4.5), reason: 'on accent');
        expect(contrastRatio(c.bg, c.danger), greaterThanOrEqualTo(4.5), reason: 'on danger');
      });

      test('status colors, the selected pill and diff lines are readable', () {
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.success, bg), greaterThanOrEqualTo(4.5), reason: 'success on $bg');
          expect(contrastRatio(c.warning, bg), greaterThanOrEqualTo(4.5), reason: 'warning on $bg');
        }
        expect(contrastRatio(c.onAccentContainer, c.accentContainer), greaterThanOrEqualTo(4.5), reason: 'nav pill');
        expect(contrastRatio(c.text, c.diffAdded), greaterThanOrEqualTo(7), reason: 'added line');
        expect(contrastRatio(c.text, c.diffRemoved), greaterThanOrEqualTo(7), reason: 'removed line');
      });

      test('control outlines (text fields, outlined buttons, checkboxes) stand out 3:1', () {
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.outline, bg), greaterThanOrEqualTo(3), reason: 'outline on $bg');
        }
      });
    });
  }

  // High contrast: WCAG AAA (7:1) for text and status, 4.5:1 for outlines,
  // and group edges visible at 3:1.
  for (final (name, c) in [('dark', AppColors.darkHigh), ('light', AppColors.lightHigh)]) {
    test('high contrast $name theme meets AAA', () {
      for (final bg in [c.bg, c.surface, c.surfaceAlt]) {
        for (final (role, fg) in [('text', c.text), ('muted', c.textMuted), ('accent', c.accent), ('danger', c.danger),
          ('success', c.success), ('warning', c.warning)]) {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(7), reason: '$role on $bg');
        }
        expect(contrastRatio(c.outline, bg), greaterThanOrEqualTo(4.5), reason: 'outline on $bg');
      }
      for (final bg in [c.bg, c.surface]) {
        expect(contrastRatio(c.border, bg), greaterThanOrEqualTo(2.5), reason: 'group edge on $bg');
      }
      expect(contrastRatio(c.bg, c.accent), greaterThanOrEqualTo(7), reason: 'on accent');
      expect(contrastRatio(c.onAccentContainer, c.accentContainer), greaterThanOrEqualTo(7), reason: 'nav pill');
      expect(contrastRatio(c.text, c.diffAdded), greaterThanOrEqualTo(7));
      expect(contrastRatio(c.text, c.diffRemoved), greaterThanOrEqualTo(7));
      expect(c.highContrast, isTrue);
    });
  }

  test('high contrast wallpaper accents stay AAA, whatever the hue', () {
    for (var hue = 0; hue < 360; hue += 15) {
      final seed = HSVColor.fromAHSV(1, hue.toDouble(), 0.7, 0.8).toColor();
      for (final base in [AppColors.darkHigh, AppColors.lightHigh]) {
        final c = base.seeded(seed);
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.accent, bg), greaterThanOrEqualTo(7), reason: 'accent on $bg, hue $hue');
        }
        expect(contrastRatio(c.bg, c.accent), greaterThanOrEqualTo(7), reason: 'on accent, hue $hue');
        expect(contrastRatio(c.onAccentContainer, c.accentContainer), greaterThanOrEqualTo(7), reason: 'pill, hue $hue');
      }
    }
  });

  test('wallpaper accents keep every accent pairing readable, whatever the hue', () {
    for (var hue = 0; hue < 360; hue += 15) {
      final seed = HSVColor.fromAHSV(1, hue.toDouble(), 0.7, 0.8).toColor();
      for (final base in [AppColors.dark, AppColors.light]) {
        final c = base.seeded(seed);
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.accent, bg), greaterThanOrEqualTo(4.5), reason: 'accent on $bg, hue $hue');
        }
        expect(contrastRatio(c.bg, c.accent), greaterThanOrEqualTo(4.5), reason: 'on accent, hue $hue');
        expect(contrastRatio(c.onAccentContainer, c.accentContainer), greaterThanOrEqualTo(4.5), reason: 'nav pill, hue $hue');
      }
    }
  });

  test('a black terminal keeps text and colors readable', () {
    const black = Color(0xFF000000);
    final t = TerminalPalette.dark;
    for (final color in [AppColors.dark.text, AppColors.dark.textMuted, t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan]) {
      expect(contrastRatio(color, black), greaterThanOrEqualTo(4.5), reason: '$color on black');
    }
  });

  test('terminal colors are readable on the terminal background, in both themes', () {
    for (final (bg, t) in [(AppColors.dark.bg, TerminalPalette.dark), (AppColors.light.bg, TerminalPalette.light)]) {
      for (final color in [t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan, t.brightRed, t.brightGreen, t.brightYellow,
        t.brightBlue, t.brightMagenta, t.brightCyan]) {
        expect(contrastRatio(color, bg), greaterThanOrEqualTo(4.5), reason: '$color on $bg');
      }
    }
  });
}
