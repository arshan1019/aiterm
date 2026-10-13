import 'dart:async';
import 'dart:io';

final _ansi = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]');
final _localUrl = RegExp(r'https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\]):(\d{2,5})');
final _hostPort = RegExp(r'\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{2,5})\b');
final _listening = RegExp(r'\b(?:listening on|running on|on) port (\d{2,5})\b', caseSensitive: false);

/// Local ports a program says it's serving on, from its output banner
/// ("Local: http://localhost:5173/", "listening on port 4000").
Set<int> portsMentionedIn(String output) {
  final text = output.replaceAll(_ansi, '');
  return {
    for (final re in [_localUrl, _hostPort, _listening])
      for (final m in re.allMatches(text))
        if (int.parse(m.group(1)!) case final p when p > 0 && p < 65536) p,
  };
}

/// Ports dev servers commonly use (Next/React, Angular, Flask, Vite,
/// Django/python -m http.server, generic).
const commonDevPorts = {3000, 3001, 4200, 5000, 5173, 8000, 8080, 8888};

/// Knows which local ports are accepting connections, checking hinted ports
/// (seen in output) and common dev ports, and announces newly opened ones.
class PortWatcher {
  PortWatcher({Future<bool> Function(int port)? probe, required this.onAppeared})
      : _probe = probe ?? _tcpProbe;

  final Future<bool> Function(int port) _probe;
  final void Function(int port) onAppeared;

  final _hinted = <int>{};
  final _live = <int>{};
  Set<int> get live => Set.unmodifiable(_live);

  void hint(Iterable<int> ports) => _hinted.addAll(ports);

  /// Probes every candidate once. With [announce] false, only records the
  /// current state (so servers that were already up aren't announced).
  Future<void> check({bool announce = true}) async {
    final candidates = {...commonDevPorts, ..._hinted, ..._live};
    final results = await Future.wait(candidates.map((p) async => (p, await _probe(p))));
    for (final (port, open) in results) {
      if (open && _live.add(port) && announce) onAppeared(port);
      if (!open) _live.remove(port);
    }
  }

  static Future<bool> _tcpProbe(int port) async {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 250));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
