import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/terminal/terminal_session.dart';
import 'package:aiterm/terminal/terminal_tabs.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('aiterm_tabs'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('scrollback snapshot', () {
    test('main-screen text, trailing blank lines dropped', () {
      final s = TerminalSession(id: 1, title: 't');
      s.terminal.write('one\r\n\x1b[32mtwo\x1b[0m\r\nthree\r\n');
      expect(s.scrollbackText(), 'one\ntwo\nthree');
      s.dispose();
    });

    test('keeps only the last lines', () {
      final s = TerminalSession(id: 1, title: 't');
      for (var i = 0; i < 50; i++) {
        s.terminal.write('line $i\r\n');
      }
      expect(s.scrollbackText(maxLines: 3).split('\n'), ['line 47', 'line 48', 'line 49']);
      s.dispose();
    });

    test('a full-screen app on the alternate screen is not saved', () {
      final s = TerminalSession(id: 1, title: 't');
      s.terminal.write('before\r\n\x1b[?1049hTUI STUFF');
      expect(s.scrollbackText(), 'before');
      s.dispose();
    });

    test('restored text shows before the new shell output', () {
      final s = TerminalSession(id: 1, title: 't', restoredScrollback: 'old one\nold two');
      s.showRestoredScrollback();
      final text = s.scrollbackText();
      expect(text, startsWith('old one\nold two'));
      expect(text, contains('restored'));
      s.dispose();
    });
  });

  group('TerminalTabs persistence', () {
    test('every tab comes back with title, pin, folder, scrollback and selection', () async {
      final tabs = TerminalTabs(dir.path);
      await tabs.load();
      final first = tabs.active..terminal.write('hello\r\n');
      first.cwd = '/root/app';
      first.rename('build');
      final second = tabs.open()..cwd = '/tmp';
      tabs.togglePin(second);
      await tabs.save();
      tabs.dispose();

      final again = TerminalTabs(dir.path);
      await again.load();
      final restored = again.tabs;
      expect(restored.map((t) => t.title), ['shell', 'build']); // pinned first
      expect(restored[0].pinned, isTrue);
      expect(restored[0].cwd, '/tmp');
      expect(restored[1].cwd, '/root/app');
      expect(restored[1].customTitle, isTrue);
      expect(restored[1].restoredScrollback, 'hello');
      expect(again.active.title, 'shell'); // the tab that was active
      again.dispose();
    });

    test('reads the old pinned-only format', () async {
      File('${dir.path}/terminal_tabs.json').writeAsStringSync(jsonEncode([
        {'title': 'server', 'custom': true},
      ]));
      final tabs = TerminalTabs(dir.path);
      await tabs.load();
      expect(tabs.tabs.single.title, 'server');
      expect(tabs.tabs.single.pinned, isTrue);
      tabs.dispose();
    });

    test('a corrupt file starts fresh with one tab', () async {
      File('${dir.path}/terminal_tabs.json').writeAsStringSync('{nope');
      final tabs = TerminalTabs(dir.path);
      await tabs.load();
      expect(tabs.tabs.single.title, 'shell');
      tabs.dispose();
    });
  });

  test('listeners always see a valid active tab while pinning', () async {
    final tabs = TerminalTabs(dir.path);
    await tabs.load();
    final seen = <String>[];
    tabs.addListener(() => seen.add(tabs.active.title));
    tabs.togglePin(tabs.active);
    expect(seen, isNotEmpty);
    tabs.dispose();
  });
}
