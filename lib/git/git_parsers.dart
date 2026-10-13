/// Parsers for git's machine-readable output (porcelain v2, numstat,
/// unified diff, for-each-ref). Pure, so they're unit tested.
library;

enum GitChangeKind { modified, added, deleted, renamed, copied, typeChanged, untracked, conflicted }

class GitChange {
  const GitChange({required this.path, this.origPath, this.staged, this.unstaged});

  final String path;

  /// The old path of a rename or copy.
  final String? origPath;

  /// What's staged for this path (null: nothing staged).
  final GitChangeKind? staged;

  /// What's changed in the working tree but not staged (null: nothing).
  final GitChangeKind? unstaged;

  bool get conflicted => staged == GitChangeKind.conflicted || unstaged == GitChangeKind.conflicted;
}

class GitCommitInfo {
  const GitCommitInfo(this.hash, this.subject, this.author, this.time);
  final String hash;
  final String subject;
  final String author;
  final DateTime time;
}

class GitStatus {
  const GitStatus({
    required this.branch,
    required this.hasCommits,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.changes = const [],
    this.lastCommit,
  });

  /// Current branch, or null when HEAD is detached.
  final String? branch;
  final bool hasCommits;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<GitChange> changes;
  final GitCommitInfo? lastCommit;

  bool get isClean => changes.isEmpty;
  List<GitChange> get staged => [for (final c in changes) if (c.staged != null) c];
  List<GitChange> get unstaged => [for (final c in changes) if (c.unstaged != null) c];

  GitStatus withLastCommit(GitCommitInfo? c) => GitStatus(
        branch: branch,
        hasCommits: hasCommits,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
        changes: changes,
        lastCommit: c,
      );
}

GitChangeKind? _kind(String c) => switch (c) {
      'M' => GitChangeKind.modified,
      'A' => GitChangeKind.added,
      'D' => GitChangeKind.deleted,
      'R' => GitChangeKind.renamed,
      'C' => GitChangeKind.copied,
      'T' => GitChangeKind.typeChanged,
      _ => null, // '.' unchanged
    };

/// `git status --porcelain=v2 -z --branch`.
GitStatus parseStatus(String out) {
  String? branch;
  String? upstream;
  var hasCommits = true;
  var ahead = 0, behind = 0;
  final changes = <GitChange>[];
  final records = out.split('\x00');
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    if (r.isEmpty) continue;
    if (r.startsWith('# branch.oid ')) {
      hasCommits = r.substring(13) != '(initial)';
    } else if (r.startsWith('# branch.head ')) {
      final h = r.substring(14);
      branch = h == '(detached)' ? null : h;
    } else if (r.startsWith('# branch.upstream ')) {
      upstream = r.substring(18);
    } else if (r.startsWith('# branch.ab ')) {
      final m = RegExp(r'\+(\d+) -(\d+)').firstMatch(r);
      if (m != null) {
        ahead = int.parse(m.group(1)!);
        behind = int.parse(m.group(2)!);
      }
    } else if (r.startsWith('1 ')) {
      final f = r.split(' ');
      changes.add(GitChange(path: f.sublist(8).join(' '), staged: _kind(f[1][0]), unstaged: _kind(f[1][1])));
    } else if (r.startsWith('2 ')) {
      final f = r.split(' ');
      final orig = i + 1 < records.length ? records[++i] : null;
      changes.add(GitChange(
        path: f.sublist(9).join(' '),
        origPath: orig,
        staged: _kind(f[1][0]),
        unstaged: _kind(f[1][1]),
      ));
    } else if (r.startsWith('u ')) {
      final f = r.split(' ');
      changes.add(GitChange(
        path: f.sublist(10).join(' '),
        staged: GitChangeKind.conflicted,
        unstaged: GitChangeKind.conflicted,
      ));
    } else if (r.startsWith('? ')) {
      changes.add(GitChange(path: r.substring(2), unstaged: GitChangeKind.untracked));
    }
  }
  changes.sort((a, b) => a.path.compareTo(b.path));
  return GitStatus(
    branch: branch,
    hasCommits: hasCommits,
    upstream: upstream,
    ahead: ahead,
    behind: behind,
    changes: changes,
  );
}

