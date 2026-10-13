/// Keeping sessions alive on Android: what's needed, and the fix for the
/// Android 12+ child-process limit.
///
/// Android kills an app's child processes (all of Linux, here) beyond 32
/// across the system, the "phantom process killer", and battery
/// optimisation stops backgrounded apps. The foreground service keeps the
/// app itself running; these steps remove the rest.
library;

enum ChildProcessLimit {
  /// Before Android 12 there's no limit.
  notApplicable,
  enforced,
  disabled,

  /// The setting couldn't be read.
  unknown,
}

class KeepAliveStatus {
  const KeepAliveStatus({
    required this.sdk,
    required this.batteryUnrestricted,
    required this.notificationsAllowed,
    required this.childProcessLimit,
  });

  final int sdk;
  final bool batteryUnrestricted;
  final bool notificationsAllowed;
  final ChildProcessLimit childProcessLimit;
}

enum StepKind { battery, notifications, childProcesses }

class KeepAliveStep {
  const KeepAliveStep(this.kind, {required this.done, required this.title, required this.detail});

  final StepKind kind;
  final bool done;
  final String title;
  final String detail;
}

List<KeepAliveStep> keepAliveSteps(KeepAliveStatus s) => [
      KeepAliveStep(
        StepKind.battery,
        done: s.batteryUnrestricted,
        title: 'Unrestricted battery',
        detail: 'Stops Android pausing aiterm in the background.',
      ),
      KeepAliveStep(
        StepKind.notifications,
        done: s.notificationsAllowed,
        title: 'Notifications',
        detail: 'Shows that sessions are running, and tells you when a command finishes.',
      ),
      if (s.childProcessLimit != ChildProcessLimit.notApplicable)
        KeepAliveStep(
          StepKind.childProcesses,
          done: s.childProcessLimit == ChildProcessLimit.disabled,
          title: 'Child process limit',
          detail: 'Android ${s.sdk >= 34 ? '14+' : '12+'} kills long-running Linux processes '
              '("signal 9"). Turned off once through Wireless debugging; no computer needed.',
        ),
    ];

bool allDone(List<KeepAliveStep> steps) => steps.every((s) => s.done);

/// Shell commands (run through adb) that lift the limit on [sdk].
List<String> childProcessFixCommands(int sdk) => [
      if (sdk >= 31) ...[
        // Without this, device_config changes are synced back from Google.
        '/system/bin/device_config set_sync_disabled_for_tests persistent',
        '/system/bin/device_config put activity_manager max_phantom_processes 2147483647',
      ],
      // Android 13+ (and 12L backports): the switch Developer options shows
      // as "Disable child process restrictions".
      if (sdk >= 32) 'settings put global settings_enable_monitor_phantom_procs false',
    ];

String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The script run inside Linux (needs `apk add android-tools`): pair with
/// Wireless debugging, connect, apply [commands], and stop the adb server so
/// nothing is left running.
String adbFixScript({required int pairPort, required String code, required int connectPort, required List<String> commands}) {
  if (!RegExp(r'^\d{6}$').hasMatch(code)) throw ArgumentError.value(code, 'code', 'must be 6 digits');
  final device = '127.0.0.1:$connectPort';
  return [
    'adb pair 127.0.0.1:$pairPort $code &&',
    'adb connect $device &&',
    for (final c in commands) 'adb -s $device shell ${_q(c)} &&',
    'true; status=\$?',
    'adb kill-server >/dev/null 2>&1; exit \$status',
  ].join('\n');
}

class AdbFixResult {
  const AdbFixResult.ok()
      : ok = true,
        message = 'Done. Long-running processes are no longer killed.';
  const AdbFixResult.failed(this.message) : ok = false;

  final bool ok;
  final String message;

  @override
  bool operator ==(Object other) => other is AdbFixResult && other.ok == ok && other.message == message;
  @override
  int get hashCode => Object.hash(ok, message);
  @override
  String toString() => 'AdbFixResult($ok, $message)';
}

AdbFixResult parseAdbFix(String output, int exitCode) {
  if (exitCode == 0) return const AdbFixResult.ok();
  final o = output.toLowerCase();
  if (o.contains('adb: not found') || o.contains('adb: command not found') || exitCode == 127) {
    return const AdbFixResult.failed('adb isn\'t installed in Linux. Install it with: apk add android-tools');
  }
  if (o.contains('wrong password') || (o.contains('failed') && !o.contains('successfully paired'))) {
    return const AdbFixResult.failed('Pairing failed. Check the pairing code and try again while the code is showing.');
  }
  if (o.contains('failed to connect') || o.contains('cannot connect') || o.contains('connection refused')) {
    return const AdbFixResult.failed('Paired, but couldn\'t connect. Keep Wireless debugging turned on and retry.');
  }
  final last = output.trim().split('\n').last;
  return AdbFixResult.failed(last.isEmpty ? 'adb failed (exit $exitCode).' : last);
}
