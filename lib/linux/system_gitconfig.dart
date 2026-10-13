/// /etc/gitconfig defaults for git under proot.
///
/// proot emulates hard links as symlinks (`--link2symlink`), and git stores
/// new objects by hard-linking them into place by default; it then can't
/// find them ("unpack should have generated … bad pack", seen pushing to a
/// local repo). `core.createObject = rename` is git's own setting for
/// filesystems where hard links misbehave. Existing settings are kept.
String withProotGitDefaults(String existing) {
  if (RegExp(r'^\s*createObject\s*=', multiLine: true).hasMatch(existing)) return existing;
  const line = '\tcreateObject = rename\n';
  final core = RegExp(r'^\[core\]\s*\n', multiLine: true).firstMatch(existing);
  if (core != null) return existing.replaceRange(core.end, core.end, line);
  final sep = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
  return '$existing$sep[core]\n$line';
}
