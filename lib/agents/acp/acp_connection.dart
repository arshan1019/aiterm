import 'dart:async';
import 'dart:convert';

/// An ACP agent process: one JSON-RPC message per line each way
/// (agentclientprotocol.com, "Transports"). stderr is the agent's log.
abstract class AcpTransport {
  /// stdout, split into lines.
  Stream<String> get lines;

  /// Writes one line to stdin.
  void send(String line);

  /// The last lines the agent logged (stderr), for error messages.
  String get log;

  Future<int> get exitCode;
  void kill();
}

/// An error from the agent (a JSON-RPC error), or the agent going away.
class AcpError implements Exception {
  const AcpError(this.code, this.message, [this.data]);

  final int code;
  final String message;
  final Object? data;

  /// ACP's "authentication required".
  static const authRequired = -32000;
  static const methodNotFound = -32601;
  static const internal = -32603;

  /// The process ended while a request was waiting.
  static const closed = -1;

  @override
  String toString() => message;
}

typedef AcpParams = Map<String, Object?>;

/// JSON-RPC 2.0 over an [AcpTransport]: requests out with matched
/// responses, notifications and requests in.
class AcpConnection {
  AcpConnection(
    this._transport, {
    required this.onNotification,
    required this.onRequest,
  }) {
    _sub = _transport.lines.listen(_onLine, onDone: _onDone);
  }

  final AcpTransport _transport;

  /// A notification from the agent (session/update).
  final void Function(String method, AcpParams params) onNotification;

  /// A request from the agent (session/request_permission); the result is
  /// sent back, an [AcpError] becomes an error response.
  final Future<Object?> Function(String method, AcpParams params) onRequest;

  late final StreamSubscription<String> _sub;
  final _pending = <int, Completer<AcpParams>>{};
  var _nextId = 0;
  var _closed = false;

  bool get closed => _closed;

  Future<AcpParams> request(String method, AcpParams params) {
    if (_closed) return Future.error(const AcpError(AcpError.closed, 'The agent stopped.'));
    final id = ++_nextId;
    final done = Completer<AcpParams>();
    _pending[id] = done;
    _write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return done.future;
  }

  void notify(String method, AcpParams params) {
    if (!_closed) _write({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void _write(Map<String, Object?> message) => _transport.send(jsonEncode(message));

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Map<String, Object?> m;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) return;
      m = decoded;
    } on FormatException {
      return; // Not a protocol message (a stray log line).
    }
    final id = m['id'];
    final method = m['method'];
    final params = m['params'] is Map ? (m['params'] as Map).cast<String, Object?>() : const <String, Object?>{};
    if (method is String) {
      if (id == null) {
        onNotification(method, params);
      } else {
        _answer(id, method, params);
      }
    } else if (id is int) {
      final done = _pending.remove(id);
      if (done == null) return;
      final error = m['error'];
      if (error is Map) {
        done.completeError(AcpError(
          (error['code'] as num?)?.toInt() ?? AcpError.internal,
          error['message'] as String? ?? 'Unknown error',
          error['data'],
        ));
      } else {
        final result = m['result'];
        done.complete(result is Map ? result.cast<String, Object?>() : const {});
      }
    }
  }

  Future<void> _answer(Object id, String method, AcpParams params) async {
    try {
      final result = await onRequest(method, params);
      if (!_closed) _write({'jsonrpc': '2.0', 'id': id, 'result': result ?? const <String, Object?>{}});
    } on AcpError catch (e) {
      if (!_closed) _write({'jsonrpc': '2.0', 'id': id, 'error': {'code': e.code, 'message': e.message}});
    } catch (e) {
      if (!_closed) _write({'jsonrpc': '2.0', 'id': id, 'error': {'code': AcpError.internal, 'message': '$e'}});
    }
  }

  void _onDone() {
    _closed = true;
    for (final done in _pending.values) {
      done.completeError(const AcpError(AcpError.closed, 'The agent stopped.'));
    }
    _pending.clear();
  }

  /// Stops the agent.
  Future<void> close() async {
    _transport.kill();
    await _sub.cancel();
    _onDone();
  }
}
