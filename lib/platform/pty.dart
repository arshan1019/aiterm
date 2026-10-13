import 'dart:async';
import 'package:flutter/services.dart';

/// Native pseudo-terminals (android/.../PtyPlugin.kt + cpp/pty_native.c).
///
/// The native side only forks a PTY and execs the argv it's given; what to
/// run (proot, the Android shell) is decided in lib/linux.
///
/// All sessions share one event stream, demultiplexed here by session id.
class PtyHost {
  PtyHost._();
  static final instance = PtyHost._();

  static const _method = MethodChannel('aiterm/pty');
  static const _events = EventChannel('aiterm/pty/output');

  final _sessions = <int, PtySession>{};
  // Events for an id whose start() hasn't returned yet.
  final _early = <int, List<Object>>{};
  StreamSubscription<dynamic>? _sub;

  Future<PtySession> start({
    required List<String> argv,
    required Map<String, String> env,
    required String cwd,
    required int rows,
    required int cols,
  }) async {
    _sub ??= _events.receiveBroadcastStream().listen(_onEvent);
    final result = await _method.invokeMapMethod<String, Object?>('start', {
      'argv': argv,
      'env': env,
      'cwd': cwd,
      'rows': rows,
      'cols': cols,
    });
    final id = result!['id']! as int;
    final session = PtySession._(id);
    _sessions[id] = session;
    for (final e in _early.remove(id) ?? const <Object>[]) {
      session._deliver(e);
    }
    return session;
  }

  void _onEvent(dynamic event) {
    final list = event as List<Object?>;
    final id = list[0]! as int;
    final payload = list[1]!;
    final session = _sessions[id];
    if (session == null) {
      (_early[id] ??= []).add(payload);
      return;
    }
    session._deliver(payload);
    if (payload is int) _sessions.remove(id);
  }

  Future<void> _call(String method, Map<String, Object> args) => _method.invokeMethod(method, args);
}

/// One child process on a PTY.
class PtySession {
  PtySession._(this.id);
  final int id;

  final _output = StreamController<Uint8List>(sync: true);
  final _exit = Completer<int>();
  bool _stopped = false;

  /// Raw bytes from the process. Single subscriber.
  Stream<Uint8List> get output => _output.stream;

  /// Completes with the exit status when the process ends.
  Future<int> get exitCode => _exit.future;

  void _deliver(Object payload) {
    if (payload is Uint8List) {
      if (!_output.isClosed) _output.add(payload);
    } else if (payload is int) {
      if (!_exit.isCompleted) _exit.complete(payload);
      _output.close();
    }
  }

  void write(String data) {
    if (!_stopped) PtyHost.instance._call('write', {'id': id, 'data': data});
  }

  void resize(int rows, int cols) {
    if (!_stopped) PtyHost.instance._call('resize', {'id': id, 'rows': rows, 'cols': cols});
  }

  /// Hangs up the process (SIGHUP) and releases the PTY.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    PtyHost.instance._sessions.remove(id);
    PtyHost.instance._call('stop', {'id': id});
    if (!_output.isClosed) _output.close();
  }
}
