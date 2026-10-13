import 'package:flutter/foundation.dart';

enum SetupState { waiting, running, done, failed }

class SetupStep {
  SetupStep(this.id, this.label);

  /// 'linux', 'tools', or an agent id.
  final String id;
  final String label;
  SetupState state = SetupState.waiting;

  /// What the running step is doing now ("Downloading Alpine").
  String? detail;
  double? progress;
  String? error;
}

/// First run as one wait: Linux, then git and GitHub's tools, then the
/// agents the user picked, installed back to back with one progress list.
/// Linux failing stops the rest (everything needs it); a tool or agent
/// failing doesn't stop the others. Retry runs only what isn't done.
class SetupPipeline extends ChangeNotifier {
  SetupPipeline({
    required this.installLinux,
    required this.linuxReady,
    required this.installTools,
    required this.installAgent,
    required this.agentName,
  });

  /// Throws on failure.
  final Future<void> Function(void Function(String status, double? progress) onProgress) installLinux;
  final bool Function() linuxReady;

  /// Each returns null on success, or why it failed.
  final Future<String?> Function() installTools;
  final Future<String?> Function(String agentId) installAgent;
  final String Function(String agentId) agentName;

  List<SetupStep> steps = const [];
  bool _running = false;
  bool _left = true;

  bool get running => _running;

  /// Setup is on screen: running, or finished with something to retry.
  bool get active => !_left;

  bool get failed => steps.any((s) => s.state == SetupState.failed);

  /// Leaving with failures is fine once Linux works (agents can be
  /// installed later from their page).
  bool get canSkip => !_running && failed && steps.isNotEmpty && steps.first.state == SetupState.done;

  Future<void> start(List<String> agents) {
    steps = [
      SetupStep('linux', 'Linux system'),
      SetupStep('tools', 'Git and GitHub tools'),
      for (final id in agents) SetupStep(id, agentName(id)),
    ];
    _left = false;
    return _run();
  }

  Future<void> retry() => _run();

  void skip() {
    _left = true;
    notifyListeners();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    notifyListeners();
    for (final step in steps) {
      if (step.state == SetupState.done) continue;
      step
        ..state = SetupState.running
        ..error = null
        ..detail = null
        ..progress = null;
      notifyListeners();
      final error = await _runStep(step);
      step
        ..state = error == null ? SetupState.done : SetupState.failed
        ..error = error
        ..detail = null
        ..progress = null;
      notifyListeners();
      if (error != null && step.id == 'linux') break;
    }
    _running = false;
    if (!failed) _left = true;
    notifyListeners();
  }

  Future<String?> _runStep(SetupStep step) async {
    try {
      switch (step.id) {
        case 'linux':
          if (linuxReady()) return null;
          await installLinux((status, progress) {
            step
              ..detail = status
              ..progress = progress;
            notifyListeners();
          });
          return null;
        case 'tools':
          return await installTools();
        default:
          return await installAgent(step.id);
      }
    } catch (e) {
      return '$e'.replaceFirst('Exception: ', '');
    }
  }
}
