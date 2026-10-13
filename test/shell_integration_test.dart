import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/terminal/shell_integration.dart';
import 'package:aiterm/linux/shell_profile.dart';

void main() {
  group('parseOsc', () {
    test('OSC 7 reports the working directory, percent-decoded', () {
      expect(parseOsc('7', ['file://localhost/root/my%20app']), const CwdChanged('/root/my app'));
      expect(parseOsc('7', ['file:///tmp']), const CwdChanged('/tmp'));
      expect(parseOsc('7', ['not a url']), isNull);
    });

    test('OSC 133 prompt marks', () {
      expect(parseOsc('133', ['A']), const PromptShown());
      expect(parseOsc('133', ['C']), const CommandStarted());
      expect(parseOsc('133', ['D', '0']), const CommandFinished(0));
      expect(parseOsc('133', ['D', '127']), const CommandFinished(127));
      expect(parseOsc('133', ['D']), const CommandFinished(null));
    });

    test('OSC 9 and OSC 777 notifications keep semicolons in the text', () {
      expect(parseOsc('9', ['Claude needs your permission; continue?']),
          const ShellNotification(null, 'Claude needs your permission; continue?'));
      expect(parseOsc('9', ['a', 'b']), const ShellNotification(null, 'a;b'));
      expect(parseOsc('777', ['notify', 'Build', 'done; 0 errors']), const ShellNotification('Build', 'done; 0 errors'));
      // OSC 9;4 is ConEmu progress, not a notification.
      expect(parseOsc('9', ['4', '1', '50']), isNull);
    });

    test('unrelated codes are ignored', () {
      expect(parseOsc('52', ['c', 'aGk=']), isNull);
    });
  });

  group('CommandTracker', () {
    late DateTime now;
    late CommandTracker t;
    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      t = CommandTracker(clock: () => now);
    });

    test('a command is Enter … exit code … prompt', () {
      expect(t.onEvent(const PromptShown()), isNull); // first prompt
      t.onEnter();
      now = now.add(const Duration(seconds: 42));
      expect(t.onEvent(const CommandFinished(2)), isNull);
      final done = t.onEvent(const PromptShown());
      expect(done, isNotNull);
      expect(done!.exitCode, 2);
      expect(done.duration, const Duration(seconds: 42));
    });

    test('Enter at an empty prompt or a prompt without Enter is not a command', () {
      t.onEvent(const PromptShown());
      expect(t.onEvent(const PromptShown()), isNull);
    });

    test('only the first prompt after Enter counts', () {
      t.onEvent(const PromptShown());
      t.onEnter();
      expect(t.onEvent(const PromptShown()), isNotNull);
      expect(t.onEvent(const PromptShown()), isNull);
    });

    test('busy is true between Enter and the next prompt', () {
      t.onEvent(const PromptShown());
      expect(t.busy, isFalse);
      t.onEnter();
      expect(t.busy, isTrue);
      t.onEvent(const PromptShown());
      expect(t.busy, isFalse);
    });
  });

  group('shell profile (needs busybox ash)', () {
    final ash = ['/bin/ash', '/bin/busybox'].firstWhere((p) => File(p).existsSync(), orElse: () => '');

    test('script output parses into the expected events', () async {
      final dir = Directory.systemTemp.createTempSync('aiterm_profile');
      addTearDown(() => dir.deleteSync(recursive: true));
      final profile = File('${dir.path}/aiterm.sh')..writeAsStringSync(shellProfile);
      final work = Directory('${dir.path}/my dir')..createSync();
      final p = await Process.start(
        ash,
        [if (ash.endsWith('busybox')) 'ash', '-i'],
        environment: {'ENV': profile.path, 'PS1': r'\w\$ ', 'HOME': dir.path},
      );
      p.stdin.write('cd "${work.path}"\nfalse\nexit\n');
      await p.stdin.close();
      final err = await p.stderr.transform(const SystemEncoding().decoder).join();
      await p.exitCode;
      final events = oscEventsIn(err);
      expect(events, contains(CwdChanged(work.path)));
      expect(events, contains(const CommandFinished(1)));
      expect(events.whereType<PromptShown>().length, greaterThanOrEqualTo(3));
    }, skip: ash.isEmpty ? 'no ash here' : null);
  });
}
