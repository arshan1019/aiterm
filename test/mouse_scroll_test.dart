import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Scrolling in full-screen programs (Claude Code, less, vim with mouse):
/// they turn on mouse reporting and scroll on wheel events, so a swipe must
/// arrive as a correctly encoded wheel.
void main() {
  (Terminal, List<String>) terminal(String setup) {
    final t = Terminal()..resize(44, 18);
    final out = <String>[];
    t.onOutput = out.add;
    t.write(setup);
    out.clear();
    return (t, out);
  }

  String wheel(Terminal t, List<String> out, TerminalMouseButton b, [CellOffset at = const CellOffset(5, 6)]) {
    out.clear();
    t.mouseInput(b, TerminalMouseButtonState.down, at);
    return out.join();
  }

  group('wheel encoding', () {
    test('SGR: wheel up/down/left/right are buttons 64/65/66/67', () {
      final (t, out) = terminal('\x1b[?1049h\x1b[?1000h\x1b[?1006h');
      expect(wheel(t, out, TerminalMouseButton.wheelUp), '\x1b[<64;6;7M');
      expect(wheel(t, out, TerminalMouseButton.wheelDown), '\x1b[<65;6;7M');
      expect(wheel(t, out, TerminalMouseButton.wheelLeft), '\x1b[<66;6;7M');
      expect(wheel(t, out, TerminalMouseButton.wheelRight), '\x1b[<67;6;7M');
    });

    test('X10/normal encoding: button + 32, 1-based column and row + 32', () {
      final (t, out) = terminal('\x1b[?1049h\x1b[?1000h');
      expect(wheel(t, out, TerminalMouseButton.wheelUp), '\x1b[M${String.fromCharCodes([32 + 64, 32 + 6, 32 + 7])}');
      out.clear();
      t.mouseInput(TerminalMouseButton.left, TerminalMouseButtonState.down, const CellOffset(0, 0));
      expect(out.join(), '\x1b[M${String.fromCharCodes([32, 33, 33])}', reason: 'top-left cell is 1;1');
    });

    test("Claude Code's own session gets proper wheel events", () {
      final session = utf8.decode(File('test/fixtures/claude_code_session.bin').readAsBytesSync(), allowMalformed: true);
      final (t, out) = terminal(session);
      expect(t.isUsingAltBuffer, isTrue);
      expect(wheel(t, out, TerminalMouseButton.wheelUp), startsWith('\x1b[<64;'));
      expect(wheel(t, out, TerminalMouseButton.wheelDown), startsWith('\x1b[<65;'));
    });
  });

  testWidgets('swiping a full-screen program sends wheel events in the right direction', (tester) async {
    final (t, out) = terminal('\x1b[?1049h\x1b[?1000h\x1b[?1006h');
    await tester.pumpWidget(MaterialApp(home: SizedBox(width: 400, height: 600, child: TerminalView(t))));
    await tester.pump();

    // Finger moves down: look back at earlier content = wheel up.
    out.clear();
    await tester.drag(find.byType(TerminalView), const Offset(0, 120));
    await tester.pumpAndSettle();
    final ups = out.join();
    expect(ups, contains('\x1b[<64;'));
    expect(ups, isNot(contains('\x1b[<65;')));

    out.clear();
    await tester.drag(find.byType(TerminalView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(out.join(), contains('\x1b[<65;'));
  });
}
