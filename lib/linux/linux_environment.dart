import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../platform/android_env.dart';
import '../shared/download.dart';
import 'proc_stubs.dart';
import 'session_spec.dart';
import 'shell_profile.dart';

enum LinuxStatus { missing, installing, ready }

/// Alpine Linux in the app's private storage, run under proot.
///
/// proot and its libraries come from Termux's repo (scripts/fetch_deps.sh)
/// and ship as jniLibs, since Android only lets an app exec files from its
/// native library directory. The session is set up the way Termux's
/// proot-distro does it, so programs see an ordinary Linux system.
class LinuxEnvironment extends ChangeNotifier {
  LinuxEnvironment(this.paths);

  final AppPaths paths;

  static const _releases = 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64';

  LinuxStatus _status = LinuxStatus.missing;
  LinuxStatus get status => _status;
  bool get installed => _status == LinuxStatus.ready;

  /// The user chose Android's own shell instead of installing Alpine.
  bool _androidShell = false;
  bool get usesAndroidShell => _androidShell;

  String get rootfs => '${paths.filesDir}/alpine';

  /// Home folder of whichever shell is in use, as a host path.
  String get home => _androidShell || !installed ? androidHome : '$rootfs/root';
  String get androidHome => '${paths.filesDir}/home';

  File get _marker => File('$rootfs/.aiterm-installed');

  Future<void> load() async {
    if (await _marker.exists()) _status = LinuxStatus.ready;
    await Directory(androidHome).create(recursive: true);
  }

  void useAndroidShell() {
    _androidShell = true;
    notifyListeners();
  }

