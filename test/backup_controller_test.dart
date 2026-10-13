import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/backup/backup.dart';
import 'package:aiterm/backup/backup_controller.dart';

class FakeBackupPlatform implements BackupPlatform {
  List<String>? tarArgs;
  int? written = 1234;
  bool manifestStaged = false;
  void Function(String staging)? unpack; // simulates tar -x into staging
  bool restarted = false;
  bool stopped = false;

  @override
  Future<int?> saveArchive({required String fileName, required String filesDir, required List<String> tarArgs}) async {
    this.tarArgs = tarArgs;
    manifestStaged = File('$filesDir/$backupMetaDir/manifest.json').existsSync();
    return written;
  }

  @override
  Future<bool> openArchive({required String staging}) async {
    if (unpack == null) return false; // cancelled
    unpack!(staging);
    return true;
  }

  @override
  Future<void> stopAllSessions() async => stopped = true;
  @override
  Future<void> restartApp() async => restarted = true;
}

void main() {
  late Directory files;
  late FakeBackupPlatform platform;
  late BackupController c;

  setUp(() {
    files = Directory.systemTemp.createTempSync('aiterm_bc');
    Directory('${files.path}/alpine/bin').createSync(recursive: true);
    File('${files.path}/alpine/bin/busybox').writeAsStringSync('old');
    platform = FakeBackupPlatform();
    c = BackupController(platform, filesDir: files.path, appVersion: '1.0.0');
  });
  tearDown(() => files.deleteSync(recursive: true));

  test('backup stages metadata and streams the archive', () async {
    await c.backup();
    expect(platform.tarArgs, backupTarArgs());
    expect(platform.manifestStaged, isTrue); // present while archiving…
    expect(Directory('${files.path}/$backupMetaDir').existsSync(), isFalse); // …cleaned up after
    expect(c.message, contains('1.2 KB'));
    expect(c.busy, isFalse);
  });

  test('a cancelled save says nothing went wrong', () async {
    platform.written = null;
    await c.backup();
    expect(c.message, isNull);
  });

  test('restoring a valid backup stops shells, swaps, and restarts', () async {
    platform.unpack = (staging) {
      Directory('$staging/alpine/bin').createSync(recursive: true);
      File('$staging/alpine/bin/busybox').writeAsStringSync('new');
      Directory('$staging/$backupMetaDir').createSync(recursive: true);
      File('$staging/$backupMetaDir/manifest.json').writeAsStringSync(jsonEncode({'format': 1}));
    };
    await c.restore();
    expect(platform.stopped, isTrue);
    expect(File('${files.path}/alpine/bin/busybox').readAsStringSync(), 'new');
    expect(platform.restarted, isTrue);
  });

  test('an invalid file leaves everything as it was', () async {
    platform.unpack = (staging) => File('$staging/random.txt').writeAsStringSync('x');
    await c.restore();
    expect(File('${files.path}/alpine/bin/busybox').readAsStringSync(), 'old');
    expect(platform.restarted, isFalse);
    expect(c.message, contains('not an aiterm backup'));
    expect(Directory('${files.path}/restore-staging').existsSync(), isFalse);
  });
}
