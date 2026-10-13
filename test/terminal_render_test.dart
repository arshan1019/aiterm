import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
// ignore: implementation_imports
import 'package:xterm/src/ui/painter.dart' show TerminalPainter;

/// The terminal's line-picture cache (third_party/xterm, aiterm patch):
/// each line is recorded once and reused while scrolling.
void main() {
  group('line cache keys', () {
    BufferLine line(String seq) {
      final t = Terminal()..write(seq);
      return t.buffer.lines[0];
    }

    test('same content and attributes give the same key', () {
      expect(line('hello \x1b[31mred').contentKey(), line('hello \x1b[31mred').contentKey());
    });

    test('any change of text, colour or attribute changes the key', () {
      final base = line('hello').contentKey();
      expect(line('hellp').contentKey(), isNot(base));
      expect(line('\x1b[31mhello').contentKey(), isNot(base));
      expect(line('\x1b[4mhello').contentKey(), isNot(base));
      expect(line('\x1b[1mhello').contentKey(), isNot(base));
    });
  });

  group('rendering', () {
    final content = StringBuffer();
    for (var i = 0; i < 400; i++) {
      content.write('\x1b[3${i % 8}mline $i\x1b[0m  plain text with \x1b[4munderline\x1b[24m and \x1b[1mbold\x1b[22m ok\r\n');
    }

    Future<(Terminal, GlobalKey<TerminalViewState>, GlobalKey)> show(WidgetTester tester) async {
      final terminal = Terminal(maxLines: 1000)..write(content.toString());
      final viewKey = GlobalKey<TerminalViewState>();
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: RepaintBoundary(key: boundary, child: TerminalView(terminal, key: viewKey)),
        ),
      ));
      await tester.pump();
      return (terminal, viewKey, boundary);
    }

    Future<Uint8List> capture(WidgetTester tester, GlobalKey boundary) async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await render.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    testWidgets('cached lines draw exactly like uncached ones', (tester) async {
      TerminalPainter.lineCacheEnabled = false;
      final (_, _, b1) = await show(tester);
      final plain = await capture(tester, b1);

      TerminalPainter.lineCacheEnabled = true;
      await tester.pumpWidget(const SizedBox());
      final (_, _, b2) = await show(tester);
      final cached = await capture(tester, b2);
      // Draw again from the cache (second paint) and compare too.
      b2.currentContext!.findRenderObject()!.markNeedsPaint();
      await tester.pump();
      final cachedAgain = await capture(tester, b2);

      expect(cached, plain);
      expect(cachedAgain, plain);
    });

    testWidgets('scrolling is faster with the line cache', (tester) async {
      Future<Duration> scrollFrames(bool cache) async {
        TerminalPainter.lineCacheEnabled = cache;
        await tester.pumpWidget(const SizedBox());
        final (_, viewKey, _) = await show(tester);
        final scrollable = find.descendant(of: find.byKey(viewKey), matching: find.byType(Scrollable));
        final position = tester.state<ScrollableState>(scrollable.first).position;
        // Warm up, then time 120 scroll frames back and forth.
        for (var i = 0; i < 10; i++) {
          position.jumpTo(position.pixels - 7);
          await tester.pump();
        }
        final sw = Stopwatch()..start();
        for (var i = 0; i < 120; i++) {
          position.jumpTo(position.pixels + (i % 40 < 20 ? -9 : 9));
          await tester.pump();
        }
        return sw.elapsed;
      }

      final without = await scrollFrames(false);
      final withCache = await scrollFrames(true);
      // ignore: avoid_print
      print('scroll 120 frames: without cache ${without.inMilliseconds} ms, with cache ${withCache.inMilliseconds} ms');
      expect(withCache.inMicroseconds, lessThan(without.inMicroseconds * 0.8));
      TerminalPainter.lineCacheEnabled = true;
    });
  });
}
