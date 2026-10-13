import 'dart:io';

var _seq = 0;

String _tempName(String path) => '$path.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

/// Makes [path] a symlink to [target], safely when several sessions start
/// at once: the new link is made under a unique name and renamed into
/// place, which replaces atomically. (Delete-then-create raced: two tabs
/// both saw no link and the second create failed with PathExistsException.)
Future<void> ensureLink(String path, String target) async {
  try {
    if (await Link(path).target() == target) return;
  } on FileSystemException {
    // Missing, or not a link: replace it below.
  }
  final temp = Link(_tempName(path));
  await temp.create(target);
  try {
    await temp.rename(path);
  } catch (_) {
    await temp.delete().catchError((_) => temp);
    rethrow;
  }
}

/// Writes [contents] to [path] via a unique temp file and a rename, so a
/// reader (or a concurrent writer) never sees a partial or mixed file.
Future<void> writeFileAtomic(String path, String contents) async {
  final temp = File(_tempName(path));
  await temp.writeAsString(contents, flush: true);
  await temp.rename(path);
}
