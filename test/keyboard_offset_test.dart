import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/shared/settled_size.dart';

void main() {
  const lh = 20.0; // line height
  const settled = 600.0; // 30 rows

  double off(double available, {required int cursorRow, int scrollback = 0}) => keyboardOffset(
        settledHeight: settled,
        availableHeight: available,
        lineHeight: lh,
        cursorRow: cursorRow,
        scrollbackLines: scrollback,
      );

  group('keyboard opening (less room)', () {
    test('content near the top does not move at all', () {
      expect(off(360, cursorRow: 2), 0);
    });

    test('a cursor near the bottom is lifted just enough, in whole rows', () {
      // Cursor on row 29 (bottom). 360 px = 18 rows visible: lift by 12 rows.
      expect(off(360, cursorRow: 29), -12 * lh);
      // Mid-animation, 590 px: 29 full rows fit, so lift by one row.
      expect(off(590, cursorRow: 29), -1 * lh);
    });

    test('matches what xterm does after resizing', () {
      // xterm on shrink keeps the cursor visible: shift = cursor+1-newRows.
      for (final avail in [599.0, 500.0, 421.0, 360.0, 200.0]) {
        for (final cursor in [0, 5, 17, 29]) {
          final newRows = (avail / lh).floor();
          final xtermShift = (cursor + 1 - newRows).clamp(0, 1000);
          expect(off(avail, cursorRow: cursor), -xtermShift * lh, reason: 'avail $avail cursor $cursor');
        }
      }
    });
  });

  group('keyboard closing (more room)', () {
    test('with scrollback, content moves down as rows are pulled back in', () {
      // 600 → 800 px: 10 more rows, 100 lines of scrollback.
      expect(off(800, cursorRow: 29, scrollback: 100), 10 * lh);
    });

    test('without scrollback, content stays at the top', () {
      expect(off(800, cursorRow: 5, scrollback: 0), 0);
    });

    test('limited scrollback pulls only what exists', () {
      expect(off(800, cursorRow: 29, scrollback: 3), 3 * lh);
    });
  });
}
