import 'dart:io';
import '../git/git_repo.dart';
import '../git/git_runner.dart';
import 'project.dart';
import 'project_store.dart';
import 'templates.dart';

class FolderNotEmpty implements Exception {
  const FolderNotEmpty(this.path);
  final String path;
  @override
  String toString() => 'That folder already has files. Use "Open existing folder" instead.';
}

/// "my App!" → "my-app": a folder / package name.
String folderNameFor(String name) {
  final s = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-').replaceAll(RegExp(r'-+'), '-');
  return s.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '').isEmpty ? 'project' : s.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
}

/// The repository name in a clone URL ("…/rocket.git" → "rocket").
String repoNameFor(String url) {
  final last = url.trim().replaceAll(RegExp(r'/+$'), '').split(RegExp(r'[/:]')).last;
  return last.endsWith('.git') ? last.substring(0, last.length - 4) : last;
}

/// Creating and opening projects. Project folders are guest paths (as the
/// shell sees them); [hostPath] maps them for file operations.
class ProjectService {
  ProjectService({required this.store, required this.git, required this.hostPath});

  final ProjectStore store;
  final GitRunner git;
  final String Function(String guestPath) hostPath;

  Future<void> _check(Future<GitResult> r) async {
    final result = await r;
    if (!result.ok) throw mapGitError(result);
  }

  Future<Project> createEmpty({required String name, required String path}) async {
    await _makeEmptyFolder(path);
    await _check(git.run(path, ['init', '-q']));
    return store.add(name: name, path: path);
  }

  Future<Project> createFromTemplate(ProjectTemplate t, {required String name, required String path}) async {
    await _makeEmptyFolder(path);
    for (final MapEntry(key: file, value: text) in t.files.entries) {
      final f = File('${hostPath(path)}/$file');
      await f.parent.create(recursive: true);
      await f.writeAsString(text.replaceAll('{{name}}', name).replaceAll('{{slug}}', folderNameFor(name)));
    }
    await _check(git.run(path, ['init', '-q']));
    return store.add(name: name, path: path);
  }

  /// Clones [url] into [path] (whose parent must exist or be creatable).
  Future<Project> clone(String url, {required String path, String? name}) async {
    final parent = Directory(hostPath(path)).parent;
    await parent.create(recursive: true);
    if (await Directory(hostPath(path)).exists() && !await Directory(hostPath(path)).list().isEmpty) {
      throw FolderNotEmpty(path);
    }
    // A local source would be hard-linked by default, which proot emulates
    // with symlinks; copy instead.
    final local = url.startsWith('/') || url.startsWith('file://');
    await _check(git.run(Directory(path).parent.path, ['clone', '-q', if (local) '--no-hardlinks', url, path]));
    return store.add(name: name ?? path.split('/').last, path: path);
  }

  /// Makes an existing folder a project (git or not). On phone storage,
  /// which keeps no file modes, git is told not to track them (as git does
  /// itself for repos it creates there).
  Future<Project> openExisting(String path, {String? name}) async {
    if (onPhoneStorage(path) && await isRepo(path)) await git.run(path, ['config', 'core.fileMode', 'false']);
    return store.byPath(path) ?? await store.add(name: name ?? path.split('/').last, path: path);
  }

  Future<bool> isRepo(String path) async {
    final r = await git.run(path, ['rev-parse', '--show-toplevel']);
    return r.ok && r.stdout.trim() == path;
  }

  Future<void> initGit(Project p) => _check(git.run(p.path, ['init', '-q']));

  Future<void> _makeEmptyFolder(String path) async {
    final dir = Directory(hostPath(path));
    if (await dir.exists() && !await dir.list().isEmpty) throw FolderNotEmpty(path);
    await dir.create(recursive: true);
  }
}
