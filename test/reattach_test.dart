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

  test('a tab opened with commands runs them once its shell starts', () async {
    final backend = FakeBackend();
    final tabs = TerminalTabs(dir.path, backend: backend);
    await tabs.load();
    final t = tabs.open(title: 'Claude Code', commands: ['claude']);
    expect(t.title, 'Claude Code');
    expect(tabs.active, t);
    await t.start(spec, alpine: true);
    expect(backend.started.single.written, ['claude\r']);
    await t.restart(spec, alpine: true); // a fresh shell runs it again
    expect(backend.started.last.written, ['claude\r']);
    tabs.dispose();
  });

  group('agent tabs belong to their project', () {
    test('project, agent and launch commands persist; a fresh shell runs the agent again', () async {
      final backend = FakeBackend();
      final tabs = TerminalTabs(dir.path, backend: backend);
      await tabs.load();
      final t = tabs.open(title: 'Claude Code · app', commands: ['claude'], cwd: '/root/app', project: '/root/app', agent: 'claude');
      expect(t.project, '/root/app');
      expect(t.agent, 'claude');
      await tabs.save();
      tabs.dispose();

      final again = TerminalTabs(dir.path, backend: backend);
      await again.load();
      final restored = again.tabs.last;
      expect(restored.project, '/root/app');
      expect(restored.agent, 'claude');
      await restored.start(spec, alpine: true);
      expect(backend.started.last.written, ['claude\r']);
      again.dispose();
    });

    test('a tab still running in the background reattaches without starting the agent twice', () async {
      final backend = FakeBackend();
      File('${dir.path}/terminal_tabs.json').writeAsStringSync(jsonEncode({
        'version': 2,
        'active': 0,
        'tabs': [
          {'title': 'Claude Code · app', 'pty': 7, 'cwd': '/root/app', 'project': '/root/app', 'agent': 'claude', 'launch': ['claude']},
        ],
      }));
      backend.live[7] = (FakePty(7), 'claude is here');
      final tabs = TerminalTabs(dir.path, backend: backend);
      await tabs.load();
      await tabs.reattach();
      await tabs.active.start(spec, alpine: true); // ignored: already running
      expect(backend.live[7]!.$1.written, isEmpty);
      tabs.dispose();
    });

    test('findAgent returns the tab for the same agent and project only', () async {
      final tabs = TerminalTabs(dir.path, backend: FakeBackend());
      await tabs.load();
      final a = tabs.open(title: 'Claude Code · app', commands: ['claude'], cwd: '/root/app', project: '/root/app', agent: 'claude');
      tabs.open(title: 'Codex CLI · app', commands: ['codex'], cwd: '/root/app', project: '/root/app', agent: 'codex');
      tabs.open(cwd: '/root/app');
      expect(tabs.findAgent('claude', '/root/app'), a);
      expect(tabs.findAgent('claude', '/root/other'), isNull);
      expect(tabs.findAgent('gemini', '/root/app'), isNull);
      tabs.dispose();
    });

    test('restarting an ended agent tab runs the agent again', () async {
      final backend = FakeBackend();
      final tabs = TerminalTabs(dir.path, backend: backend);
      await tabs.load();
      final t = tabs.open(title: 'Claude Code', commands: ['claude'], cwd: '/root/app', project: '/root/app', agent: 'claude');
      await t.start(spec, alpine: true);
      backend.started.last.exit.complete(0);
      await Future<void>.delayed(Duration.zero);
      expect(t.state.value, SessionState.exited);
      await t.restart(spec, alpine: true);
      expect(backend.started.last.written, ['claude\r']);
      tabs.dispose();
    });

    test('a process killed by Android (signal 9) is flagged, and cleared by the next command', () async {
      final backend = FakeBackend();
      final tabs = TerminalTabs(dir.path, backend: backend);
      await tabs.load();
      final t = tabs.active;
      await t.start(spec, alpine: true);
      final pty = backend.started.last;
      pty.out.add(Uint8List.fromList(utf8.encode('\x1b]133;A\x07')));
      t.terminal.textInput('claude\r');
      pty.out.add(Uint8List.fromList(utf8.encode('Killed\r\n\x1b]133;D;137\x07\x1b]133;A\x07')));
      expect(t.killed.value, isTrue);
      t.terminal.textInput('ls\r');
      expect(t.killed.value, isFalse);
      pty.exit.complete(137);
      await Future<void>.delayed(Duration.zero);
      expect(t.killed.value, isTrue);
      tabs.dispose();
    });
  });
}
