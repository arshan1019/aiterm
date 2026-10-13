import 'dart:io';
import 'package:flutter/foundation.dart';
import 'file_system_service.dart';

enum ClipMode { copy, cut }

/// Copy / Cut / Paste across locations (Linux home ↔ phone storage), so
/// project files and assets move both ways. Paste never overwrites: a name
/// that exists gets a numbered copy ("notes (2).txt").
class FileClipboard extends ChangeNotifier {
  List<FsEntry> _items = const [];
  ClipMode _mode = ClipMode.copy;

  bool get hasItems => _items.isNotEmpty;
  ClipMode get mode => _mode;
  List<FsEntry> get items => _items;

  void copy(List<FsEntry> entries) => _set(entries, ClipMode.copy);
  void cut(List<FsEntry> entries) => _set(entries, ClipMode.cut);

  void clear() => _set(const [], ClipMode.copy);

  void _set(List<FsEntry> entries, ClipMode mode) {
    _items = List.unmodifiable(entries);
    _mode = mode;
    notifyListeners();
  }

  /// Pastes into folder [dest]; returns the new paths. A cut is used up.
  Future<List<String>> paste(String dest) async {
    final created = <String>[];
    for (final e in _items) {
      final isDir = e.kind == EntryKind.directory;
      if (isDir && (dest == e.path || dest.startsWith('${e.path}/'))) {
        throw FileSystemException('A folder can\'t be pasted inside itself', dest);
      }
      final sameFolder = File(e.path).parent.path == dest;
      if (_mode == ClipMode.cut && sameFolder) continue; // moving onto itself
      final target = await _freeName(dest, e.name);
      if (_mode == ClipMode.cut) {
        await _move(e, target);
      } else {
        await _copy(e.path, target, isDir);
      }
      created.add(target);
    }
    if (_mode == ClipMode.cut) clear();
    return created;
  }

  static Future<String> _freeName(String dir, String name) async {
    var candidate = '$dir/$name';
    if (FileSystemEntity.typeSync(candidate, followLinks: false) == FileSystemEntityType.notFound) return candidate;
    final dot = name.lastIndexOf('.');
    final (stem, ext) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
    for (var n = 2;; n++) {
      candidate = '$dir/$stem ($n)$ext';
      if (FileSystemEntity.typeSync(candidate, followLinks: false) == FileSystemEntityType.notFound) return candidate;
    }
  }

  static Future<void> _move(FsEntry e, String target) async {
    try {
      await FileSystemEntity.isDirectory(e.path)
          ? await Directory(e.path).rename(target)
          : await File(e.path).rename(target);
    } on FileSystemException {
      // Different storage (app files ↔ phone storage): copy, then delete.
      final isDir = e.kind == EntryKind.directory;
      await _copy(e.path, target, isDir);
      isDir ? await Directory(e.path).delete(recursive: true) : await File(e.path).delete();
    }
  }

  static Future<void> _copy(String from, String to, bool isDir) async {
    if (!isDir) {
      await File(from).copy(to);
      return;
    }
    await Directory(to).create(recursive: true);
    await for (final child in Directory(from).list(followLinks: false)) {
      final name = child.path.substring(from.length + 1);
      final dest = '$to/$name';
      if (child is Link) {
        await Link(dest).create(await child.target());
      } else if (child is Directory) {
        await _copy(child.path, dest, true);
      } else {
        await File(child.path).copy(dest);
      }
    }
  }
}
