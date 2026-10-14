import 'dart:io';
import '../phone/phone_files.dart';

enum EntryKind { file, directory, link, other }

class FsEntry {
  final String name;
  final String path;
  final EntryKind kind;
  final int size;
  final DateTime modified;

  FsEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    required this.modified,
  });
}

/// Files for the Files tab: local paths through dart:io, and phone folders
/// the user chose (`phone:` paths, see [PhonePath]) through [phone].
class FileSystemService {
  FileSystemService({this.phone});

  final PhoneFiles? phone;

  /// Display names of phone paths seen in listings (their segments are ids).
  final phoneNames = <String, String>{};

  Future<bool> isDirectory(String path) async =>
      PhonePath.isPhone(path) ? !path.contains('/f~') : Directory(path).exists();

  Future<List<FsEntry>> list(String path) async {
    if (PhonePath.isPhone(path)) return _sorted(await _listPhone(path));
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final entries = <FsEntry>[];
    await for (final e in dir.list(followLinks: false)) {
      final stat = await e.stat();
      EntryKind kind;
      if (e is Directory) {
        kind = EntryKind.directory;
      } else if (e is File) {
        kind = EntryKind.file;
      } else if (e is Link) {
        kind = EntryKind.link;
      } else {
        kind = EntryKind.other;
      }
      entries.add(FsEntry(
        name: e.uri.pathSegments.where((s) => s.isNotEmpty).last,
        path: e.path,
        kind: kind,
        size: stat.size,
        modified: stat.modified,
      ));
    }
    return _sorted(entries);
  }

  Future<List<FsEntry>> _listPhone(String path) async {
    final phone = this.phone;
    if (phone == null) return [];
    final entries = <FsEntry>[];
    if (path == PhonePath.root) {
      for (final g in phone.grants) {
        phoneNames[g.path] = g.name;
        entries.add(FsEntry(
          name: g.name,
          path: g.path,
          kind: g.isFolder ? EntryKind.directory : EntryKind.file,
          size: g.size,
          modified: DateTime.fromMillisecondsSinceEpoch(0),
        ));
      }
      return entries;
    }
    for (final e in await phone.list(PhonePath.parse(path)!)) {
      final child = PhonePath.child(path, e.doc);
      phoneNames[child] = e.name;
      entries.add(FsEntry(
        name: e.name,
        path: child,
        kind: e.isFolder ? EntryKind.directory : EntryKind.file,
        size: e.size,
        modified: e.modified,
      ));
    }
    return entries;
  }

  List<FsEntry> _sorted(List<FsEntry> entries) {
    entries.sort((a, b) {
      if (a.kind == EntryKind.directory && b.kind != EntryKind.directory) {
        return -1;
      }
      if (b.kind == EntryKind.directory && a.kind != EntryKind.directory) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// [path] is the new entry's path: its folder plus "/name".
  Future<void> createFolder(String path) =>
      PhonePath.isPhone(path) ? _createPhone(path, folder: true) : Directory(path).create(recursive: true);

  Future<void> createFile(String path) =>
      PhonePath.isPhone(path) ? _createPhone(path, folder: false) : File(path).create(recursive: true);

  Future<void> _createPhone(String path, {required bool folder}) {
    final i = path.lastIndexOf('/');
    return phone!.create(PhonePath.parse(path.substring(0, i))!, path.substring(i + 1), folder: folder);
  }

  Future<void> delete(FsEntry entry) async {
    if (PhonePath.isPhone(entry.path)) return phone!.delete(PhonePath.parse(entry.path)!);
    if (entry.kind == EntryKind.directory) {
      await Directory(entry.path).delete(recursive: true);
    } else {
      await File(entry.path).delete();
    }
  }

  Future<void> rename(FsEntry entry, String newName) async {
    if (PhonePath.isPhone(entry.path)) return phone!.rename(PhonePath.parse(entry.path)!, newName);
    final parent = Directory(entry.path).parent.path;
    final newPath = '$parent/$newName';
    if (entry.kind == EntryKind.directory) {
      await Directory(entry.path).rename(newPath);
    } else {
      await File(entry.path).rename(newPath);
    }
  }

  Future<String> readText(String path) =>
      PhonePath.isPhone(path) ? phone!.readText(PhonePath.parse(path)!) : File(path).readAsString();

  Future<void> writeText(String path, String contents) => PhonePath.isPhone(path)
      ? phone!.writeText(PhonePath.parse(path)!, contents)
      : File(path).writeAsString(contents);

  /// A rough heuristic for "is this safe to open in the text viewer".
  bool looksLikeText(String name) {
    const binaryExt = {
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.bmp',
      '.zip', '.tar', '.gz', '.xz', '.7z', '.apk', '.so', '.o',
      '.mp3', '.mp4', '.mov', '.avi', '.pdf',
    };
    final dot = name.lastIndexOf('.');
    if (dot == -1) return true;
    return !binaryExt.contains(name.substring(dot).toLowerCase());
  }
}
