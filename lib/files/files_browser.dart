import 'dart:io';
import 'package:flutter/foundation.dart';
import 'file_system_service.dart';

typedef Crumb = ({String label, String path});

/// The Files tab's state: where we are, browser-style back/forward history,
/// and the listing. Rooted at the shell's home folder.
class FilesBrowser extends ChangeNotifier {
  FilesBrowser({required String root, required this.rootfs}) : _root = root, _current = root;

  final _fs = FileSystemService();

  /// Alpine's root, so folders outside home show as "/ › etc".
  final String? rootfs;

  String _root;
  String _current;
  List<FsEntry> _entries = const [];
  bool _loaded = false;
  bool _showHidden = false;

  /// True when the last move went into a subfolder (or forward in history);
  /// the screen slides the new listing in from that side.
  bool movedDeeper = true;

  final _back = <String>[];
  final _forward = <String>[];

  /// Scroll offset per folder, restored when coming back.
  final offsets = <String, double>{};

  String get root => _root;
  String get current => _current;
  bool get loaded => _loaded;
  bool get showHidden => _showHidden;
  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  bool get canGoUp => parent != null;
  FileSystemService get fs => _fs;

  List<FsEntry> get entries => _showHidden ? _entries : _entries.where((e) => !e.name.startsWith('.')).toList();

  String? get parent => _current == crumbs.first.path ? null : Directory(_current).parent.path;

  /// Home-relative crumbs ("~ › src › lib"); folders outside home show from
  /// the distro root ("/ › etc").
  List<Crumb> get crumbs {
    String base, label;
    if (_current == _root || _current.startsWith('$_root/')) {
      (base, label) = (_root, '~');
    } else if (rootfs case final r? when _current.startsWith(r)) {
      (base, label) = (r, '/');
    } else {
      (base, label) = ('/', '/');
    }
    final out = <Crumb>[(label: label, path: base)];
    var path = base == '/' ? '' : base;
    for (final part in _current.substring(base.length).split('/')) {
      if (part.isEmpty) continue;
      path = '$path/$part';
      out.add((label: part, path: path));
    }
    return out;
  }

  /// Starts over at a new root (e.g. once Alpine is installed).
  Future<void> reset(String root) async {
    _root = root;
    _back.clear();
    _forward.clear();
    offsets.clear();
    await _show(root, deeper: true);
  }

  Future<void> load() => _show(_current, deeper: true);

  Future<void> open(String path) async {
    if (path == _current) return;
    _back.add(_current);
    _forward.clear();
    await _show(path, deeper: _isInside(path, _current));
  }

  Future<void> back() async {
    if (_back.isEmpty) return;
    _forward.add(_current);
    final to = _back.removeLast();
    await _show(to, deeper: _isInside(to, _current));
  }

  Future<void> forward() async {
    if (_forward.isEmpty) return;
    _back.add(_current);
    final to = _forward.removeLast();
    await _show(to, deeper: _isInside(to, _current));
  }

  Future<void> up() async {
    if (parent case final p?) await open(p);
  }

  /// Android back: history first, then the parent folder.
  bool handleBack() {
    if (canGoBack) {
      back();
      return true;
    }
    if (canGoUp) {
      up();
      return true;
    }
    return false;
  }

  Future<void> refresh() => _show(_current, deeper: movedDeeper, notifyOnly: true);

  void toggleHidden() {
    _showHidden = !_showHidden;
    notifyListeners();
  }

  // Loads first, then switches, so the old listing stays up until the new
  // one is ready (no spinner flash between folders).
  Future<void> _show(String path, {required bool deeper, bool notifyOnly = false}) async {
    final entries = await _fs.list(path);
    _current = path;
    _entries = entries;
    _loaded = true;
    if (!notifyOnly) movedDeeper = deeper;
    notifyListeners();
  }

  static bool _isInside(String path, String folder) => path.startsWith('$folder/');

  Future<void> create(String name, {required bool folder}) async {
    final path = '$_current/$name';
    folder ? await _fs.createFolder(path) : await _fs.createFile(path);
    await refresh();
  }

  Future<void> rename(FsEntry e, String name) async {
    await _fs.rename(e, name);
    await refresh();
  }

  Future<void> delete(FsEntry e) async {
    await _fs.delete(e);
    await refresh();
  }
}