enum DiffLineKind { context, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldLine, this.newLine});
  final DiffLineKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

class DiffHunk {
  DiffHunk(this.header);
  final String header;
  final lines = <DiffLine>[];
}

class FileDiff {
  FileDiff(this.path);
  String path;
  bool binary = false;
  final hunks = <DiffHunk>[];

  int get added => hunks.fold(0, (n, h) => n + h.lines.where((l) => l.kind == DiffLineKind.added).length);
  int get removed => hunks.fold(0, (n, h) => n + h.lines.where((l) => l.kind == DiffLineKind.removed).length);
}

/// Unified diff (`git diff`) into files, hunks and numbered lines.
List<FileDiff> parseDiff(String out) {
  final files = <FileDiff>[];
  FileDiff? file;
  DiffHunk? hunk;
  var oldNo = 0, newNo = 0;
  final hunkHeader = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  for (final line in out.split('\n')) {
    if (line.startsWith('diff --git ')) {
      final m = RegExp(r'^diff --git a/(.*) b/(.*)$').firstMatch(line);
      file = FileDiff(m?.group(2) ?? line.substring(11));
      files.add(file);
      hunk = null;
    } else if (file == null) {
      continue;
    } else if (line.startsWith('+++ ') && hunk == null) {
      final p = line.substring(4);
      if (p.startsWith('b/')) file.path = p.substring(2);
    } else if (line.startsWith('Binary files ')) {
      file.binary = true;
    } else if (hunkHeader.firstMatch(line) case final m?) {
      hunk = DiffHunk(line);
      file.hunks.add(hunk);
      oldNo = int.parse(m.group(1)!);
      newNo = int.parse(m.group(2)!);
    } else if (hunk != null && line.isNotEmpty) {
      switch (line[0]) {
        case '+':
          hunk.lines.add(DiffLine(DiffLineKind.added, line.substring(1), newLine: newNo++));
        case '-':
          hunk.lines.add(DiffLine(DiffLineKind.removed, line.substring(1), oldLine: oldNo++));
        case ' ':
          hunk.lines.add(DiffLine(DiffLineKind.context, line.substring(1), oldLine: oldNo++, newLine: newNo++));
        default: // "\ No newline at end of file"
      }
    }
  }
  return files;
}

class GitBranch {
  const GitBranch(this.name, {this.remote = false, this.current = false, this.upstream});
  final String name;
  final bool remote;
  final bool current;
  final String? upstream;
}

/// Format string for [parseBranches].
const branchFormat = '%(refname)%00%(HEAD)%00%(upstream:short)';

List<GitBranch> parseBranches(String out) => [
      for (final line in out.split('\n'))
        if (line.split('\x00') case [final ref, final head, final up] when !ref.endsWith('/HEAD'))
          if (ref.startsWith('refs/heads/'))
            GitBranch(ref.substring(11), current: head == '*', upstream: up.isEmpty ? null : up)
          else if (ref.startsWith('refs/remotes/'))
            GitBranch(ref.substring(13), remote: true),
    ];

/// host, owner, repo of a remote URL (https, ssh:// or scp-like); null for
/// local paths.
(String, String, String)? parseRemote(String url) {
  final m = RegExp(r'^(?:https?://|ssh://)(?:[^@/]+@)?([^/:]+)(?::\d+)?/([^/]+)/([^/]+?)(?:\.git)?/?$').firstMatch(url) ??
      RegExp(r'^[^@/]+@([^:/]+):([^/]+)/([^/]+?)(?:\.git)?/?$').firstMatch(url);
  return m == null ? null : (m.group(1)!, m.group(2)!, m.group(3)!);
}
