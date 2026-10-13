import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/preview/ports.dart';

void main() {
  group('portsMentionedIn', () {
    test('dev-server banners', () {
      expect(portsMentionedIn('  ➜  Local:   http://localhost:5173/\n'), {5173});
      expect(portsMentionedIn('ready - started server on 0.0.0.0:3000, url: http://localhost:3000'), {3000});
      expect(portsMentionedIn('Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...'), {8000});
      expect(portsMentionedIn('Server listening on port 4000'), {4000});
      expect(portsMentionedIn('Running on http://127.0.0.1:5000'), {5000});
      expect(portsMentionedIn('App running at http://[::1]:8081/'), {8081});
    });

    test('ignores colours, remote hosts and nonsense ports', () {
      expect(portsMentionedIn('\x1b[36mhttp://localhost:\x1b[1m5173\x1b[22m/\x1b[39m'), {5173});
      expect(portsMentionedIn('see https://github.com:443/x and http://example.com:8080'), isEmpty);
      expect(portsMentionedIn('port 99999 and port 0'), isEmpty);
      expect(portsMentionedIn('12:30:45 build ok'), isEmpty);
    });
  });

  group('PortWatcher', () {
    late Set<int> open;
    late PortWatcher w;
    late List<int> appeared;

    setUp(() {
      open = {};
      appeared = [];
      w = PortWatcher(probe: (p) async => open.contains(p), onAppeared: appeared.add);
    });

    test('reports a port once when it starts listening, and drops it when it stops', () async {
      w.hint({5173});
      await w.check();
      expect(w.live, isEmpty);
      open.add(5173);
      await w.check();
      await w.check();
      expect(w.live, {5173});
      expect(appeared, [5173]);
      open.clear();
      await w.check();
      expect(w.live, isEmpty);
      open.add(5173);
      await w.check();
      expect(appeared, [5173, 5173]); // came back: announce again
    });

    test('common dev ports are checked without hints', () async {
      open.add(3000);
      await w.check();
      expect(w.live, {3000});
    });

    test('ports that were already open before watching are not announced', () async {
      open.add(8080);
      final quiet = PortWatcher(probe: (p) async => open.contains(p), onAppeared: appeared.add);
      await quiet.check(announce: false); // baseline
      await quiet.check();
      expect(quiet.live, {8080});
      expect(appeared, isEmpty);
    });
  });
}
