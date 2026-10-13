import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/terminal/terminal_session.dart';

void main() {
  late TerminalSession s;
  late List<SessionSignal> signals;

  setUp(() {
    s = TerminalSession(id: 1, title: 'shell');
    signals = [];
    s.onSignal = signals.add;
  });
  tearDown(() => s.dispose());

  test('follows the shell folder from OSC 7', () {
    s.terminal.write('\x1b]7;file://localhost/root/app\x07');
    expect(s.cwd, '/root/app');
  });

  test('a finished command is signalled with its exit status', () {
    s.terminal.write('\x1b]133;A\x07');
    s.terminal.textInput('make\r');
    s.terminal.write('\x1b]133;D;2\x07\x1b]133;A\x07');
    final done = signals.whereType<CommandSignal>().single;
    expect(done.command.exitCode, 2);
  });

  test('OSC 9 notifications and bells are signalled', () {
    s.terminal.write('\x1b]9;Claude needs input\x07');
    s.terminal.write('\x07');
    expect(signals.whereType<NotifySignal>().single.notification.body, 'Claude needs input');
    expect(signals.whereType<BellSignal>(), hasLength(1));
  });

  test('busy reflects a running command', () {
    s.terminal.write('\x1b]133;A\x07');
    expect(s.busy, isFalse);
    s.terminal.textInput('sleep 5\r');
    expect(s.busy, isTrue);
    s.terminal.write('\x1b]133;D;0\x07\x1b]133;A\x07');
    expect(s.busy, isFalse);
  });

  test('recent output keeps the tail as plain lines for notifications', () {
    s.terminal.write('one\r\ntwo\r\n\x1b[31mthree\x1b[0m\r\n');
    expect(s.lastOutputLine(), 'three');
  });
}
