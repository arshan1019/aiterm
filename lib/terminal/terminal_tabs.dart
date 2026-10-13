import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../platform/pty.dart';
import 'terminal_session.dart';

/// The open terminal tabs. Every tab comes back after the app restarts,
/// with its title, folder and scrollback (and a fresh shell). Pinned tabs
/// sit first and can't be closed by accident.
class TerminalTabs extends ChangeNotifier {
  TerminalTabs(String filesDir, {PtyBackend? backend})
      : _file = File('$filesDir/terminal_tabs.json'),
        _backend = backend ?? PtyHost.instance;

  final File _file;
  final PtyBackend _backend;
  final _tabs = <TerminalSession>[];
  int _nextId = 1;
  int _activeId = 0;
  Timer? _saveTimer;

  /// Ports any tab's output mentioned (for the preview watcher).
  void Function(Set<int> ports)? onPortsMentioned;

  /// Finished commands, notifications and bells from any tab.
  void Function(TerminalSession session, SessionSignal signal)? onSignal;

  List<TerminalSession> get tabs => List.unmodifiable(_tabs);
  int get activeId => _activeId;
  TerminalSession get active => _tabs.firstWhere((t) => t.id == _activeId, orElse: () => _tabs.first);
  int get activeIndex => _tabs.indexWhere((t) => t.id == _activeId);

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
          );
        }
        active = saved['active'] as int? ?? 0;
      }
    } catch (_) {
      // First run, or an unreadable file: start fresh.
      for (final t in _tabs) {
        t.dispose();
      }
      _tabs.clear();
      active = 0;
    }
    if (_tabs.isEmpty) _add(_freshTitle());
    _activeId = _tabs[active.clamp(0, _tabs.length - 1)].id;
  }

  TerminalSession _add(String title,
      {bool customTitle = false,
      bool pinned = false,
      String? cwd,
      String? scrollback,
      int? ptyId,
      List<String> commands = const []}) {
    final s = TerminalSession(
      id: _nextId++,
      title: title,
      customTitle: customTitle,
      pinned: pinned,
      restoredScrollback: scrollback == null || scrollback.isEmpty ? null : scrollback,
      savedPtyId: ptyId,
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
  /// [title] names the tab; [commands] run once its shell starts.
  TerminalSession open({String? cwd, String? title, List<String> commands = const []}) {
    final name = title ?? cwd?.split('/').lastWhere((p) => p.isNotEmpty, orElse: () => '/');
    final s = _add(name ?? _freshTitle(), cwd: cwd, customTitle: title != null, commands: commands);
    _activeId = s.id;
    _scheduleSave();
    notifyListeners();
    return s;
  }

  void select(TerminalSession s) {
    if (s.id == _activeId) return;
    _activeId = s.id;
    _scheduleSave();
    notifyListeners();
  }

  void close(TerminalSession s) {
    final i = _tabs.indexOf(s);
    if (i < 0) return;
    _tabs.removeAt(i);
    s.dispose(); // closing a tab ends its shell
    if (_tabs.isEmpty) _add(_freshTitle());
    if (s.id == _activeId) _activeId = _tabs[i.clamp(0, _tabs.length - 1)].id;
    _scheduleSave();
    notifyListeners();
  }

  void closeOthers(TerminalSession keep) {
    for (final t in _tabs.where((t) => t != keep && !t.pinned).toList()) {
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
    final used = _tabs.map((t) => t.title).toSet();
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
      'tabs': [
        for (final t in _tabs)
          {
            'title': t.title,
            'custom': t.customTitle,
            'pinned': t.pinned,
            'cwd': t.cwd,
            'scrollback': t.scrollbackText(),
            'pty': t.ptyId,
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
