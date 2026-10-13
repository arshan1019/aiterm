import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/keep_alive/keep_alive.dart';
import 'package:aiterm/keep_alive/keep_alive_controller.dart';

class FakePlatform implements KeepAlivePlatform {
  Map<String, Object?> state = {'sdk': 34, 'battery': false, 'notifications': true, 'childLimit': 'unknown'};
  final calls = <String>[];
  String? result;

  @override
  void Function(String code, int pairPort, int connectPort)? onPairingCode;

  @override
  Future<Map<String, Object?>> status() async => state;
  @override
  Future<void> requestBattery() async => calls.add('battery');
  @override
  Future<bool> requestNotifications() async {
    calls.add('notifications');
    return true;
  }

  @override
  Future<bool> openDeveloperOptions() async => true;
  @override
  Future<void> startPairing() async => calls.add('startPairing');
  @override
  Future<void> stopPairing() async => calls.add('stopPairing');
  @override
  Future<void> pairingResult(String message) async => result = message;
}

void main() {
  late FakePlatform platform;
  late List<String> scripts;
  late (String, int) Function(String) respond;
  var fixed = false;

  KeepAliveController make() => KeepAliveController(
        platform: platform,
        runInLinux: (script) async {
          scripts.add(script);
          return respond(script);
        },
        isFixed: () => fixed,
        markFixed: () => fixed = true,
      );

  setUp(() {
    platform = FakePlatform();
    scripts = [];
    fixed = false;
    respond = (_) => ('', 0);
  });

  test('status becomes checklist steps', () async {
    final c = make();
    await c.refresh();
    expect(c.steps.map((s) => s.kind), [StepKind.battery, StepKind.notifications, StepKind.childProcesses]);
    expect(c.steps.first.done, isFalse);
  });

  test('a previous successful fix counts when Android hides the setting', () async {
    fixed = true;
    final c = make();
    await c.refresh();
    expect(c.steps.last.done, isTrue);
  });

  test('fixing installs adb first, then starts pairing', () async {
    final c = make();
    await c.refresh();
    await c.fixChildProcesses();
    expect(scripts.single, contains('apk add'));
    expect(platform.calls, contains('startPairing'));
    expect(c.fixing, isTrue);
  });

  test('if adb cannot be installed, pairing does not start', () async {
    respond = (_) => ('ERROR: unable to select packages', 1);
    final c = make();
    await c.refresh();
    await c.fixChildProcesses();
    expect(platform.calls, isNot(contains('startPairing')));
    expect(c.fixing, isFalse);
    expect(c.message, contains('android-tools'));
  });

  test('a pairing code runs the fix through adb and reports back', () async {
    final c = make();
    await c.refresh();
    await c.fixChildProcesses();
    platform.state = {...platform.state, 'childLimit': 'disabled'};
    platform.onPairingCode!('123456', 37001, 41002);
    await pumpEventQueue();
    final script = scripts.last;
    expect(script, contains('adb pair 127.0.0.1:37001 123456'));
    expect(script, contains('settings_enable_monitor_phantom_procs false'));
    expect(platform.result, contains('Done'));
    expect(fixed, isTrue);
    expect(c.fixing, isFalse);
    expect(c.steps.last.done, isTrue);
  });

  test('a failed pairing reports why and stays unfixed', () async {
    final c = make();
    await c.refresh();
    await c.fixChildProcesses();
    respond = (_) => ('Failed: Wrong password or connection was dropped.', 1);
    platform.onPairingCode!('654321', 1, 2);
    await pumpEventQueue();
    expect(platform.result, contains('pairing code'));
    expect(fixed, isFalse);
  });
}
