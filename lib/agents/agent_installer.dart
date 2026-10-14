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

/// Opens (or goes back to) [agent]'s terminal tab titled [title], in folder
/// [cwd] (a guest path) if given, running [commands].
typedef AgentLauncher = void Function(AgentRecipe agent, String title, List<String> commands, String? cwd);

/// One-tap install of AI coding agents: dependencies and the agent itself
/// install in the background with progress; the user only signs in, in the
/// agent's own tab, on first open.
class AgentInstaller extends ChangeNotifier {
  AgentInstaller({required this._run, required this._launch});

  final ScriptRunner _run;
  final AgentLauncher _launch;

  /// Opens the agent as blocks instead of its terminal UI when that's on
  /// for it; true when it did.
  bool Function(AgentRecipe agent, String? cwd)? openAsBlocks;
  final _states = <String, AgentState>{};
  String? _installing;

  bool get busy => _installing != null;

  /// Agents ready to open, in catalog order (menus list only these).
  List<AgentRecipe> get installed =>
      [for (final a in agentCatalog) if (stateOf(a.id).status == AgentStatus.installed) a];

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

  /// Starts the agent in its own tab, in [cwd] if given; first start walks
  /// through sign-in. Not installed yet: installs it first (one tap from
  /// anywhere). Dependencies a newer recipe added (e.g. procps for Codex)
  /// are installed first, so existing installs keep working.
  ///
  /// With blocks on for the agent it opens as blocks, unless [terminal].
  Future<void> open(String id, {String? cwd, bool terminal = false}) async {
    final agent = recipe(id);
    if (stateOf(id).status != AgentStatus.installed && !busy) {
      await install(id);
      if (stateOf(id).status != AgentStatus.installed) return;
    } else if (!busy) {
      final present = await _run('apk info -e ${agent.allPackages.join(' ')} >/dev/null', (_) {});
      if (present != 0) {
        _installing = id;
        _states[id] = AgentState(AgentStatus.installing, step: agent.dependencies.label);
        notifyListeners();
        final log = StringBuffer();
        try {
          final code = await _run(agent.dependencies.script, (line) => log.writeln(line));
          _states[id] = code == 0
              ? const AgentState(AgentStatus.installed)
              : AgentState(AgentStatus.failed, message: _reason(log.toString(), code), log: log.toString());
          if (code != 0) return;
        } finally {
          _installing = null;
          notifyListeners();
        }
      }
    }
    if (!terminal && (openAsBlocks?.call(agent, cwd) ?? false)) return;
    final folder = cwd?.split('/').lastWhere((p) => p.isNotEmpty, orElse: () => '/');
    _launch(agent, folder == null ? agent.name : '${agent.name} · $folder', [agent.command], cwd);
  }

  static String _reason(String log, int code) {
    final lines = log.trim().split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith(r'$ ')).toList();
    final error = lines.lastWhere((l) => l.contains(RegExp('error|fail|denied|unreachable', caseSensitive: false)),
        orElse: () => lines.isEmpty ? '' : lines.last);
    return error.isEmpty ? 'Install failed (exit $code).' : error.trim();
  }
}
