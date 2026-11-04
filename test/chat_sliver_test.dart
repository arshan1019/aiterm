import 'package:aiterm/agents/blocks/chat_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A chat, newest first in [rows] (id, height), in a 400-high window.
  Widget chat(ScrollController scroll, List<(String, double)> rows, {bool dragging = false, VoidCallback? onTap}) {
    final ids = [for (final (id, _) in rows) id];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 400,
          child: CustomScrollView(
            controller: scroll,
            reverse: true,
            slivers: [
              ChatSliver(
                dragging: () => dragging,
                glide: true,
                delegate: SliverChildBuilderDelegate(
                  childCount: rows.length,
                  findChildIndexCallback: (key) {
                    final i = ids.indexOf((key as ValueKey).value as String);
                    return i < 0 ? null : i;
                  },
                  (context, i) => GestureDetector(
                    key: ValueKey(rows[i].$1),
                    onTap: onTap,
                    child: SizedBox(height: rows[i].$2, child: Text(rows[i].$1)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, double)> rows(int count, {double newest = 100}) => [
    for (var i = 0; i < count; i++) ('r$i', i == 0 ? newest : 100),
  ];

  double y(WidgetTester tester, String id) => tester.getTopLeft(find.text(id)).dy;

  testWidgets('reading further up, rows stay put as the newest grows or arrives', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(chat(scroll, rows(20)));
    scroll.jumpTo(150);
    await tester.pump();
    final before = y(tester, 'r4');

    // In the same frame, not a frame late.
    await tester.pumpWidget(chat(scroll, rows(20, newest: 140)));
    expect(y(tester, 'r4'), before);
    expect(scroll.position.pixels, 190);

    await tester.pumpWidget(chat(scroll, [('new', 60), ...rows(20, newest: 140)]));
    expect(y(tester, 'r4'), before);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('growth below keeps a drag going', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(chat(scroll, rows(20)));
    scroll.jumpTo(150);
    await tester.pump();
    final before = y(tester, 'r4');
    final finger = await tester.startGesture(const Offset(100, 200));
    await finger.moveBy(const Offset(0, 40));
    await tester.pump();
    await finger.moveBy(const Offset(0, 40));
    await tester.pump();
    final dragged = y(tester, 'r4');
    expect(dragged, greaterThan(before));

    await tester.pumpWidget(chat(scroll, rows(20, newest: 140), dragging: true));
    expect(y(tester, 'r4'), dragged);
    await finger.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(y(tester, 'r4'), dragged + 30, reason: 'the finger still moves the list');
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('at the latest, rows glide up instead of jumping', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(chat(scroll, rows(20)));
    final before = y(tester, 'r1');

    await tester.pumpWidget(chat(scroll, rows(20, newest: 124)));
    expect(y(tester, 'r1'), before, reason: 'no jump in the frame the line appears');
    expect(scroll.position.pixels, 0, reason: 'still following');

    var last = before;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = y(tester, 'r1');
      expect(now, lessThanOrEqualTo(last));
      expect(last - now, lessThan(8), reason: 'a small step each frame');
      last = now;
    }
    expect(last, lessThan(before));
    await tester.pumpAndSettle();
    expect(y(tester, 'r1'), before - 24);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('rows can be tapped where they show during a glide', (tester) async {
    final scroll = ScrollController();
    var taps = 0;
    await tester.pumpWidget(chat(scroll, rows(3), onTap: () => taps++));
    await tester.pumpWidget(chat(scroll, rows(3, newest: 140), onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(tester.getCenter(find.text('r2')));
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
