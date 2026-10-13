import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/linux/linux_environment.dart';
import 'package:aiterm/platform/android_env.dart';
import 'package:aiterm/terminal/terminal_tabs.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('aiterm_here'));
  tearDown(() => dir.deleteSync(recursive: true));

  LinuxEnvironment env() => LinuxEnvironment(AppPaths(
        nativeLibDir: '${dir.path}/lib',
        filesDir: dir.path,
        cacheDir: dir.path,
        uptimeMs: 0,
      ));

  test('folders in Alpine map to the path the shell sees', () async {
    File('${dir.path}/alpine/.aiterm-installed')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final linux = env();
    await linux.load();
    expect(linux.guestPath('${dir.path}/alpine/root/app'), '/root/app');
    expect(linux.guestPath('${dir.path}/alpine'), '/');
    expect(linux.guestPath('/storage/emulated/0/Download'), '/sdcard/Download');
  });

  test("with Android's shell the host path is the shell's path", () async {
    final linux = env();
    await linux.load();
    linux.useAndroidShell();
    expect(linux.guestPath('${dir.path}/home/x'), '${dir.path}/home/x');
  });

  test('a tab can open in a given folder', () async {
    final tabs = TerminalTabs(dir.path);
    await tabs.load();
    final t = tabs.open(cwd: '/root/app');
    expect(t.cwd, '/root/app');
    expect(tabs.active, t);
    expect(t.title, 'app'); // named after the folder
    tabs.dispose();
  });

  test('shells advertise a 256-colour, truecolour terminal', () async {
    final linux = env();
    await linux.load();
    linux.useAndroidShell();
    final spec = await linux.sessionSpec();
    expect(spec.env['TERM'], 'xterm-256color');
    expect(spec.env['COLORTERM'], 'truecolor');
    // Alpine sessions pass the same through `env -i` (see _prootSpec).
    final source = File('lib/linux/linux_environment.dart').readAsStringSync();
    expect(source, contains("'TERM=xterm-256color'"));
    expect(source, contains("'COLORTERM=truecolor'"));
  });
}
