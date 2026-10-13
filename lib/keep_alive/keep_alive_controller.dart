import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'keep_alive.dart';

/// What the app needs from Android to keep sessions alive
/// (android/.../KeepAlivePlugin.kt).
abstract interface class KeepAlivePlatform {
  Future<Map<String, Object?>> status();
  Future<void> requestBattery();
  Future<bool> requestNotifications();

  /// Opens Developer options (or About phone if they're off); true if on.
  Future<bool> openDeveloperOptions();

  /// Starts looking for Wireless debugging and asks for the pairing code.
  Future<void> startPairing();
  Future<void> stopPairing();
  Future<void> pairingResult(String message);

  /// Called with the code the user typed and the ports found over mDNS.
  set onPairingCode(void Function(String code, int pairPort, int connectPort)? callback);
}

typedef LinuxRunner = Future<(String output, int exitCode)> Function(String script);

/// The keep-alive checklist and the child-process-limit fix.
class KeepAliveController extends ChangeNotifier {
  KeepAliveController({
    required this._platform,
    required LinuxRunner runInLinux,
    required this._isFixed,
    required this._markFixed,
  }) : _run = runInLinux {
    _platform.onPairingCode = _onPairingCode;
  }

  final KeepAlivePlatform _platform;
  final LinuxRunner _run;
  final bool Function() _isFixed;
  final VoidCallback _markFixed;

  KeepAliveStatus? _status;
  List<KeepAliveStep> steps = const [];

  /// Waiting for, or running, the Wireless debugging fix.
  bool fixing = false;

  /// The latest progress or result message for the fix.
  String? message;

  int get sdk => _status?.sdk ?? 0;

  Future<void> refresh() async {
    final s = await _platform.status();
    var limit = switch (s['childLimit']) {
      'na' => ChildProcessLimit.notApplicable,
      'enforced' => ChildProcessLimit.enforced,
      'disabled' => ChildProcessLimit.disabled,
      _ => ChildProcessLimit.unknown,
    };
    // Android 12 has no readable switch; trust a fix that reported success.
    if (limit != ChildProcessLimit.notApplicable && limit != ChildProcessLimit.disabled && _isFixed()) {
      limit = ChildProcessLimit.disabled;
    }
    _status = KeepAliveStatus(
      sdk: s['sdk'] as int? ?? 0,
      batteryUnrestricted: s['battery'] == true,
      notificationsAllowed: s['notifications'] == true,
      childProcessLimit: limit,
    );
    steps = keepAliveSteps(_status!);
    notifyListeners();
  }

  Future<void> requestBattery() => _platform.requestBattery();

  Future<void> requestNotifications() async {
    await _platform.requestNotifications();
    await refresh();
  }

  Future<bool> openDeveloperOptions() => _platform.openDeveloperOptions();

  /// Step 1 of the fix: make sure adb exists in Linux, then wait for the
  /// pairing code (the notification takes it from there).
  Future<void> fixChildProcesses() async {
    fixing = true;
    message = 'Installing adb in Linux…';
    notifyListeners();
    final (output, code) = await _run('command -v adb >/dev/null 2>&1 || apk add -q android-tools');
    if (code != 0) {
      fixing = false;
      message = "Couldn't install android-tools: ${output.trim().split('\n').last}";
      notifyListeners();
      return;
    }
    message = 'Open Wireless debugging, tap “Pair device with pairing code”, '
        'and type the code into the aiterm notification.';
    notifyListeners();
    await _platform.startPairing();
  }

  Future<void> cancelFix() async {
    fixing = false;
    message = null;
    notifyListeners();
    await _platform.stopPairing();
  }

  Future<void> _onPairingCode(String code, int pairPort, int connectPort) async {
    AdbFixResult result;
    try {
      final script = adbFixScript(
        pairPort: pairPort,
        code: code,
        connectPort: connectPort,
        commands: childProcessFixCommands(sdk),
      );
      final (output, exit) = await _run(script);
      result = parseAdbFix(output, exit);
    } on ArgumentError {
      result = const AdbFixResult.failed('The pairing code is the 6 digits shown in Wireless debugging.');
    }
    if (result.ok) _markFixed();
    fixing = !result.ok && fixing;
    message = result.message;
    await _platform.pairingResult(result.message);
    await refresh();
  }
}

/// The real [KeepAlivePlatform] over the "aiterm/keepalive" channel.
class KeepAliveChannel implements KeepAlivePlatform {
  KeepAliveChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pairingCode') {
        final a = call.arguments as Map;
        _onCode?.call(a['code'] as String, a['pairPort'] as int, a['connectPort'] as int);
      }
    });
  }

  static const _channel = MethodChannel('aiterm/keepalive');
  void Function(String, int, int)? _onCode;

  @override
  set onPairingCode(void Function(String code, int pairPort, int connectPort)? callback) => _onCode = callback;

  @override
  Future<Map<String, Object?>> status() async =>
      (await _channel.invokeMapMethod<String, Object?>('status')) ?? const {};
  @override
  Future<void> requestBattery() => _channel.invokeMethod('requestBattery');
  @override
  Future<bool> requestNotifications() async => await _channel.invokeMethod<bool>('requestNotifications') ?? false;
  @override
  Future<bool> openDeveloperOptions() async => await _channel.invokeMethod<bool>('openDeveloperOptions') ?? false;
  @override
  Future<void> startPairing() => _channel.invokeMethod('startPairing');
  @override
  Future<void> stopPairing() => _channel.invokeMethod('stopPairing');
  @override
  Future<void> pairingResult(String message) => _channel.invokeMethod('pairingResult', {'message': message});
}
