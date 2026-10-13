import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/linux/proc_stubs.dart';

void main() {
  final boot = DateTime.utc(2026, 10, 13, 6, 0, 0, 750);

  test('/proc/stat boot time is the real boot moment, whenever it is written', () {
    final early = procStatContent(cpus: [0, 1], bootTime: boot, now: boot.add(const Duration(minutes: 5)));
    final late = procStatContent(cpus: [0, 1], bootTime: boot, now: boot.add(const Duration(hours: 9)));
    final btime = boot.millisecondsSinceEpoch ~/ 1000;
    expect(early, contains('\nbtime $btime\n'));
    expect(late, contains('\nbtime $btime\n'), reason: 'every session must agree (Codex compares start times)');
  });

  test('/proc/stat lists every cpu and the fields procps reads', () {
    final s = procStatContent(cpus: [0, 1, 2, 3], bootTime: boot, now: boot.add(const Duration(hours: 1)));
    expect(s, startsWith('cpu  '));
    for (final i in [0, 1, 2, 3]) {
      expect(s, contains('\ncpu$i '));
    }
    for (final f in ['intr', 'ctxt', 'btime', 'processes', 'procs_running', 'procs_blocked']) {
      expect(s, contains('\n$f '));
    }
  });

  test('/proc/uptime is the time since boot', () {
    final u = procUptimeContent(cpus: 4, bootTime: boot, now: boot.add(const Duration(seconds: 3600)));
    expect(u.split(' ').first, '3600.00');
  });
}
