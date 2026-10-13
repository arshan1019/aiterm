import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/backup/backup.dart';

void main() {
  late Directory files;
  setUp(() => files = Directory.systemTemp.createTempSync('aiterm_backup'));
  tearDown(() => files.deleteSync(recursive: true));

  void makeRootfs(String dir, {String marker = 'v1'}) {
    Directory('$dir/bin').createSync(recursive: true);
    File('$dir/bin/busybox').writeAsStringSync(marker);
    File('$dir/etc/alpine-release').createSync(recursive: true);
    File('$dir/etc/alpine-release').writeAsStringSync('3.24.2\n');
  }

  group('backup', () {
    test('tar arguments archive Linux and the app state, minus caches', () {
      final args = backupTarArgs();
      expect(args.take(2), ['-czf', '-']);
      expect(args, containsAll(['alpine', backupMetaDir]));
      expect(args, contains('--exclude=alpine/tmp/*'));
      expect(args, contains('--exclude=alpine/var/cache/apk/*'));
      expect(args, contains('--exclude=alpine/root/.cache/*'));
    });

    test('staging writes a manifest and copies settings and tabs', () async {
      makeRootfs('${files.path}/alpine');
      File('${files.path}/settings.json').writeAsStringSync('{"dark":false}');
      File('${files.path}/terminal_tabs.json').writeAsStringSync('{"version":2}');
      await stageBackup(files.path, appVersion: '1.0.0', now: DateTime.utc(2026, 10, 13));
      final meta = Directory('${files.path}/$backupMetaDir');
      final manifest = jsonDecode(File('${meta.path}/manifest.json').readAsStringSync());
      expect(manifest['format'], 1);
      expect(manifest['alpine'], '3.24.2');
      expect(manifest['created'], '2026-10-13T00:00:00.000Z');
      expect(File('${meta.path}/settings.json').readAsStringSync(), '{"dark":false}');
      expect(File('${meta.path}/terminal_tabs.json').existsSync(), isTrue);
    });

    test('file name carries the date', () {
      expect(backupFileName(DateTime(2026, 10, 13, 9, 5)), 'aiterm-backup-2026-10-13-0905.tar.gz');
    });
  });

  group('restore', () {
    test('a valid staging folder passes', () {
      final staging = '${files.path}/restore';
      makeRootfs('$staging/alpine');
      Directory('$staging/$backupMetaDir').createSync(recursive: true);
      File('$staging/$backupMetaDir/manifest.json').writeAsStringSync(jsonEncode({'format': 1, 'alpine': '3.24.2'}));
      expect(validateRestore(staging), isNull);
    });

    test('a file that is not an aiterm backup is rejected', () {
      final staging = '${files.path}/restore';
      Directory(staging).createSync();
      expect(validateRestore(staging), contains('not an aiterm backup'));
    });

    test('a backup from a newer app is rejected', () {
      final staging = '${files.path}/restore';
      makeRootfs('$staging/alpine');
      Directory('$staging/$backupMetaDir').createSync(recursive: true);
      File('$staging/$backupMetaDir/manifest.json').writeAsStringSync(jsonEncode({'format': 99}));
      expect(validateRestore(staging), contains('newer'));
    });

    test('swap replaces Linux and app state, removing the old copy', () async {
      makeRootfs('${files.path}/alpine', marker: 'old');
      File('${files.path}/settings.json').writeAsStringSync('old settings');
      final staging = '${files.path}/restore';
      makeRootfs('$staging/alpine', marker: 'new');
      Directory('$staging/$backupMetaDir').createSync(recursive: true);
      File('$staging/$backupMetaDir/manifest.json').writeAsStringSync(jsonEncode({'format': 1}));
      File('$staging/$backupMetaDir/settings.json').writeAsStringSync('new settings');

      await applyRestore(files.path, staging);
      expect(File('${files.path}/alpine/bin/busybox').readAsStringSync(), 'new');
      expect(File('${files.path}/settings.json').readAsStringSync(), 'new settings');
      expect(Directory('${files.path}/alpine.old').existsSync(), isFalse);
      expect(Directory(staging).existsSync(), isFalse);
    });

    test('if moving the new copy in fails, the old Linux is put back', () async {
      makeRootfs('${files.path}/alpine', marker: 'old');
      final staging = '${files.path}/restore'; // no alpine inside: the move fails
      Directory('$staging/$backupMetaDir').createSync(recursive: true);
      await expectLater(applyRestore(files.path, staging), throwsA(isA<FileSystemException>()));
      expect(File('${files.path}/alpine/bin/busybox').readAsStringSync(), 'old');
    });
  });
}
