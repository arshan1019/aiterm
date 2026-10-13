import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/preview/preview_controller.dart';

void main() {
  test('a newly opened port is announced until dismissed or opened', () async {
    final open = <int>{};
    final c = PreviewController(probe: (p) async => open.contains(p));
    await c.start(); // baseline: nothing announced
    c.portsMentioned({5173});
    open.add(5173);
    await c.checkNow();
    expect(c.announced, 5173);
    expect(c.livePorts, [5173]);
    c.dismiss();
    expect(c.announced, isNull);
    expect(c.livePorts, [5173]); // still listed, just not announced
    c.stop();
  });

  test('the announcement goes away when the server stops', () async {
    final open = {8000};
    final c = PreviewController(probe: (p) async => open.contains(p));
    await c.start();
    open.clear();
    await c.checkNow();
    open.add(8000);
    await c.checkNow();
    expect(c.announced, 8000);
    open.clear();
    await c.checkNow();
    expect(c.announced, isNull);
    c.stop();
  });

  test('preview url', () {
    expect(previewUrl(5173), Uri.parse('http://127.0.0.1:5173/'));
  });
}
