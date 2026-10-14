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

      test('control outlines (text fields, outlined buttons, checkboxes) stand out 3:1', () {
        for (final bg in [c.bg, c.surface]) {
          expect(contrastRatio(c.outline, bg), greaterThanOrEqualTo(3), reason: 'outline on $bg');
        }
      });
    });
  }
}
