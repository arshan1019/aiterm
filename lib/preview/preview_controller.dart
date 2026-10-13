import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ports.dart';

Uri previewUrl(int port) => Uri.parse('http://127.0.0.1:$port/');

/// Watches for dev servers started in the terminal and offers a preview.
/// Linux shares the app's network, so its localhost is reachable here.
class PreviewController extends ChangeNotifier {
  PreviewController({Future<bool> Function(int port)? probe}) {
    _watcher = PortWatcher(probe: probe, onAppeared: _appeared);
  }

  late final PortWatcher _watcher;
  Timer? _timer;
  int? _announced;

  /// A port that just started listening, offered for preview.
  int? get announced => _announced;

  List<int> get livePorts => _watcher.live.toList()..sort();

  /// Starts checking every few seconds; servers already up aren't announced.
  Future<void> start() async {
    await _watcher.check(announce: false);
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkNow() async {
    final before = livePorts;
    await _watcher.check();
    if (_announced != null && !_watcher.live.contains(_announced)) _announced = null;
    if (!listEquals(before, livePorts)) notifyListeners();
  }

  /// Ports a session's output mentioned; checked right away.
  void portsMentioned(Set<int> ports) {
    _watcher.hint(ports);
    checkNow();
  }

  void dismiss() {
    _announced = null;
    notifyListeners();
  }

  void _appeared(int port) {
    _announced = port;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
