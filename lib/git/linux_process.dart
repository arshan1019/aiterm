import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../linux/linux_environment.dart';
import 'github_auth.dart';

/// A Linux command on plain pipes, its stdout and stderr merged. Not a
/// terminal on purpose: gh's login then runs non-interactively, printing
/// the one-time code and URL with no prompts to answer.
class LinuxProcess implements InteractiveProcess {
  LinuxProcess._(this._process) {
    var open = 2;
    void done() {
      if (--open == 0) _out.close();
    }

    for (final stream in [_process.stdout, _process.stderr]) {
      stream.transform(const Utf8Decoder(allowMalformed: true)).listen(_out.add, onDone: done);
    }
  }

  static Future<LinuxProcess> start(LinuxEnvironment linux, String commandLine) async {
    final spec = await linux.commandSpec(['/bin/sh', '-c', commandLine]);
    final p = await Process.start(spec.argv.first, spec.argv.sublist(1), environment: spec.env, workingDirectory: spec.cwd);
    return LinuxProcess._(p);
  }

  final Process _process;
  final _out = StreamController<String>();

  @override
  Stream<String> get output => _out.stream;
  @override
  void write(String text) => _process.stdin.write(text);
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  void kill() => _process.kill();
}
