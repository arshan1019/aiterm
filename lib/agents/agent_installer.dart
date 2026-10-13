import 'package:flutter/foundation.dart';
import 'agent_catalog.dart';

enum AgentStatus { unknown, notInstalled, installing, installed, failed }

class AgentState {
  const AgentState(this.status, {this.step, this.message, this.log = ''});

  final AgentStatus status;

  /// The step running now (while installing).
  final String? step;

  /// Why it failed (the last meaningful output line).
  final String? message;

  /// Full output of the failed install, for "Show details".
  final String log;
}

/// Runs a script in Linux, streaming output lines; returns the exit status.
typedef ScriptRunner = Future<int> Function(String script, void Function(String line) onOutput);

/// Opens a terminal tab titled [title] and runs [commands] in it.
typedef AgentLauncher = void Function(String title, List<String> commands);

/// One-tap install of AI coding agents: dependencies and the agent itself
/// install in the background with progress; the user only signs in, in the
/// agent's own tab, on first open.
class AgentInstaller extends ChangeNotifier {
  AgentInstaller({required this._run, required this._launch});

  final ScriptRunner _run;
  final AgentLauncher _launch;
  final _states = <String, AgentState>{};
  String? _installing;

  bool get busy => _installing != null;

  AgentState stateOf(String id) => _states[id] ?? const AgentState(AgentStatus.unknown);

  static AgentRecipe recipe(String id) => agentCatalog.firstWhere((a) => a.id == id);

  /// Checks which agents are installed.
  Future<void> refresh() async {
    final found = <String>{};
    final check = [
      r'PATH="$HOME/.local/bin:$PATH"',
      for (final a in agentCatalog) 'command -v ${a.command} >/dev/null 2>&1 && echo ${a.command}',
      'true',
    ].join('\n');
    await _run(check, (line) => found.add(line.trim()));
    for (final a in agentCatalog) {
      if (_installing == a.id) continue;
      final failed = stateOf(a.id).status == AgentStatus.failed;
      if (found.contains(a.command)) {
        _states[a.id] = const AgentState(AgentStatus.installed);
      } else if (!failed) {
        _states[a.id] = const AgentState(AgentStatus.notInstalled);
      }
    }
    notifyListeners();
  }

  Future<void> install(String id) async {
    if (busy) return;
    final agent = recipe(id);
    _installing = id;
    final log = StringBuffer();
    try {
      for (final step in agent.steps) {
        _states[id] = AgentState(AgentStatus.installing, step: step.label);
        notifyListeners();
        log.writeln('\$ ${step.label}');
        final code = await _run(step.script, (line) => log.writeln(line));
        if (code != 0) {
          _states[id] = AgentState(AgentStatus.failed, message: _reason(log.toString(), code), log: log.toString());
          return;
        }
      }
      _states[id] = const AgentState(AgentStatus.installed);
    } catch (e) {
      _states[id] = AgentState(AgentStatus.failed, message: '$e', log: log.toString());
    } finally {
      _installing = null;
      notifyListeners();
    }
    await refresh();
  }

  /// Starts the agent in its own tab; first start walks through sign-in.
  void open(String id) {
    final agent = recipe(id);
    _launch(agent.name, [agent.command]);
  }

  static String _reason(String log, int code) {
    final lines = log.trim().split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith(r'$ ')).toList();
    final error = lines.lastWhere((l) => l.contains(RegExp('error|fail|denied|unreachable', caseSensitive: false)),
        orElse: () => lines.isEmpty ? '' : lines.last);
    return error.isEmpty ? 'Install failed (exit $code).' : error.trim();
  }
}
