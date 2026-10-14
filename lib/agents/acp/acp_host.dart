import 'dart:async';
import 'acp_agents.dart';
import 'acp_connection.dart';

/// One chat's side of a shared [AcpHost]: its session's updates and the
/// agent's requests for it.
abstract class AcpSessionHandler {
  void onUpdate(AcpParams params);
  Future<Object?> onRequest(String method, AcpParams params);

  /// The agent process ended ([reason]: its last log line).
  void onHostExit(String reason);
}

/// One running ACP agent (its adapter process) in a folder, shared by every
/// chat with that agent there: ACP multiplexes sessions over a connection,
/// so a second Claude chat costs a session, not another Node process.
class AcpHost {
  AcpHost({required this.agent, required this.cwd, required this._start, required this._prepare});

  final AcpAgent agent;
  final String cwd;
  final AcpStarter _start;
  final AcpPreparer _prepare;

  AcpConnection? _connection;
  Future<void>? _starting;
  final _progress = <void Function(String)>{};
  final _handlers = <String, AcpSessionHandler>{};
  AcpSessionHandler? _opening;
  Future<void> _openLock = Future.value();
  var _disposed = false;

  /// What the agent said it can do (`agentCapabilities`).
  Map<Object?, Object?> capabilities = const {};

  bool get alive => _connection != null && !_connection!.closed;

  bool can(String sessionCapability) {
    final caps = capabilities['sessionCapabilities'];
    return caps is Map && caps.containsKey(sessionCapability);
  }

  /// Installs the adapter if needed and starts the agent, once; callers
  /// arriving meanwhile share the start. [onProgress] gets install output.
  /// Throws a [String] or [AcpError] when it can't.
  Future<void> ensure({void Function(String line)? onProgress}) {
    if (alive) return Future.value();
    if (onProgress != null) _progress.add(onProgress);
    return _starting ??= _boot().whenComplete(() {
      _starting = null;
      _progress.clear();
    });
  }

  Future<void> _boot() async {
    final problem = await _prepare(agent, (line) {
      for (final p in _progress) {
        p(line);
      }
    });
    if (problem != null) throw problem;
    if (_disposed) throw 'Closed.';
    final transport = await _start(agent, cwd);
    final connection = AcpConnection(transport, onNotification: _onNotification, onRequest: _onRequest);
    _connection = connection;
    transport.exitCode.then((_) {
      if (_connection != connection) return;
      _connection = null;
      final lines = transport.log.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      final reason = lines.isEmpty ? 'The agent stopped.' : lines.last;
      for (final h in [..._handlers.values, ?_opening]) {
        h.onHostExit(reason);
      }
    });
    final init = await connection.request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        // Agents use their own tools for files and commands.
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
        // Questions (Claude's AskUserQuestion) arrive as forms.
        'elicitation': {'form': <String, Object?>{}},
      },
      'clientInfo': {'name': 'aiterm', 'version': '1.0.0'},
    });
    capabilities = (init['agentCapabilities'] as Map?) ?? const {};
  }

  Future<AcpParams> request(String method, AcpParams params) {
    final connection = _connection;
    if (connection == null) return Future.error(const AcpError(AcpError.closed, 'The agent stopped.'));
    return connection.request(method, params);
  }

  void notify(String method, AcpParams params) => _connection?.notify(method, params);

  /// Runs [body] (a session/new or session/load) with [handler] receiving
  /// updates for the session whose id isn't known yet. One at a time.
  Future<T> opening<T>(AcpSessionHandler handler, Future<T> Function() body) {
    final run = _openLock.then((_) async {
      _opening = handler;
      try {
        return await body();
      } finally {
        if (_opening == handler) _opening = null;
      }
    });
    _openLock = run.then((_) {}, onError: (_) {});
    return run;
  }

  void attach(String sessionId, AcpSessionHandler handler) => _handlers[sessionId] = handler;

  void detach(String sessionId, AcpSessionHandler handler) {
    if (_handlers[sessionId] == handler) _handlers.remove(sessionId);
  }

  AcpSessionHandler? _handlerFor(AcpParams params) {
    final id = params['sessionId'];
    return (id is String ? _handlers[id] : null) ?? _opening;
  }

  void _onNotification(String method, AcpParams params) {
    if (method == 'session/update') _handlerFor(params)?.onUpdate(params);
  }

  Future<Object?> _onRequest(String method, AcpParams params) {
    final handler = _handlerFor(params);
    if (handler == null) return Future.error(const AcpError(AcpError.methodNotFound, 'No such session'));
    return handler.onRequest(method, params);
  }

  /// Stops the agent (the last chat with it closed).
  Future<void> dispose() async {
    _disposed = true;
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }
}
