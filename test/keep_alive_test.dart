import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/keep_alive/keep_alive.dart';

void main() {
  group('checklist', () {
    test('everything done on Android 11: no child-process step at all', () {
      final steps = keepAliveSteps(const KeepAliveStatus(
        sdk: 30,
        batteryUnrestricted: true,
        notificationsAllowed: true,
        childProcessLimit: ChildProcessLimit.notApplicable,
      ));
      expect(steps.map((s) => s.kind), [StepKind.battery, StepKind.notifications]);
      expect(steps.every((s) => s.done), isTrue);
    });

    test('Android 14 with the limit on asks to fix it', () {
      final steps = keepAliveSteps(const KeepAliveStatus(
        sdk: 34,
        batteryUnrestricted: false,
        notificationsAllowed: true,
        childProcessLimit: ChildProcessLimit.enforced,
      ));
      final child = steps.firstWhere((s) => s.kind == StepKind.childProcesses);
      expect(child.done, isFalse);
      expect(steps.firstWhere((s) => s.kind == StepKind.battery).done, isFalse);
      expect(allDone(steps), isFalse);
    });

    test('unknown limit state is shown as not done', () {
      final steps = keepAliveSteps(const KeepAliveStatus(
        sdk: 33,
        batteryUnrestricted: true,
        notificationsAllowed: true,
        childProcessLimit: ChildProcessLimit.unknown,
      ));
      expect(steps.firstWhere((s) => s.kind == StepKind.childProcesses).done, isFalse);
    });
  });

  group('fix commands', () {
    test('Android 12/12L raise the phantom process cap and stop it syncing back', () {
      final cmds = childProcessFixCommands(31);
      expect(cmds, contains('/system/bin/device_config set_sync_disabled_for_tests persistent'));
      expect(cmds, contains('/system/bin/device_config put activity_manager max_phantom_processes 2147483647'));
    });

    test('Android 13+ also turns the monitor off', () {
      expect(childProcessFixCommands(34), contains('settings put global settings_enable_monitor_phantom_procs false'));
    });

    test('nothing to do before Android 12', () {
      expect(childProcessFixCommands(30), isEmpty);
    });
  });

  group('adb script', () {
    test('pairs, connects, runs each command on that device, then stops the server', () {
      final script = adbFixScript(pairPort: 37001, code: '123456', connectPort: 41002, commands: ['echo a', "echo 'b'"]);
      expect(script, contains('adb pair 127.0.0.1:37001 123456'));
      expect(script, contains('adb connect 127.0.0.1:41002'));
      expect(script, contains("adb -s 127.0.0.1:41002 shell 'echo a'"));
      expect(script, contains("adb -s 127.0.0.1:41002 shell 'echo '\\''b'\\'''"));
      expect(script.trim().split('\n').last, contains('adb kill-server'));
    });

    test('rejects a malformed pairing code instead of passing it to a shell', () {
      expect(() => adbFixScript(pairPort: 1, code: '12; rm -rf /', connectPort: 2, commands: const []),
          throwsArgumentError);
    });
  });

  group('adb results', () {
    test('success', () {
      expect(
        parseAdbFix('Successfully paired to 127.0.0.1:37001 [guid=adb-x]\nconnected to 127.0.0.1:41002\n', 0),
        const AdbFixResult.ok(),
      );
    });

    test('wrong code', () {
      final r = parseAdbFix('Failed: Wrong password or connection was dropped.\n', 1);
      expect(r.ok, isFalse);
      expect(r.message, contains('pairing code'));
    });

    test('connect refused', () {
      final r = parseAdbFix('Successfully paired to 127.0.0.1:1\nfailed to connect to 127.0.0.1:2\n', 1);
      expect(r.ok, isFalse);
      expect(r.message, contains('Wireless debugging'));
    });

    test('adb missing', () {
      final r = parseAdbFix('sh: adb: not found\n', 127);
      expect(r.ok, isFalse);
      expect(r.message, contains('android-tools'));
    });
  });
}
