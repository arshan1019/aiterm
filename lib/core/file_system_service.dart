import 'dart:io';

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

/// Thin wrapper around dart:io for the file explorer. Rooted at whatever
/// [rootPath] the caller picks (the app's sandbox dir today; the Linux
/// rootfs home directory once the distro backend lands).
class FileSystemService {
  Future<List<FsEntry>> list(String path) async {
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

  Future<void> createFolder(String path) => Directory(path).create(recursive: true);

  Future<void> createFile(String path) => File(path).create(recursive: true);

  Future<void> delete(FsEntry entry) async {
    if (entry.kind == EntryKind.directory) {
      await Directory(entry.path).delete(recursive: true);
    } else {
      await File(entry.path).delete();
    }
  }

  Future<void> rename(FsEntry entry, String newName) async {
    final parent = Directory(entry.path).parent.path;
    final newPath = '$parent/$newName';
    if (entry.kind == EntryKind.directory) {
      await Directory(entry.path).rename(newPath);
    } else {
      await File(entry.path).rename(newPath);
    }
  }

  Future<String> readText(String path) => File(path).readAsString();

  Future<void> writeText(String path, String contents) =>
      File(path).writeAsString(contents);

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
