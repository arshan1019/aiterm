import 'git_repo.dart';
import 'git_runner.dart';

/// Which repository a folder belongs to, and one shared [GitRepo] per
/// repository (so every screen showing it sees the same live status).
class GitRegistry {
  GitRegistry(this.runner);

  final GitRunner runner;
  final _roots = <String, String?>{};
  final _repos = <String, GitRepo>{};

  /// The repository root containing [folder], or null if it isn't in one.
  Future<String?> rootFor(String folder) async {
    if (_roots.containsKey(folder)) return _roots[folder];
    final r = await runner.run(folder, ['rev-parse', '--show-toplevel']);
    final root = r.ok ? r.stdout.trim() : null;
    _roots[folder] = root;
    return root;
  }

  Future<GitRepo?> repoFor(String folder) async {
    final root = await rootFor(folder);
    if (root == null) return null;
    return _repos.putIfAbsent(root, () => GitRepo(root, runner));
  }

  /// Drops cached lookups for [folder] (it was just initialised or cloned).
  void forget(String folder) => _roots.remove(folder);

  /// Repositories currently known (for refresh triggers).
  Iterable<GitRepo> get repos => _repos.values;

  /// The global commit identity (name, email), or null if unset.
  Future<(String, String)?> identity() async {
    final name = await runner.run('/', ['config', '--global', 'user.name']);
    final email = await runner.run('/', ['config', '--global', 'user.email']);
    if (!name.ok || !email.ok || name.stdout.trim().isEmpty || email.stdout.trim().isEmpty) return null;
    return (name.stdout.trim(), email.stdout.trim());
  }

  Future<void> setIdentity(String name, String email) async {
    for (final (key, value) in [('user.name', name), ('user.email', email)]) {
      final r = await runner.run('/', ['config', '--global', key, value]);
      if (!r.ok) throw mapGitError(r);
    }
  }

  /// Refreshes repos containing [folder] (a command finished there, or
  /// Files changed something).
  void touched(String folder) {
    for (final repo in _repos.values) {
      if (folder == repo.path || folder.startsWith('${repo.path}/')) repo.refreshSoon();
    }
  }
}
