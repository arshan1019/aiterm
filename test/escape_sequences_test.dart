import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Text attributes after feeding escape sequences to the terminal engine.
/// "normal" (or whatever word is checked) must come out plain.
void main() {
  /// Flags of the cells of [word] on the first row that contains it.
  int flagsOf(Terminal t, String word) {
    final lines = t.buffer.lines;
    for (var y = 0; y < lines.length; y++) {
      final line = lines[y];
      final text = line.getText();
      final x = text.indexOf(word);
      if (x < 0) continue;
      final cell = CellData.empty();
      var flags = 0;
      for (var i = x; i < x + word.length; i++) {
        line.getCellData(i, cell);
        flags |= cell.flags;
      }
      return flags;
    }
    fail('"$word" not found in: ${t.buffer.lines[0].getText()}');
  }

  int run(String seq, [String word = 'normal']) {
    final t = Terminal();
    t.write(seq);
    return flagsOf(t, word);
  }

  bool underlined(String seq, [String word = 'normal']) => run(seq, word) & CellFlags.underline != 0;

  group('the reported cases: "normal" is not underlined', () {
    test('italic off (23)', () => expect(underlined('\x1b[3mitalic\x1b[23m normal\n'), isFalse));
    test('dim off (22)', () => expect(underlined('\x1b[2mdim\x1b[22m normal\n'), isFalse));
    test('underline off (24)', () => expect(underlined('\x1b[4munder\x1b[24m normal\n'), isFalse));
    test('bare reset (ESC [ m)', () => expect(underlined('\x1b[4munder\x1b[m normal\n'), isFalse));
    test('curly underline, then 4:0', () => expect(underlined('\x1b[4:3mcurly\x1b[4:0m normal\n'), isFalse));
    test('OSC 8 link ended with ST', () {
      expect(underlined('\x1b]8;;https://x.com\x1b\\link\x1b]8;;\x1b\\ normal\n'), isFalse);
    });
    test('OSC 8 link ended with BEL', () {
      expect(underlined('\x1b]8;;https://x.com\x07link\x1b]8;;\x07 normal\n'), isFalse);
    });
  });

  group('what the cases imply', () {
    test('curly underline (4:3) does underline, without other effects', () {
      expect(underlined('\x1b[4:3mcurly\n', 'curly'), isTrue);
      final t = Terminal()..write('\x1b[4:3mcurly\n');
      final cell = CellData.empty();
      t.buffer.lines[0].getCellData(0, cell);
      expect(cell.background, 0, reason: '4:3 must not be read as 43 (yellow background)');
    });

    test('the OSC 8 text itself is shown, the sequence is not', () {
      final t = Terminal()..write('\x1b]8;id=1;https://x.com\x1b\\link\x1b]8;;\x1b\\ normal');
      expect(t.buffer.lines[0].getText().trimRight(), 'link normal');
    });

    test('22 clears bold as well as dim', () {
      expect(run('\x1b[1mbold\x1b[22m normal\n') & CellFlags.bold, 0);
      expect(run('\x1b[2mdim\x1b[22m normal\n') & CellFlags.faint, 0);
    });

    test('23 and 27 clear only their own attribute', () {
      expect(run('\x1b[3;4mx\x1b[23m normal\n') & CellFlags.italic, 0);
      expect(run('\x1b[3;4mx\x1b[23m normal\n') & CellFlags.underline, isNot(0));
      expect(run('\x1b[7mx\x1b[27m normal\n') & CellFlags.inverse, 0);
    });

    test('empty parameters count as 0', () {
      expect(underlined('\x1b[4munder\x1b[;m normal\n'), isFalse);
      // ESC [ ; 4 m is "reset, then underline".
      expect(underlined('\x1b[1mx\x1b[;4m normal\n'), isTrue);
      expect(run('\x1b[1mx\x1b[;4m normal\n') & CellFlags.bold, 0);
    });
  });

  group('sequences that must not change attributes', () {
    test('modifyOtherKeys (CSI > 4 ; 1 m), sent by Claude Code and other TUIs', () {
      expect(underlined('\x1b[>4;1m normal\n'), isFalse);
      expect(run('\x1b[>4;1m normal\n') & CellFlags.bold, 0);
      expect(underlined('\x1b[>4;2m\x1b[>4m normal\n'), isFalse);
      expect(underlined('\x1b[?4m normal\n'), isFalse); // query form
    });

    test('underline colour (58) consumes its arguments', () {
      expect(underlined('\x1b[58;5;4m normal\n'), isFalse); // 4 is the colour, not underline
      expect(run('\x1b[58;5;4m normal\n') & CellFlags.blink, 0);
      expect(underlined('\x1b[58;2;1;4;9m normal\n'), isFalse);
      expect(underlined('\x1b[58:2::1:4:9m normal\n'), isFalse);
      expect(underlined('\x1b[58;5;4m\x1b[59m normal\n'), isFalse);
    });

    test('truncated 256/RGB colours do not break parsing', () {
      expect(underlined('\x1b[38;5m normal\n'), isFalse);
      expect(underlined('\x1b[48;2;1m normal\n'), isFalse);
      final t = Terminal()..write('\x1b[38;5mA\x1b[4mB\x1b[24m normal\n');
      expect(t.buffer.lines[0].getText().trimRight(), 'AB normal');
    });

    test('colon colours are understood', () {
      final t = Terminal()..write('\x1b[38:5:196mred\x1b[39m normal\n');
      final cell = CellData.empty();
      t.buffer.lines[0].getCellData(0, cell);
      expect(cell.foreground & 0xFF, 196);
      expect(flagsOf(t, 'normal') & CellFlags.underline, 0);
    });

    test('DCS, APC, PM and SOS strings are consumed, not printed', () {
      for (final intro in ['P', '_', '^', 'X']) {
        final t = Terminal()..write('a\x1b${intro}secret\x1b\\b normal');
        expect(t.buffer.lines[0].getText().trimRight(), 'ab normal', reason: 'ESC $intro');
        expect(flagsOf(t, 'normal') & CellFlags.underline, 0);
      }
    });

    test('a sequence split across writes still works', () {
      final t = Terminal()
        ..write('\x1b[4mx\x1b[2')
        ..write('4m normal\n');
      expect(flagsOf(t, 'normal') & CellFlags.underline, 0);
    });
  });
}
