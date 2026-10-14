import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../linux/linux_environment.dart';
import '../../git/git_runner.dart';
import 'acp_connection.dart';

/// How an agent speaks ACP (agentclientprotocol.com): Gemini CLI natively,
/// Claude Code and Codex through the official adapters, which run the
/// agent already installed (CLAUDE_CODE_EXECUTABLE, CODEX_PATH), so
/// `--omit=optional` skips their bundled copies (about 240 MB for Claude).
class AcpAgent {
  const AcpAgent({required this.id, required this.command, this.adapter, this.install});

  /// The agent's id in the catalog.
  final String id;

  /// Starts the ACP server on stdio (POSIX sh).
  final String command;

  /// The adapter program, when the agent needs one.
  final String? adapter;

  /// Installs the adapter.
  final String? install;

  static const all = [
    AcpAgent(
      id: 'claude',
      command: 'CLAUDE_CODE_EXECUTABLE="\$(command -v claude)" exec claude-agent-acp',
      adapter: 'claude-agent-acp',
      install: 'apk add -q --no-cache nodejs npm && npm install -g --omit=optional @agentclientprotocol/claude-agent-acp',
    ),
    AcpAgent(
      id: 'codex',
      command: 'CODEX_PATH="\$(command -v codex)" exec codex-acp',
      adapter: 'codex-acp',
      install: 'npm install -g --omit=optional @agentclientprotocol/codex-acp',
    ),
    AcpAgent(id: 'gemini', command: 'exec gemini --acp'),
  ];

  static AcpAgent? of(String id) => all.where((a) => a.id == id).firstOrNull;
}

/// The PATH agents are installed on (Claude's installer uses ~/.local/bin).
const _path = r'export PATH="$HOME/.local/bin:$PATH"';

/// Starts [agent]'s ACP server in Linux, in [cwd] (a guest path).
typedef AcpStarter = Future<AcpTransport> Function(AcpAgent agent, String cwd);

/// Installs [agent]'s adapter if missing; null when ready, else the reason.
typedef AcpPreparer = Future<String?> Function(AcpAgent agent, void Function(String line) onOutput);

/// An agent's ACP server under proot, on pipes.
class LinuxAcpTransport implements AcpTransport {
  LinuxAcpTransport._(this._process) {
    _lines = _process.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());
    _process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
      _log.add(line);
      if (_log.length > 40) _log.removeAt(0);
    });
  }

  static Future<LinuxAcpTransport> start(LinuxEnvironment linux, AcpAgent agent, String cwd) async {
    final spec = await linux.commandSpec(['/bin/sh', '-c', '$_path; cd ${shellQuote(cwd)} && ${agent.command}']);
    final p = await Process.start(spec.argv.first, spec.argv.sublist(1), environment: spec.env, workingDirectory: spec.cwd);
    return LinuxAcpTransport._(p);
  }

  /// Installs the adapter when it's missing.
  static Future<String?> prepare(LinuxEnvironment linux, AcpAgent agent, void Function(String line) onOutput) async {
    final adapter = agent.adapter;
    if (adapter == null) return null;
    final log = <String>[];
    final code = await linux.runScriptStreaming(
      '$_path\ncommand -v $adapter >/dev/null 2>&1 && exit 0\nset -e\n${agent.install}',
      (line) {
        log.add(line);
        onOutput(line);
      },
    );
    if (code == 0) return null;
    return log.lastWhere((l) => l.trim().isNotEmpty, orElse: () => 'Install failed (exit $code).').trim();
  }

  final Process _process;
  late final Stream<String> _lines;
  final _log = <String>[];

  @override
  Stream<String> get lines => _lines;
  @override
  void send(String line) => _process.stdin.writeln(line);
  @override
  String get log => _log.join('\n');
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  void kill() => _process.kill();
}
