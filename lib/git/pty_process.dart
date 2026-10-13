import 'dart:async';
import 'dart:convert';
import '../linux/linux_environment.dart';
import '../platform/pty.dart';
import 'github_auth.dart';

/// A Linux command on a PTY, for programs that need a terminal to behave
/// interactively (gh's login).
class PtyProcess implements InteractiveProcess {
  PtyProcess._(this._pty) {
    _pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(
          _out.add,
          onDone: _out.close,
        );
    _pty.exitCode.then(_exit.complete);
  }

  static Future<PtyProcess> start(LinuxEnvironment linux, String commandLine) async {
    final spec = await linux.commandSpec(['/bin/sh', '-c', commandLine]);
    final pty = await PtyHost.instance.start(argv: spec.argv, env: spec.env, cwd: spec.cwd, rows: 24, cols: 120);
    return PtyProcess._(pty);
  }

  final PtySession _pty;
  final _out = StreamController<String>();
  final _exit = Completer<int>();

  @override
  Stream<String> get output => _out.stream;
  @override
  void write(String text) => _pty.write(text);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void kill() => _pty.stop();
}
