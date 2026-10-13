import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'distro_manager.dart';

/// Android's built-in shell: no package manager, but always available.
/// Used when Alpine isn't installed yet or the user wants to skip it.
class ShellEnv {
  static Future<SessionSpec> androidShell() async {
    final docs = await getApplicationDocumentsDirectory();
    final home = Directory('${docs.path}/home');
    await home.create(recursive: true);
    return SessionSpec(
      const ['/system/bin/sh', '-l'],
      {
        'HOME': home.path,
        'TERM': 'xterm-256color',
        'PATH': '/system/bin:/system/xbin',
      },
      home.path,
    );
  }
}
