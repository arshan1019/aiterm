import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'backup.dart';

/// Android's side of backups (android/.../BackupPlugin.kt): the system file
/// picker and streaming tar to or from the chosen file.
abstract interface class BackupPlatform {
  /// Asks where to save, then streams `tar [tarArgs]` (run in [filesDir])
  /// into it. Bytes written, or null if the user cancelled.
  Future<int?> saveArchive({required String fileName, required String filesDir, required List<String> tarArgs});

  /// Asks for a backup file and unpacks it into [staging]; false if cancelled.
  Future<bool> openArchive({required String staging});

  Future<void> stopAllSessions();
  Future<void> restartApp();
}

class BackupController extends ChangeNotifier {
  BackupController(this._platform, {required this.filesDir, required this.appVersion});

  final BackupPlatform _platform;
  final String filesDir;
  final String appVersion;

  bool busy = false;
  String? message;

  String get _staging => '$filesDir/restore-staging';

  void _set({bool? busy, String? message, bool clear = false}) {
    if (busy != null) this.busy = busy;
    if (clear) this.message = null;
    if (message != null) this.message = message;
    notifyListeners();
  }

  Future<void> backup() async {
    _set(busy: true, message: 'Preparing backup…');
    try {
      await stageBackup(filesDir, appVersion: appVersion);
      _set(message: 'Saving… (large installs take a minute)');
      final bytes = await _platform.saveArchive(
        fileName: backupFileName(DateTime.now()),
        filesDir: filesDir,
        tarArgs: backupTarArgs(),
      );
      if (bytes == null) {
        _set(clear: true);
      } else {
        _set(message: 'Backup saved (${_size(bytes)}).');
      }
    } catch (e) {
      _set(message: 'Backup failed: ${e is PlatformException ? e.message : e}');
    } finally {
      final meta = Directory('$filesDir/$backupMetaDir');
      if (await meta.exists()) await meta.delete(recursive: true);
      _set(busy: false);
    }
  }

  /// Replaces Linux and the app's settings and tabs with a backup, then
  /// restarts the app so everything loads fresh.
  Future<void> restore() async {
    _set(busy: true, message: 'Choose a backup file…');
    final staging = Directory(_staging);
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      if (!await _platform.openArchive(staging: staging.path)) {
        _set(clear: true);
        return;
      }
      final problem = validateRestore(staging.path);
      if (problem != null) {
        _set(message: problem);
        return;
      }
      _set(message: 'Restoring…');
      await _platform.stopAllSessions(); // nothing may be running in the old rootfs
      await applyRestore(filesDir, staging.path);
      await _platform.restartApp();
    } catch (e) {
      _set(message: 'Restore failed: ${e is PlatformException ? e.message : e}');
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      _set(busy: false);
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class BackupChannel implements BackupPlatform {
  static const _channel = MethodChannel('aiterm/backup');

  @override
  Future<int?> saveArchive({required String fileName, required String filesDir, required List<String> tarArgs}) =>
      _channel.invokeMethod<int>('save', {'fileName': fileName, 'dir': filesDir, 'args': tarArgs});

  @override
  Future<bool> openArchive({required String staging}) async =>
      await _channel.invokeMethod<bool>('open', {'staging': staging}) ?? false;

  @override
  Future<void> stopAllSessions() => _channel.invokeMethod('stopAll');

  @override
  Future<void> restartApp() => _channel.invokeMethod('restart');
}
