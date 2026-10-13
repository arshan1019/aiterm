import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../platform/pty.dart';
import 'terminal_session.dart';

/// The open terminal tabs. Every tab comes back after the app restarts,
/// with its title, folder and scrollback (and a fresh shell). Pinned tabs
/// sit first and can't be closed by accident.
///
/// Tabs are grouped by scope: a project's tabs show in its workspace, the
/// rest (scope null) in the Terminal tab, which always has at least one.
/// Each scope remembers its selected tab.
class TerminalTabs extends ChangeNotifier {
  TerminalTabs(String filesDir, {PtyBackend? backend})
      : _file = File('$filesDir/terminal_tabs.json'),
        _backend = backend ?? PtyHost.instance;

  final File _file;
  final PtyBackend _backend;
  final _tabs = <TerminalSession>[];
  int _nextId = 1;
  int _activeId = 0;
  final _activeByScope = <String?, int>{};
  Timer? _saveTimer;

  /// Ports any tab's output mentioned (for the preview watcher).
  void Function(Set<int> ports)? onPortsMentioned;

  /// Finished commands, notifications and bells from any tab.
  void Function(TerminalSession session, SessionSignal signal)? onSignal;

  List<TerminalSession> get tabs => List.unmodifiable(_tabs);
  int get activeId => _activeId;

  /// The tab selected last, in any scope.
  TerminalSession get active => _tabs.firstWhere((t) => t.id == _activeId, orElse: () => activeIn(null)!);
  int get activeIndex => _tabs.indexWhere((t) => t.id == _activeId);

  /// [project]'s tabs (null: the Terminal tab's).
  List<TerminalSession> inScope(String? project) => [for (final t in _tabs) if (t.project == project) t];

  /// The selected tab of [project] (null: the Terminal tab's), if it has any.
  TerminalSession? activeIn(String? project) {
    final list = inScope(project);
    final id = _activeByScope[project];
    return list.where((t) => t.id == id).firstOrNull ?? list.firstOrNull;
  }

  /// [project] was removed: its tabs move to the Terminal tab.
  void detachProject(String project) {
    for (final t in inScope(project)) {
      t.project = null;
    }
    _activeByScope.remove(project);
    notifyListeners();
  }

  Future<void> load() async {
    var active = 0;
    try {
      final saved = jsonDecode(await _file.readAsString());
      if (saved is List) {
        // v1: only pinned tabs, titles only.
        for (final t in saved.cast<Map<String, dynamic>>()) {
          _add(t['title'] as String, customTitle: t['custom'] == true, pinned: true);
        }
      } else if (saved is Map<String, dynamic>) {
        for (final t in (saved['tabs'] as List).cast<Map<String, dynamic>>()) {
          _add(
            t['title'] as String,
            customTitle: t['custom'] == true,
            pinned: t['pinned'] == true,
            cwd: t['cwd'] as String?,
            scrollback: t['scrollback'] as String?,
            ptyId: t['pty'] as int?,
            project: t['project'] as String?,
            agent: t['agent'] as String?,
            launch: (t['launch'] as List?)?.cast<String>() ?? const [],
            // A fresh shell (the old one is gone) runs what the tab was
            // opened for; a reattached one never starts, so never reruns.
            commands: (t['launch'] as List?)?.cast<String>() ?? const [],
          );
        }
        active = saved['active'] as int? ?? 0;
        if (saved['scopes'] case final Map<String, dynamic> scopes) {
          for (final MapEntry(key: scope, value: index) in scopes.entries) {
            if (index is int && index >= 0 && index < _tabs.length) {
              _activeByScope[scope.isEmpty ? null : scope] = _tabs[index].id;
            }
          }
        }
      }
    } catch (_) {
      // First run, or an unreadable file: start fresh.
      for (final t in _tabs) {
        t.dispose();
      }
      _tabs.clear();
      active = 0;
    }
    _ensureGlobal();
    _activeId = _tabs[active.clamp(0, _tabs.length - 1)].id;
    _activeByScope.putIfAbsent(_tabs.firstWhere((t) => t.id == _activeId).project, () => _activeId);
  }

  /// The Terminal tab always has a shell.
  void _ensureGlobal() {
    if (inScope(null).isEmpty) _add(_freshTitle());
  }

