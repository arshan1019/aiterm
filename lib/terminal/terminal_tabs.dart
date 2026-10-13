import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'terminal_session.dart';

/// The open terminal tabs. Every tab comes back after the app restarts,
/// with its title, folder and scrollback (and a fresh shell). Pinned tabs
/// sit first and can't be closed by accident.
class TerminalTabs extends ChangeNotifier {
  TerminalTabs(String filesDir) : _file = File('$filesDir/terminal_tabs.json');

  final File _file;
  final _tabs = <TerminalSession>[];
  int _nextId = 1;
  int _activeId = 0;
  Timer? _saveTimer;

  List<TerminalSession> get tabs => List.unmodifiable(_tabs);
  int get activeId => _activeId;
  TerminalSession get active => _tabs.firstWhere((t) => t.id == _activeId);
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
      {bool customTitle = false, bool pinned = false, String? cwd, String? scrollback}) {
    final s = TerminalSession(
      id: _nextId++,
      title: title,
      customTitle: customTitle,
      pinned: pinned,
      restoredScrollback: scrollback == null || scrollback.isEmpty ? null : scrollback,
    )..cwd = cwd;
    s.onMetaChanged = () {
      _scheduleSave();
      notifyListeners();
    };
    s.onPersistable = _scheduleSave;
    _tabs.add(s);
    return s;
  }

  TerminalSession open() {
    final s = _add(_freshTitle());
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
    s.dispose();
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
    _tabs.remove(s);
    s.pinned = !s.pinned;
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
      t.dispose();
    }
    super.dispose();
  }
}
