import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Describes the command used to start a terminal session.
///
/// Today this launches Android's own built-in shell (no root, no distro) —
/// that's the backend wired up in [ShellSession]/ShellPlugin.kt. It runs in
/// a real child process with real stdin/stdout, just not a Linux userland.
///
/// The planned replacement launches `proot` against a bootstrapped Alpine
/// rootfs instead (see README.md "Roadmap"), at which point only the argv
/// built here changes — the PtySession/EventChannel contract stays the same.
class ShellEnv {
  static Future<List<String>> argv() async {
    // /system/bin/sh exists on every Android device; it's Android's
    // toolbox/busybox-derived shell, not a full Linux distro.
    return const ['/system/bin/sh', '-i'];
  }

  static Future<Map<String, String>> env() async {
    final home = await _homeDir();
    return {
      'HOME': home,
      'TERM': 'xterm-256color',
      'PATH': '/system/bin:/system/xbin',
    };
  }

  static Future<String> _homeDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final home = Directory('${dir.path}/home');
    if (!await home.exists()) {
      await home.create(recursive: true);
    }
    return home.path;
  }

  static Future<String> cwd() => _homeDir();
}
