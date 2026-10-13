import 'dart:io';
import '../shared/fs_atomic.dart';

const kernelRelease = '6.17.0-aiterm';
const kernelVersion = '#1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000';

/// Android (SELinux) denies apps /proc/stat, /proc/uptime and friends, but
/// top, ps, free, Node's os.cpus() and Python's psutil all read them. Like
/// Termux's proot-distro, bind believable stand-ins over the ones this
/// device blocks. They're written to [dir], outside the rootfs, so the
/// guest can't swap them for links to host files.
Future<List<String>> procStubBinds(Directory dir, {required DateTime bootTime}) async {
  await dir.create(recursive: true);
  final empty = Directory('${dir.path}/empty');
  await empty.create();
  // An empty /sys/fs/selinux: tools then don't try to label files.
  final binds = ['--bind=${empty.path}:/sys/fs/selinux'];

  final cpus = _cpuIds();
  final now = DateTime.now();
  final stubs = {
    '/proc/stat': procStatContent(cpus: cpus, bootTime: bootTime, now: now),
    '/proc/uptime': procUptimeContent(cpus: cpus.length, bootTime: bootTime, now: now),
    '/proc/loadavg': '0.12 0.07 0.02 1/100 100\n',
    '/proc/version': 'Linux version $kernelRelease (aiterm@localhost) (clang version 18) $kernelVersion\n',
    '/proc/vmstat': '${const [
      'nr_free_pages 100000', 'nr_inactive_anon 0', 'nr_active_anon 0', 'nr_inactive_file 0',
      'nr_active_file 0', 'nr_dirty 0', 'nr_writeback 0', 'pgpgin 0', 'pgpgout 0', 'pswpin 0',
      'pswpout 0', 'pgfault 0', 'pgmajfault 0',
    ].join('\n')}\n',
    '/proc/sys/kernel/cap_last_cap': '40\n',
    '/proc/sys/fs/inotify/max_user_watches': '8192\n',
    '/proc/sys/kernel/overflowuid': '65534\n',
    '/proc/sys/kernel/overflowgid': '65534\n',
  };
  for (final MapEntry(key: real, value: content) in stubs.entries) {
    if (_readable(real)) continue; // this device allows the real one
    final stub = '${dir.path}/${real.substring(1).replaceAll('/', '_')}';
    await writeFileAtomic(stub, content); // several tabs may start at once
    binds.add('--bind=$stub:$real');
  }
  return binds;
}

/// /proc/stat with one line per cpu. `btime` is the fixed boot moment, so
/// every session reports the same process start times (procps computes
/// them from it; Codex compares them across runs).
String procStatContent({required List<int> cpus, required DateTime bootTime, required DateTime now}) {
  final uptime = now.difference(bootTime).inMilliseconds / 1000;
  String jiffies(double share) => '${(uptime * 100 * share).round()}';
  final idle = uptime * cpus.length * 0.9;
  final stat = StringBuffer()
    ..writeln('cpu  ${jiffies(0.05 * cpus.length)} 0 ${jiffies(0.03 * cpus.length)} ${(idle * 100).round()} 0 0 0 0 0 0');
  for (final id in cpus) {
    stat.writeln('cpu$id ${jiffies(0.05)} 0 ${jiffies(0.03)} ${jiffies(0.9)} 0 0 0 0 0 0');
  }
  stat
    ..writeln('intr 0')
    ..writeln('ctxt 0')
    ..writeln('btime ${bootTime.millisecondsSinceEpoch ~/ 1000}')
    ..writeln('processes 1')
    ..writeln('procs_running 1')
    ..writeln('procs_blocked 0')
    ..writeln('softirq 0');
  return stat.toString();
}

String procUptimeContent({required int cpus, required DateTime bootTime, required DateTime now}) {
  final uptime = now.difference(bootTime).inMilliseconds / 1000;
  return '${uptime.toStringAsFixed(2)} ${(uptime * cpus * 0.9).toStringAsFixed(2)}\n';
}

List<int> _cpuIds() {
  try {
    final ids = RegExp(r'^processor\s*:\s*(\d+)', multiLine: true)
        .allMatches(File('/proc/cpuinfo').readAsStringSync())
        .map((m) => int.parse(m.group(1)!))
        .toList();
    if (ids.isNotEmpty) return ids;
  } catch (_) {}
  return List.generate(Platform.numberOfProcessors, (i) => i);
}

bool _readable(String path) {
  try {
    final f = File(path).openSync();
    try {
      f.readSync(1);
    } finally {
      f.closeSync();
    }
    return true;
  } catch (_) {
    return false;
  }
}
