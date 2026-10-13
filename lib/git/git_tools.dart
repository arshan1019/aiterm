import 'package:flutter/foundation.dart';

enum ToolsStatus { unknown, missing, installing, ready, failed }

/// Streams a script's output lines; returns its exit status.
typedef ToolsRunner = Future<int> Function(String script, void Function(String line) onLine);

/// git, GitHub's CLI and ssh in Linux, installed in one tap on first use.
class GitTools extends ChangeNotifier {
  GitTools({required this._run});

  static const packages = ['git', 'github-cli', 'openssh-client'];
  final ToolsRunner _run;

  ToolsStatus status = ToolsStatus.unknown;
  String? error;

  bool get ready => status == ToolsStatus.ready;

  Future<void> refresh() async {
    final code = await _run('command -v git >/dev/null && command -v gh >/dev/null && command -v ssh >/dev/null', (_) {});
    status = code == 0 ? ToolsStatus.ready : ToolsStatus.missing;
    notifyListeners();
  }

  /// Installs what's missing; true when everything is ready.
  Future<bool> ensure() async {
    if (status == ToolsStatus.ready) return true;
    if (status == ToolsStatus.installing) return false;
    status = ToolsStatus.installing;
    error = null;
    notifyListeners();
    final log = StringBuffer();
    final code = await _run('set -e\napk add -q --no-cache ${packages.join(' ')}', (l) => log.writeln(l));
    if (code != 0) {
      status = ToolsStatus.failed;
      error = log.toString().trim().split('\n').lastWhere((l) => l.trim().isNotEmpty, orElse: () => 'Install failed');
      notifyListeners();
      return false;
    }
    await refresh();
    return ready;
  }
}
