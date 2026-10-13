import 'dart:io';
import 'distro_manager.dart';

/// Android's built-in shell: no package manager, but always available.
/// Used when Alpine isn't installed yet or the user wants to skip it.
class ShellEnv {
  static Future<String> androidHome() async {
    final d = DistroManager.instance;
    await d.init();
    final home = Directory('${d.filesDir}/home');
    await home.create(recursive: true);
    return home.path;
  }

  static Future<SessionSpec> androidShell() async {
    final home = await androidHome();
    return SessionSpec(
      const ['/system/bin/sh', '-l'],
      {
        'HOME': home,
        'TERM': 'xterm-256color',
        'PATH': '/system/bin:/system/xbin',
      },
      home,
    );
  }
}
