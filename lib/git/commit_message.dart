import 'git_parsers.dart';

/// A commit message describing [changes] ("Add notes.txt, update
/// README.md"), for people who'd rather not type one on a phone. Only
/// staged changes are described when there are any, since only they get
/// committed.
String suggestCommitMessage(List<GitChange> changes) {
  final staged = [for (final c in changes) if (c.staged != null) c];
  final described = staged.isNotEmpty ? staged : changes;
  final groups = <String, List<String>>{'Add': [], 'Update': [], 'Delete': [], 'Rename': []};
  for (final c in described) {
    final kind = staged.isNotEmpty ? c.staged : (c.unstaged ?? c.staged);
    final verb = switch (kind) {
      GitChangeKind.added || GitChangeKind.untracked || GitChangeKind.copied => 'Add',
      GitChangeKind.deleted => 'Delete',
      GitChangeKind.renamed => 'Rename',
      _ => 'Update',
    };
    groups[verb]!.add(c.path);
  }
  final parts = [
    for (final MapEntry(key: verb, value: paths) in groups.entries)
      if (paths.isNotEmpty) '$verb ${_names(paths)}',
  ];
  if (parts.isEmpty) return '';
  return [parts.first, for (final p in parts.skip(1)) p[0].toLowerCase() + p.substring(1)].join(', ');
}

String _names(List<String> paths) {
  String name(String p) => p.split('/').last;
  if (paths.length == 1) return name(paths.single);
  if (paths.length == 2) return '${name(paths[0])} and ${name(paths[1])}';
  final dirs = {for (final p in paths) p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : ''};
  return dirs.length == 1 && dirs.single.isNotEmpty ? '${paths.length} files in ${dirs.single}' : '${paths.length} files';
}
