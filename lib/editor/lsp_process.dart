import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../git/git_runner.dart';
import '../linux/linux_environment.dart';
import 'language_servers.dart';
import 'lsp_framing.dart';

/// A language server running in Linux, speaking LSP over its stdin/stdout
/// (plain pipes, not a terminal: the protocol is length-framed bytes).
class LspProcess {
  LspProcess._(this._process, void Function(String json) onMessage) {
    final reader = LspReader(onMessage);
    _out = _process.stdout.listen(reader.add);
    // Servers log to stderr; keep the tail for "Details".
    _err = _process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((s) {
      _log.write(s);
      if (_log.length > 8000) {
        final keep = _log.toString().substring(_log.length - 4000);
        _log
          ..clear()
          ..write(keep);
      }
    });
  }

  final Process _process;
  late final StreamSubscription<List<int>> _out;
  late final StreamSubscription<String> _err;
  final _log = StringBuffer();

  Future<int> get exitCode => _process.exitCode;
  String get log => _log.toString();

  /// Starts [server] in [root] (a guest path: the project, or the file's folder).
  static Future<LspProcess> start(
    LinuxEnvironment linux,
    LanguageServer server,
    String root,
    void Function(String json) onMessage,
  ) async {
    final spec = await linux.commandSpec(['/bin/sh', '-c', 'cd ${shellQuote(root)} 2>/dev/null; exec ${server.command}']);
    final p = await Process.start(spec.argv.first, spec.argv.sublist(1), environment: spec.env, workingDirectory: spec.cwd);
    return LspProcess._(p, onMessage);
  }

  void send(String json) {
    try {
      _process.stdin.add(encodeLspMessage(json));
    } catch (_) {
      // The server exited; the editor hears it from exitCode.
    }
  }

  Future<void> stop() async {
    await _out.cancel();
    await _err.cancel();
    _process.kill();
  }
}
