import 'dart:async';
import 'package:flutter/services.dart';

/// Bridge to the native PTY implementation (Kotlin + JNI, see
/// android/app/src/main/cpp/pty_jni.c). One [PtySession] == one live
/// child process attached to a real pseudo-terminal.
///
/// The native side knows nothing about proot/Alpine/Arch — it just forks
/// a pty and execs whatever argv it's given. All distro-specific argv
/// construction lives in [DistroManager] / [SessionLauncher] on the Dart
/// side, so the native bridge never needs to change when the distro does.
class PtySession {
  static const MethodChannel _method = MethodChannel('aiterm/pty');
  static const EventChannel _events = EventChannel('aiterm/pty/output');

  int? _id;
  StreamSubscription<dynamic>? _sub;
  final _outputController = StreamController<Uint8List>.broadcast();
  final _exitController = StreamController<int>.broadcast();

  Stream<Uint8List> get output => _outputController.stream;
  Stream<int> get onExit => _exitController.stream;
  bool get isRunning => _id != null;

  /// Starts [argv] inside a new pty. [env] is passed through verbatim
  /// (the caller is responsible for a sane PATH/HOME/TERM).
  Future<void> start({
    required List<String> argv,
    required Map<String, String> env,
    required String cwd,
    int rows = 24,
    int cols = 80,
  }) async {
    if (_id != null) {
      throw StateError('Session already started');
    }
    final result = await _method.invokeMethod<Map>('start', {
      'argv': argv,
      'env': env,
      'cwd': cwd,
      'rows': rows,
      'cols': cols,
    });
    _id = result?['id'] as int?;
    if (_id == null) {
      throw StateError('Native side did not return a session id');
    }

    _sub = _events.receiveBroadcastStream(_id).listen(
      (event) {
        if (event is Uint8List) {
          _outputController.add(event);
        } else if (event is Map && event['exitCode'] != null) {
          _exitController.add(event['exitCode'] as int);
        }
      },
      onError: (Object e) => _outputController.addError(e),
    );
  }

  Future<void> write(String data) async {
    final id = _id;
    if (id == null) return;
    await _method.invokeMethod('write', {'id': id, 'data': data});
  }

  Future<void> resize(int rows, int cols) async {
    final id = _id;
    if (id == null) return;
    await _method.invokeMethod('resize', {
      'id': id,
      'rows': rows,
      'cols': cols,
    });
  }

  Future<void> stop() async {
    final id = _id;
    if (id == null) return;
    await _method.invokeMethod('stop', {'id': id});
    await _sub?.cancel();
    _id = null;
  }

  Future<void> dispose() async {
    await stop();
    await _outputController.close();
    await _exitController.close();
  }
}