  TerminalSession _add(String title,
      {bool customTitle = false,
      bool pinned = false,
      String? cwd,
      String? scrollback,
      int? ptyId,
      String? project,
      String? agent,
      List<String> launch = const [],
      List<String> commands = const []}) {
    final s = TerminalSession(
      id: _nextId++,
      title: title,
      customTitle: customTitle,
      pinned: pinned,
      restoredScrollback: scrollback == null || scrollback.isEmpty ? null : scrollback,
      savedPtyId: ptyId,
      project: project,
      agent: agent,
      launch: launch,
      startupCommands: commands,
      backend: _backend,
    )..cwd = cwd;
    s.onMetaChanged = () {
      _scheduleSave();
      notifyListeners();
    };
    s.onPersistable = _scheduleSave;
    s.onPortsMentioned = (ports) => onPortsMentioned?.call(ports);
    s.onSignal = (signal) => onSignal?.call(s, signal);
    s.state.addListener(notifyListeners); // e.g. a shell started or exited
    _tabs.add(s);
    return s;
  }

  /// Reconnects tabs to shells that kept running in the background service
  /// while the UI was gone (e.g. the app was swiped away).
  Future<void> reattach() async {
    final live = (await _backend.liveSessions()).toSet();
    for (final t in _tabs) {
      final id = t.savedPtyId;
      if (id == null || !live.contains(id)) continue;
      if (await _backend.attach(id) case final a?) t.attach(a);
    }
  }

  /// A new tab, starting in [cwd] (a guest path) if given and named after it.
  /// [title] names the tab; [commands] run once its shell starts (and again
  /// whenever it gets a fresh shell). [project] and [agent] say what it's for.
  TerminalSession open({String? cwd, String? title, List<String> commands = const [], String? project, String? agent}) {
    final name = title ?? cwd?.split('/').lastWhere((p) => p.isNotEmpty, orElse: () => '/');
    final s = _add(name ?? _freshTitle(),
        cwd: cwd, customTitle: title != null, commands: commands, launch: commands, project: project, agent: agent);
    _activeId = s.id;
    _activeByScope[project] = s.id;
    _scheduleSave();
    notifyListeners();
    return s;
  }

  /// The tab running [agent] for [project], to go back to instead of
  /// opening another.
  TerminalSession? findAgent(String agent, String? project) =>
      _tabs.where((t) => t.agent == agent && t.project == project).firstOrNull;

  void select(TerminalSession s) {
    if (s.id == _activeId && _activeByScope[s.project] == s.id) return;
    _activeId = s.id;
    _activeByScope[s.project] = s.id;
    _scheduleSave();
    notifyListeners();
  }

  void close(TerminalSession s) {
    final scope = inScope(s.project);
    final i = scope.indexOf(s);
    if (i < 0) return;
    _tabs.remove(s);
    scope.removeAt(i);
    s.dispose(); // closing a tab ends its shell
    if (_activeByScope[s.project] == s.id) {
      if (scope.isEmpty) {
        _activeByScope.remove(s.project);
      } else {
        _activeByScope[s.project] = scope[i.clamp(0, scope.length - 1)].id;
      }
    }
    _ensureGlobal();
    if (s.id == _activeId) _activeId = (activeIn(s.project) ?? activeIn(null)!).id;
    _scheduleSave();
    notifyListeners();
  }

  void closeOthers(TerminalSession keep) {
    for (final t in inScope(keep.project).where((t) => t != keep && !t.pinned).toList()) {
      close(t);
    }
  }

  /// Pins or unpins [s], keeping pinned tabs grouped at the front in the
  /// order they were pinned.
  void togglePin(TerminalSession s) {
    // Flip first: listeners run while the tab is still in the list.
    s.pinned = !s.pinned;
    _tabs.remove(s);
    _tabs.insert(_tabs.where((t) => t.pinned).length, s);
    _scheduleSave();
    notifyListeners();
  }

  String _freshTitle() {
    final used = inScope(null).map((t) => t.title).toSet();
    if (!used.contains('shell')) return 'shell';
    var n = 2;
    while (used.contains('shell $n')) {
      n++;
    }
    return 'shell $n';
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  /// Writes every tab to disk now (also called when the app goes to the
  /// background). Atomic: a crash mid-write leaves the previous file.
  Future<void> save() async {
    _saveTimer?.cancel();
    final data = {
      'version': 2,
      'active': activeIndex,
      'scopes': {
        for (final MapEntry(key: scope, value: id) in _activeByScope.entries)
          if (_tabs.indexWhere((t) => t.id == id) case final i when i >= 0) scope ?? '': i,
      },
      'tabs': [
        for (final t in _tabs)
          {
            'title': t.title,
            'custom': t.customTitle,
            'pinned': t.pinned,
            'cwd': t.cwd,
            'scrollback': t.scrollbackText(),
            'pty': t.ptyId,
            'project': ?t.project,
            'agent': ?t.agent,
            if (t.launch.isNotEmpty) 'launch': t.launch,
          },
      ],
    };
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(_file.path);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final t in _tabs) {
      // The UI is going away, not the user closing tabs: shells live on.
      t.dispose(stopShell: false);
    }
    super.dispose();
  }
}
