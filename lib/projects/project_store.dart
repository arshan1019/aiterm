import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../shared/fs_atomic.dart';
import 'project.dart';

class ProjectExists implements Exception {
  const ProjectExists(this.path);
  final String path;
  @override
  String toString() => 'A project already uses $path';
}

/// The user's projects, saved as JSON; most recently opened first.
class ProjectStore extends ChangeNotifier {
  ProjectStore(this._file);

  final String _file;
  var _projects = <Project>[];

  List<Project> get projects => List.unmodifiable(_projects);

  Future<void> load() async {
    try {
      final list = jsonDecode(await File(_file).readAsString()) as List;
      _projects = [for (final j in list.cast<Map<String, dynamic>>()) Project.fromJson(j)];
      _sort();
    } catch (_) {
      _projects = [];
    }
    notifyListeners();
  }

  Project? byPath(String path) => _projects.where((p) => p.path == path).firstOrNull;

  Future<Project> add({required String name, required String path}) async {
    if (byPath(path) != null) throw ProjectExists(path);
    final now = DateTime.now();
    final p = Project(id: '${now.microsecondsSinceEpoch}', name: name, path: path, createdAt: now, lastOpened: now);
    _projects.insert(0, p);
    await _save();
    return p;
  }

  /// Agent [agentId] was opened in [path]: that folder becomes (or stays)
  /// the most recent project, remembering the agent. Home and / aren't
  /// projects (null).
  Future<Project?> usedAgent(String path, String agentId) async {
    if (path == '/' || path == '/root') return null;
    final now = DateTime.now();
    final existing = byPath(path);
    if (existing != null) {
      await _replace(existing, existing.copyWith(lastOpened: now, agentId: agentId));
      return byPath(path);
    }
    final p = Project(
        id: '${now.microsecondsSinceEpoch}',
        name: path.split('/').lastWhere((x) => x.isNotEmpty),
        path: path,
        createdAt: now,
        lastOpened: now,
        agentId: agentId);
    _projects.insert(0, p);
    await _save();
    return p;
  }

  Future<void> opened(Project p) => _replace(p, p.copyWith(lastOpened: DateTime.now()));

  Future<void> rename(Project p, String name) => _replace(p, p.copyWith(name: name));

  /// Forgets the project (its folder is untouched).
  Future<void> remove(Project p) async {
    _projects.removeWhere((x) => x.id == p.id);
    await _save();
  }

  /// Puts back a project [remove] took out (Undo).
  Future<void> restore(Project p) async {
    if (_projects.any((x) => x.id == p.id || x.path == p.path)) return;
    _projects.add(p);
    _sort();
    await _save();
  }

  Future<void> _replace(Project old, Project updated) async {
    final i = _projects.indexWhere((x) => x.id == old.id);
    if (i < 0) return;
    _projects[i] = updated;
    _sort();
    await _save();
  }

  void _sort() => _projects.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

  Future<void> _save() async {
    notifyListeners();
    await File(_file).parent.create(recursive: true);
    await writeFileAtomic(_file, jsonEncode([for (final p in _projects) p.toJson()]));
  }
}