  /// Downloads, verifies and unpacks the latest Alpine minirootfs.
  Future<void> install(void Function(String status, double? progress) onProgress) async {
    _status = LinuxStatus.installing;
    notifyListeners();
    try {
      onProgress('Finding the latest Alpine release', null);
      final index = await http.read(Uri.parse('$_releases/latest-releases.yaml'));
      final entry = index
          .split(RegExp(r'^-\s*$', multiLine: true))
          .firstWhere((e) => e.contains('flavor: alpine-minirootfs'),
              orElse: () => throw StateError('No minirootfs in the Alpine release index'));
      String field(String name) => RegExp('^\\s*$name: (\\S+)', multiLine: true).firstMatch(entry)!.group(1)!;
      final fileName = field('file');

      final tarball = File('${paths.cacheDir}/$fileName');
      await downloadVerified(
        Uri.parse('$_releases/$fileName'),
        tarball,
        sha256Hex: field('sha256'),
        onProgress: (p) => onProgress(p == null ? 'Verifying' : 'Downloading Alpine', p),
      );

      onProgress('Unpacking', null);
      final dir = Directory(rootfs);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      // Android's toybox tar keeps symlinks and exec bits, which busybox's
      // applet links depend on.
      final tar = await Process.run('/system/bin/tar', ['-xzf', tarball.path, '-C', rootfs]);
      await tarball.delete();
      if (!await File('$rootfs/bin/busybox').exists()) throw StateError('Unpacking failed: ${tar.stderr}');

      // The guest can't see Android's resolver config.
      await File('$rootfs/etc/resolv.conf').writeAsString('nameserver 1.1.1.1\nnameserver 8.8.8.8\n');
      await File('$rootfs/etc/hosts').writeAsString('127.0.0.1 localhost\n::1 localhost\n');
      await File('$rootfs/etc/hostname').writeAsString('localhost\n');
      await _marker.writeAsString(fileName);
      _status = LinuxStatus.ready;
    } catch (_) {
      _status = LinuxStatus.missing;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// What a terminal tab should run, starting in [cwd] (as the shell sees
  /// it) when that folder still exists.
  Future<SessionSpec> sessionSpec([String? cwd]) =>
      _androidShell || !installed ? Future.value(_androidSpec(cwd)) : _prootSpec(cwd);

  SessionSpec _androidSpec(String? cwd) => SessionSpec(
        const ['/system/bin/sh', '-l'],
        {'HOME': androidHome, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'PATH': '/system/bin:/system/xbin'},
        cwd != null && Directory(cwd).existsSync() ? cwd : androidHome,
      );

  Future<SessionSpec> _prootSpec(String? cwd, {List<String>? command}) async {
    final lib = paths.nativeLibDir;
    // proot links against libtalloc.so.2, but jniLibs must be named lib*.so.
    // nativeLibDir moves on every app update, so rebuild the link each time.
    final libDir = Directory('${paths.filesDir}/lib');
    await libDir.create(recursive: true);
    final talloc = Link('${libDir.path}/libtalloc.so.2');
    if (await talloc.exists()) await talloc.delete();
    await talloc.create('$lib/libtalloc.so');
    final prootTmp = Directory('${paths.cacheDir}/proot-tmp');
    await prootTmp.create(recursive: true);

    // Sticky world-writable /tmp and /dev/shm, as on any Linux system.
    final shm = Directory('${paths.filesDir}/shm');
    await shm.create(recursive: true);
    await Directory('$rootfs/tmp').create(recursive: true);
    await Process.run('/system/bin/chmod', ['1777', shm.path, '$rootfs/tmp']);

    // Shell integration: folder and command boundaries (see shell_profile).
    await File('$rootfs/etc/profile.d/aiterm.sh').writeAsString(shellProfile);
    final start = cwd != null && cwd.startsWith('/') && Directory('$rootfs$cwd').existsSync() ? cwd : '/root';

    final shell = await _loginShell();
    final argv = <String>[
      '$lib/libproot.so',
      '--kill-on-exit',
      '--link2symlink',
      '--sysvipc',
      // Android kernels report versions some tools refuse to run on.
      '--kernel-release=\\Linux\\localhost\\$kernelRelease\\$kernelVersion\\aarch64\\localdomain\\-1\\',
      '-L',
      '--change-id=0:0',
      '--rootfs=$rootfs',
      '--cwd=$start',
      '--bind=/dev',
      '--bind=/proc',
      '--bind=/sys',
      '--bind=/dev/urandom:/dev/random',
      '--bind=${shm.path}:/dev/shm',
      if (!_exists('/dev/fd')) '--bind=/proc/self/fd:/dev/fd',
      for (final (i, name) in [(0, 'stdin'), (1, 'stdout'), (2, 'stderr')])
        if (!_exists('/dev/$name')) '--bind=/proc/self/fd/$i:/dev/$name',
      ...await procStubBinds(Directory('${paths.filesDir}/sysdata'), uptimeMs: paths.uptimeMs),
      // Android's own tree, for device tools like getprop.
      for (final p in const [
        '/apex', '/odm', '/product', '/system', '/system_ext', '/vendor',
        '/linkerconfig/ld.config.txt', '/linkerconfig/com.android.art/ld.config.txt',
        '/plat_property_contexts', '/property_contexts',
      ])
        if (_exists(p)) '--bind=$p',
      if (_listable('/storage/emulated/0')) ...[
        '--bind=/storage',
        '--bind=/storage/emulated/0:/sdcard',
        '--bind=/storage/emulated/0:/mnt/sdcard',
      ],
      '/usr/bin/env', '-i',
      // Deliberately no ANDROID_* variables: installers use them to detect
      // Android and pick Android builds, which a musl Linux can't run.
      'HOME=/root',
      'USER=root',
      'LOGNAME=root',
      'SHELL=$shell',
      'TERM=xterm-256color',
      'COLORTERM=truecolor',
      'LANG=C.UTF-8',
      'TMPDIR=/tmp',
      // The app's keystore-backed ssh-agent (lib/ssh).
      'SSH_AUTH_SOCK=/tmp/aiterm-agent.sock',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      ...(command ?? [shell, '-l']),
    ];
    return SessionSpec(
      argv,
      {
        'PROOT_LOADER': '$lib/libproot-loader.so',
        'PROOT_TMP_DIR': prootTmp.path,
        'LD_LIBRARY_PATH': '${libDir.path}:$lib',
      },
      paths.filesDir,
    );
  }

  /// Runs [script] with /bin/sh inside Linux, without a terminal; returns
  /// the combined output and exit status.
  Future<(String, int)> runScript(String script) async {
    if (!installed) return ('Linux is not installed', 1);
    final spec = await _prootSpec(null, command: ['/bin/sh', '-c', script]);
    final r = await Process.run(spec.argv.first, spec.argv.sublist(1),
        environment: spec.env, workingDirectory: spec.cwd);
    return ('${r.stdout}${r.stderr}', r.exitCode);
  }

  /// Like [runScript], streaming output lines as they come (installs).
  Future<int> runScriptStreaming(String script, void Function(String line) onOutput) async {
    if (!installed) {
      onOutput('Linux is not installed');
      return 1;
    }
    final spec = await _prootSpec(null, command: ['/bin/sh', '-c', script]);
    final p = await Process.start(spec.argv.first, spec.argv.sublist(1),
        environment: spec.env, workingDirectory: spec.cwd);
    void pipe(Stream<List<int>> s) => s
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(onOutput);
    pipe(p.stdout);
    pipe(p.stderr);
    return p.exitCode;
  }

  /// root's shell from /etc/passwd, so `chsh -s /bin/bash` sticks.
  Future<String> _loginShell() async {
    try {
      for (final line in await File('$rootfs/etc/passwd').readAsLines()) {
        final f = line.split(':');
        if (f.length >= 7 && f[0] == 'root' && f[6].isNotEmpty && _exists('$rootfs${f[6]}')) return f[6];
      }
    } catch (_) {}
    return '/bin/sh';
  }

  /// Maps a path as the shell sees it ("/etc", "~/src", "src") to a host
  /// path, or null if it can't be shown.
  String hostPath(String guestPath) {
    if (guestPath.isEmpty || guestPath == '~') return home;
    if (guestPath.startsWith('/') && installed && !_androidShell) return '$rootfs$guestPath';
    return '$home/${guestPath.replaceFirst(RegExp(r'^~/'), '')}';
  }

  /// The inverse of [hostPath]: where the shell sees host folder [host].
  String guestPath(String host) {
    if (!_androidShell && installed) {
      if (host == rootfs) return '/';
      if (host.startsWith('$rootfs/')) return host.substring(rootfs.length);
      if (host.startsWith('/storage/emulated/0')) return '/sdcard${host.substring('/storage/emulated/0'.length)}';
    }
    return host;
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

  static bool _listable(String path) {
    try {
      Directory(path).listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }
}
