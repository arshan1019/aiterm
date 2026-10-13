import 'dart:async';
import 'package:flutter/services.dart';

/// Starts and finds pseudo-terminal sessions. [PtyHost] is the real one;
/// tests use a fake.
abstract interface class PtyBackend {
  Future<PtySession> start({
    required List<String> argv,
    required Map<String, String> env,
    required String cwd,
    required int rows,
    required int cols,
  });

  /// Ids of sessions still running natively (they outlive the UI).
  Future<List<int>> liveSessions();

  /// Reconnects to a running session, with its recent output to replay.
  Future<PtyAttachment?> attach(int id);
}

/// One child process on a PTY.
abstract interface class PtySession {
  int get id;

  /// Raw bytes from the process. Single subscriber.
  Stream<Uint8List> get output;

  /// Completes with the exit status when the process ends.
  Future<int> get exitCode;

  void write(String data);
  void resize(int rows, int cols);

  /// Hangs up the process (SIGHUP) and releases the PTY.
  void stop();
}

class PtyAttachment {
  const PtyAttachment(this.session, this.replay);
  final PtySession session;

  /// The session's recent output, to redraw the terminal.
  final Uint8List replay;
}

/// Native pseudo-terminals (android/.../PtyPlugin.kt + cpp/pty_native.c).
///
/// The native side only forks a PTY and execs the argv it's given; what to
/// run (proot, the Android shell) is decided in lib/linux. Sessions belong
/// to the process (kept alive by a foreground service), not to this UI, so
/// a recreated UI can reattach to them.
///
/// All sessions share one event stream, demultiplexed here by session id.
class PtyHost implements PtyBackend {
  PtyHost._();
  static final instance = PtyHost._();

  static const _method = MethodChannel('aiterm/pty');
  static const _events = EventChannel('aiterm/pty/output');

  final _sessions = <int, _NativePtySession>{};
  // Events for an id whose start() hasn't returned yet.
  final _early = <int, List<Object>>{};
  StreamSubscription<dynamic>? _sub;

  void _listen() => _sub ??= _events.receiveBroadcastStream().listen(_onEvent);

  @override
  Future<List<int>> liveSessions() async {
    _listen();
    return (await _method.invokeListMethod<int>('list')) ?? const [];
  }

  @override
  Future<PtyAttachment?> attach(int id) async {
    _listen();
    final replay = await _method.invokeMethod<Uint8List>('attach', {'id': id});
    if (replay == null) return null;
    // Anything that arrived before this is already part of the replay.
    _early.remove(id);
    return PtyAttachment(_register(id), replay);
  }

  _NativePtySession _register(int id) {
    final session = _NativePtySession._(id);
    _sessions[id] = session;
    for (final e in _early.remove(id) ?? const <Object>[]) {
      session._deliver(e);
    }
    return session;
  }

  @override
  Future<PtySession> start({
    required List<String> argv,
    required Map<String, String> env,
    required String cwd,
    required int rows,
    required int cols,
  }) async {
    _listen();
    final result = await _method.invokeMapMethod<String, Object?>('start', {
      'argv': argv,
      'env': env,
      'cwd': cwd,
      'rows': rows,
      'cols': cols,
    });
    return _register(result!['id']! as int);
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

class _NativePtySession implements PtySession {
  _NativePtySession._(this.id);

  @override
  final int id;

  final _output = StreamController<Uint8List>(sync: true);
  final _exit = Completer<int>();
  bool _stopped = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void _deliver(Object payload) {
    if (payload is Uint8List) {
      if (!_output.isClosed) _output.add(payload);
    } else if (payload is int) {
      if (!_exit.isCompleted) _exit.complete(payload);
      _output.close();
    }
  }

  @override
  void write(String data) {
    if (!_stopped) PtyHost.instance._call('write', {'id': id, 'data': data});
  }

  @override
  void resize(int rows, int cols) {
    if (!_stopped) PtyHost.instance._call('resize', {'id': id, 'rows': rows, 'cols': cols});
  }

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    PtyHost.instance._sessions.remove(id);
    PtyHost.instance._call('stop', {'id': id});
    if (!_output.isClosed) _output.close();
  }
}
