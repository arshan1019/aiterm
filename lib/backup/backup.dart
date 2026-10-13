/// Backup and restore of the whole Linux setup (installed tools, home
/// folder, config) plus the app's settings and tabs, as one .tar.gz the
/// user saves anywhere, Google Drive included.
///
/// Archive layout (paths relative to the app's files directory):
///   alpine/               the rootfs
///   aiterm-backup/        manifest.json, settings.json, terminal_tabs.json
library;

import 'dart:convert';
import 'dart:io';

const backupMetaDir = 'aiterm-backup';
const _format = 1;
const _appFiles = ['settings.json', 'terminal_tabs.json'];

/// Arguments for Android's tar, run in the files directory, writing the
/// archive to stdout. Caches and temp files are left out.
List<String> backupTarArgs() => [
      '-czf', '-',
      '--exclude=alpine/tmp/*',
      '--exclude=alpine/var/cache/apk/*',
      '--exclude=alpine/root/.cache/*',
      '--exclude=alpine/root/.npm/_cacache/*',
      'alpine',
      backupMetaDir,
    ];

String backupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'aiterm-backup-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}.tar.gz';
}

/// Writes the manifest and copies app state next to the rootfs, ready for
/// [backupTarArgs].
Future<void> stageBackup(String filesDir, {required String appVersion, DateTime? now}) async {
  final meta = Directory('$filesDir/$backupMetaDir');
  if (await meta.exists()) await meta.delete(recursive: true);
  await meta.create(recursive: true);
  String? alpine;
  try {
    alpine = (await File('$filesDir/alpine/etc/alpine-release').readAsString()).trim();
  } catch (_) {}
  await File('${meta.path}/manifest.json').writeAsString(jsonEncode({
    'format': _format,
    'app': appVersion,
    'alpine': alpine,
    'created': (now ?? DateTime.now()).toUtc().toIso8601String(),
  }));
  for (final name in _appFiles) {
    final f = File('$filesDir/$name');
    if (await f.exists()) await f.copy('${meta.path}/$name');
  }
}

/// Null if [staging] (an unpacked archive) can be restored, else why not.
String? validateRestore(String staging) {
  final manifest = File('$staging/$backupMetaDir/manifest.json');
  if (!manifest.existsSync() || !File('$staging/alpine/bin/busybox').existsSync()) {
    return 'This file is not an aiterm backup.';
  }
  try {
    final format = (jsonDecode(manifest.readAsStringSync()) as Map)['format'] as int? ?? 0;
    if (format > _format) return 'This backup is from a newer version of aiterm. Update the app first.';
  } catch (_) {
    return 'The backup manifest is damaged.';
  }
  return null;
}

/// Swaps the restored Linux and app state into place. The current rootfs is
/// kept aside until the new one is in, and put back if that fails.
Future<void> applyRestore(String filesDir, String staging) async {
  final current = Directory('$filesDir/alpine');
  final aside = Directory('$filesDir/alpine.old');
  if (await aside.exists()) await aside.delete(recursive: true);
  if (await current.exists()) await current.rename(aside.path);
  try {
    await Directory('$staging/alpine').rename(current.path);
  } catch (_) {
    if (await aside.exists()) await aside.rename(current.path);
    rethrow;
  }
  for (final name in _appFiles) {
    final f = File('$staging/$backupMetaDir/$name');
    if (await f.exists()) await f.copy('$filesDir/$name');
  }
  if (await aside.exists()) await aside.delete(recursive: true);
  await Directory(staging).delete(recursive: true);
}
