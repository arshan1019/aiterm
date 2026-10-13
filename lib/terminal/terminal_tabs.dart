import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'terminal_session.dart';

/// The open terminal tabs. Pinned tabs sit first, can't be closed by
/// accident, and are reopened (with a fresh shell) when the app starts.
class TerminalTabs extends ChangeNotifier {
  TerminalTabs(String filesDir) : _file = File('$filesDir/terminal_tabs.json');

  final File _file;
  final _tabs = <TerminalSession>[];
  int _nextId = 1;
  int _activeId = 0;

  List<TerminalSession> get tabs => List.unmodifiable(_tabs);
  int get activeId => _activeId;
  TerminalSession get active => _tabs.firstWhere((t) => t.id == _activeId);
  int get activeIndex => _tabs.indexWhere((t) => t.id == _activeId);

  /// Reopens pinned tabs, or one plain tab.
  Future<void> load() async {
    try {
      final saved = jsonDecode(await _file.readAsString()) as List;
      for (final t in saved.cast<Map<String, dynamic>>()) {
        _add(t['title'] as String, customTitle: t['custom'] == true, pinned: true);
      }
    } catch (_) {
      // First run or unreadable file.
    }
    if (_tabs.isEmpty) _add(_freshTitle());
    _activeId = _tabs.first.id;
  }

  TerminalSession _add(String title, {bool customTitle = false, bool pinned = false}) {
    final s = TerminalSession(id: _nextId++, title: title, customTitle: customTitle, pinned: pinned);
    s.onMetaChanged = () {
      if (s.pinned) _save();
      notifyListeners();
    };
    _tabs.add(s);
    return s;
  }

  TerminalSession open() {
    final s = _add(_freshTitle());
    _activeId = s.id;
    notifyListeners();
    return s;
  }

  void select(TerminalSession s) {
    if (s.id == _activeId) return;
    _activeId = s.id;
    notifyListeners();
  }

  void close(TerminalSession s) {
    final i = _tabs.indexOf(s);
    if (i < 0) return;
    _tabs.removeAt(i);
    s.dispose();
    if (_tabs.isEmpty) _add(_freshTitle());
    if (s.id == _activeId) _activeId = _tabs[i.clamp(0, _tabs.length - 1)].id;
    if (s.pinned) _save();
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
    _save();
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

  void _save() {
    final pinned = [
      for (final t in _tabs.where((t) => t.pinned)) {'title': t.title, 'custom': t.customTitle},
    ];
    _file.writeAsString(jsonEncode(pinned)).ignore();
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }
}
