import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/linux/session_spec.dart';
import 'package:aiterm/platform/pty.dart';
import 'package:aiterm/terminal/terminal_session.dart';
import 'package:aiterm/terminal/terminal_tabs.dart';

class FakePty implements PtySession {
  FakePty(this.id);
  @override
  final int id;
  final out = StreamController<Uint8List>(sync: true);
  final exit = Completer<int>();
  final written = <String>[];
  bool stopped = false;

  @override
  Stream<Uint8List> get output => out.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(String data) => written.add(data);
  @override
  void resize(int rows, int cols) {}
  @override
  void stop() => stopped = true;
}

class FakeBackend implements PtyBackend {
  final live = <int, (FakePty, String)>{}; // id → session, replay text
  final started = <FakePty>[];
  var nextId = 100;

  @override
  Future<PtySession> start({required List<String> argv, required Map<String, String> env, required String cwd, required int rows, required int cols}) async {
    final p = FakePty(nextId++);
    started.add(p);
    return p;
  }

  @override
  Future<List<int>> liveSessions() async => live.keys.toList();

  @override
  Future<PtyAttachment?> attach(int id) async {
    final l = live[id];
    return l == null ? null : PtyAttachment(l.$1, Uint8List.fromList(utf8.encode(l.$2)));
  }
}

Future<SessionSpec> spec(String? cwd) async => const SessionSpec(['/bin/sh'], {}, '/');

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('aiterm_reattach'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a running session saves its PTY id', () async {
    final backend = FakeBackend();
    final tabs = TerminalTabs(dir.path, backend: backend);
    await tabs.load();
    await tabs.active.start(spec, alpine: true);
    await tabs.save();
    final saved = jsonDecode(File('${dir.path}/terminal_tabs.json').readAsStringSync());
    expect(saved['tabs'][0]['pty'], 100);
    tabs.dispose();
  });

  test('tabs whose shell is still alive reattach and replay recent output', () async {
    File('${dir.path}/terminal_tabs.json').writeAsStringSync(jsonEncode({
      'version': 2,
      'active': 0,
      'tabs': [
        {'title': 'live', 'pty': 7, 'scrollback': 'stale text'},
        {'title': 'dead', 'pty': 8, 'scrollback': 'old output'},
      ],
    }));
    final backend = FakeBackend()..live[7] = (FakePty(7), 'recent \x1b[32mgreen\x1b[0m output\r\n');
    final tabs = TerminalTabs(dir.path, backend: backend);
    await tabs.load();
    await tabs.reattach();

    final live = tabs.tabs[0], dead = tabs.tabs[1];
    expect(live.state.value, SessionState.running);
    expect(live.scrollbackText(), 'recent green output'); // replay, not the stale save
    expect(dead.state.value, SessionState.idle); // starts normally later
    expect(dead.restoredScrollback, 'old output');

    // Output keeps flowing into the reattached tab.
    backend.live[7]!.$1.out.add(Uint8List.fromList(utf8.encode('more\r\n')));
    expect(live.lastOutputLine(), 'more');
    // Typing goes to the existing shell.
    live.terminal.textInput('ls\r');
    expect(backend.live[7]!.$1.written, ['ls\r']);
    tabs.dispose();
  });

  test('closing a tab stops its shell; disposing the app does not', () async {
    final backend = FakeBackend();
    final tabs = TerminalTabs(dir.path, backend: backend);
    await tabs.load();
    final first = tabs.active;
    await first.start(spec, alpine: true);
    final second = tabs.open();
    await second.start(spec, alpine: true);
    tabs.close(first);
    expect(backend.started[0].stopped, isTrue);
    tabs.dispose(); // the UI going away must leave shells to the service
    expect(backend.started[1].stopped, isFalse);
  });
}
