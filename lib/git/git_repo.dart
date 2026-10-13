import 'dart:async';
import 'package:flutter/foundation.dart';
import 'git_parsers.dart';
import 'git_runner.dart';

enum GitErrorKind {
  /// No user.name / user.email: ask once, then retry.
  identity,

  /// The host refused the credentials: sign in to GitHub / add an SSH key.
  auth,

  /// The remote has commits we don't: pull first.
  pullFirst,

  /// Local and remote both moved on; fast-forward isn't possible.
  diverged,

  /// Not inside a repository.
  notRepo,

  /// No remote to sync with.
  noRemote,
  other,
}

class GitError implements Exception {
  const GitError(this.kind, this.message, {this.detail = ''});
  final GitErrorKind kind;

  /// Plain-language explanation for the user.
  final String message;

  /// git's own output, for "Show details".
  final String detail;

  @override
  String toString() => message;
}

/// Turns git's stderr into a [GitError] the UI can act on.
GitError mapGitError(GitResult r) {
  final e = '${r.stderr}\n${r.stdout}';
  final l = e.toLowerCase();
  if (l.contains('please tell me who you are') || l.contains('empty ident') || l.contains('unable to auto-detect email')) {
    return GitError(GitErrorKind.identity, 'Set your name and email for commits.', detail: e);
  }
  if (l.contains('authentication failed') ||
      l.contains('could not read username') ||
      l.contains('permission denied (publickey)') ||
      l.contains('terminal prompts disabled') ||
      l.contains('invalid username or password')) {
    return GitError(GitErrorKind.auth, 'Sign in to GitHub (or add your SSH key) to sync.', detail: e);
  }
  if (l.contains('[rejected]') || l.contains('fetch first') || l.contains('non-fast-forward')) {
    return GitError(GitErrorKind.pullFirst, 'The remote has new commits. Pull first, then push.', detail: e);
  }
  if (l.contains('not possible to fast-forward') || l.contains('diverging branches') || l.contains('have diverged')) {
    return GitError(GitErrorKind.diverged, 'Your branch and the remote have both changed.', detail: e);
  }
  if (l.contains('not a git repository')) {
    return GitError(GitErrorKind.notRepo, 'This folder is not a git repository.', detail: e);
  }
  if (l.contains("does not appear to be a git repository") || l.contains('no configured push destination') || l.contains('no remote')) {
    return GitError(GitErrorKind.noRemote, 'This repository has no remote to sync with.', detail: e);
  }
  final last = e.trim().split('\n').lastWhere((x) => x.trim().isNotEmpty, orElse: () => 'git failed');
  return GitError(GitErrorKind.other, last.replaceFirst(RegExp(r'^(fatal|error): '), ''), detail: e);
}

/// One repository: its status, and the operations the Git view offers.
/// Operations run one at a time; each refreshes the status afterwards.
class GitRepo extends ChangeNotifier {
  GitRepo(this.path, this._git);

  /// Repository root, as the runner sees it.
  final String path;
  final GitRunner _git;

  GitStatus? status;
  bool busy = false;

  Future<void> _queue = Future.value();
  Timer? _debounce;
  bool _refreshing = false, _refreshAgain = false;

  Future<GitResult> _run(List<String> args, {bool check = true}) async {
    final r = await _git.run(path, args);
    if (check && !r.ok) throw mapGitError(r);
    return r;
  }

  /// Runs [op] after anything already queued, with [busy] set, then
  /// refreshes the status.
  Future<T> _op<T>(Future<T> Function() op) {
    final next = _queue.then((_) async {
      busy = true;
      notifyListeners();
      try {
        return await op();
      } finally {
        busy = false;
        await _refreshNow();
      }
    });
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Re-reads the status soon (coalesced; never two at once).
  void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _refreshNow());
  }

  Future<void> refresh() => _refreshNow();

  Future<void> _refreshNow() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final r = await _run(['status', '--porcelain=v2', '-z', '--branch', '--untracked-files=all']);
        var s = parseStatus(r.stdout);
        if (s.hasCommits) {
          final log = await _run(['log', '-1', '--format=%H%x00%s%x00%an%x00%at'], check: false);
          final f = log.stdout.trim().split('\x00');
          if (log.ok && f.length == 4) {
            s = s.withLastCommit(GitCommitInfo(
                f[0], f[1], f[2], DateTime.fromMillisecondsSinceEpoch(int.parse(f[3]) * 1000)));
          }
        }
        status = s;
        notifyListeners();
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> stage(List<String> paths) => _op(() => _run(['add', '-A', '--', ...paths]));

  Future<void> unstage(List<String> paths) => _op(() async {
        if (status?.hasCommits ?? true) {
          await _run(['restore', '--staged', '--', ...paths]);
        } else {
          await _run(['rm', '--cached', '-r', '-q', '--', ...paths]); // nothing to restore to yet
        }
      });

  /// Throws away working-tree changes: tracked files go back to their
  /// committed/staged state, untracked files are deleted.
  Future<void> discard(List<GitChange> changes) => _op(() async {
        final untracked = [for (final c in changes) if (c.unstaged == GitChangeKind.untracked) c.path];
        final tracked = [for (final c in changes) if (c.unstaged != GitChangeKind.untracked) c.path];
        if (tracked.isNotEmpty) await _run(['restore', '--', ...tracked]);
        if (untracked.isNotEmpty) await _run(['clean', '-f', '-q', '--', ...untracked]);
      });

  Future<void> commit(String message) => _op(() => _run(['commit', '-q', '-m', message]));

  Future<void> fetch() => _op(() => _run(['fetch', '-q', '--prune']));

  Future<void> pull() => _op(() => _run(['pull', '-q', '--ff-only']));

  /// Pushes; a branch with no upstream is published to origin first.
  Future<void> push() => _op(() async {
        final s = status ?? (await _refreshNow().then((_) => status));
        if (s?.upstream == null) {
          await _run(['push', '-q', '-u', 'origin', 'HEAD']);
        } else {
          await _run(['push', '-q']);
        }
      });

  Future<void> switchBranch(String name) => _op(() => _run(['switch', '-q', name]));

  Future<void> createBranch(String name) => _op(() => _run(['switch', '-q', '-c', name]));

  Future<List<GitBranch>> branches() async =>
      parseBranches((await _run(['for-each-ref', '--format=$branchFormat', 'refs/heads', 'refs/remotes'])).stdout);

  /// The diff of one file: staged ([staged]) or working tree; an untracked
  /// file shows as entirely added.
  Future<FileDiff> diff(String file, {bool staged = false}) async {
    final s = status ?? (await _refreshNow().then((_) => status));
    final untracked = s?.changes.any((c) => c.path == file && c.unstaged == GitChangeKind.untracked) ?? false;
    final r = untracked
        ? await _run(['diff', '--no-color', '--no-index', '--', '/dev/null', file], check: false)
        : await _run(['diff', '--no-color', if (staged) '--cached', '--', file]);
    final files = parseDiff(r.stdout);
    return files.isEmpty ? FileDiff(file) : (files.first..path = file);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
