import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SessionSpec {
  final List<String> argv;
  final Map<String, String> env;
  final String cwd;
  const SessionSpec(this.argv, this.env, this.cwd);
}

/// Installs Alpine Linux into the app's private storage and builds the
/// proot command line that runs a shell inside it.
///
/// proot and its libs come from Termux's repo via scripts/fetch_proot.sh and
/// are packaged as jniLibs, because Android only lets an app exec files
/// that live in its native library directory.
class DistroManager extends ChangeNotifier {
  DistroManager._();
  static final instance = DistroManager._();

  static const _channel = MethodChannel('aiterm/env');
  static const _releases =
      'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64';

  late final String nativeLibDir;
  late final String filesDir;
  late final String cacheDir;
  String _uptimeMs = '0';
  bool _ready = false;
  bool installed = false;

  String get rootfs => '$filesDir/alpine';
  String get home => '$rootfs/root';
  String get _marker => '$rootfs/.aiterm-installed';

  Future<void> init() async {
    if (_ready) return;
    final p = await _channel.invokeMapMethod<String, String>('paths');
    nativeLibDir = p!['nativeLibDir']!;
    filesDir = p['filesDir']!;
    cacheDir = p['cacheDir']!;
    _uptimeMs = p['uptimeMs'] ?? '0';
    _ready = true;
    installed = await File(_marker).exists();
    notifyListeners();
  }

  Future<void> install(void Function(String status, double? progress) onProgress) async {
    await init();
    onProgress('Finding latest Alpine release', null);
    final index = await http.read(Uri.parse('$_releases/latest-releases.yaml'));
    final entry = index
        .split(RegExp(r'^-\s*$', multiLine: true))
        .firstWhere((e) => e.contains('flavor: alpine-minirootfs'),
            orElse: () => throw StateError('No minirootfs in Alpine release index'));
    String field(String name) =>
        RegExp('^\\s*$name: (\\S+)', multiLine: true).firstMatch(entry)!.group(1)!;
    final fileName = field('file');
    final expectedSha = field('sha256');

    final tarball = File('$cacheDir/$fileName');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse('$_releases/$fileName')));
      if (resp.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = tarball.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress('Downloading $fileName', total == null ? null : received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }

    onProgress('Verifying', null);
    final actualSha = (await sha256.bind(tarball.openRead()).first).toString();
    if (actualSha != expectedSha) {
      await tarball.delete();
      throw StateError('Checksum mismatch for $fileName');
    }

    onProgress('Extracting', null);
    final dir = Directory(rootfs);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    // Android's toybox tar keeps symlinks and exec bits, which busybox's
    // applet symlinks depend on; Dart's archive package would lose both.
    final tar = await Process.run('/system/bin/tar', ['-xzf', tarball.path, '-C', rootfs]);
    await tarball.delete();
    if (!await File('$rootfs/bin/busybox').exists()) {
      throw StateError('Extraction failed: ${tar.stderr}');
    }

    // The guest can't see Android's resolver config.
    await File('$rootfs/etc/resolv.conf')
        .writeAsString('nameserver 1.1.1.1\nnameserver 8.8.8.8\n');
    await File('$rootfs/etc/hosts')
        .writeAsString('127.0.0.1 localhost\n::1 localhost\n');
    await File('$rootfs/etc/hostname').writeAsString('localhost\n');
    await File(_marker).writeAsString(fileName);

    installed = true;
    notifyListeners();
  }

  static const _kernelRelease = '6.17.0-aiterm';
  static const _kernelVersion = '#1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000';

  /// The proot session, set up the way Termux's proot-distro sets up a
  /// distro so programs see an ordinary Linux system: emulated hard links,
  /// SysV IPC and a modern kernel version; the usual /dev entries; and
  /// stand-ins for /proc files Android hides from apps.
  Future<SessionSpec> sessionSpec() async {
    await init();
    // proot links against libtalloc.so.2, but jniLibs must be named lib*.so.
    // nativeLibDir moves on every app update, so rebuild the link each time.
    final libDir = Directory('$filesDir/lib');
    await libDir.create(recursive: true);
    final talloc = Link('${libDir.path}/libtalloc.so.2');
    if (await talloc.exists()) await talloc.delete();
    await talloc.create('$nativeLibDir/libtalloc.so');
    final tmp = Directory('$cacheDir/proot-tmp');
    await tmp.create(recursive: true);

    // Sticky world-writable /tmp and /dev/shm, as on any Linux box.
    final shm = Directory('$filesDir/shm');
    await shm.create(recursive: true);
    await Directory('$rootfs/tmp').create(recursive: true);
    await Process.run('/system/bin/chmod', ['1777', shm.path, '$rootfs/tmp']);

    final shell = await _loginShell();
    final args = <String>[
      '$nativeLibDir/libproot.so',
      '--kill-on-exit',
      '--link2symlink',
      '--sysvipc',
      // Android kernels report old versions some tools refuse to run on.
      '--kernel-release=\\Linux\\localhost\\$_kernelRelease\\$_kernelVersion\\aarch64\\localdomain\\-1\\',
      '-L',
      '--change-id=0:0',
      '--rootfs=$rootfs',
      '--cwd=/root',
      '--bind=/dev',
      '--bind=/proc',
      '--bind=/sys',
      '--bind=/dev/urandom:/dev/random',
      '--bind=${shm.path}:/dev/shm',
      if (!_exists('/dev/fd')) '--bind=/proc/self/fd:/dev/fd',
      for (final (i, name) in [(0, 'stdin'), (1, 'stdout'), (2, 'stderr')])
        if (!_exists('/dev/$name')) '--bind=/proc/self/fd/$i:/dev/$name',
      ...await _sysdataBinds(),
      // Android's own tree, for running device tools like getprop.
      for (final p in const [
        '/apex', '/odm', '/product', '/system', '/system_ext', '/vendor',
        '/linkerconfig/ld.config.txt', '/linkerconfig/com.android.art/ld.config.txt',
        '/plat_property_contexts', '/property_contexts',
      ])
        if (_exists(p)) '--bind=$p',
      if (await _canRead('/storage/emulated/0')) ...[
        '--bind=/storage',
        '--bind=/storage/emulated/0:/sdcard',
        '--bind=/storage/emulated/0:/mnt/sdcard',
      ],
      '/usr/bin/env', '-i',
      for (final e in _guestEnv(shell).entries) '${e.key}=${e.value}',
      shell, '-l',
    ];
    final env = {
      'PROOT_LOADER': '$nativeLibDir/libproot-loader.so',
      'PROOT_TMP_DIR': tmp.path,
      'LD_LIBRARY_PATH': '${libDir.path}:$nativeLibDir',
    };
    return SessionSpec(args, env, filesDir);
  }

  // Deliberately no ANDROID_* variables: installers use them to detect
  // Android and pick Android builds, which a musl Linux can't run.
  Map<String, String> _guestEnv(String shell) => {
        'HOME': '/root',
        'USER': 'root',
        'LOGNAME': 'root',
        'SHELL': shell,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'LANG': 'C.UTF-8',
        'TMPDIR': '/tmp',
        'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      };

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

  /// Android (SELinux) denies apps /proc/stat, /proc/uptime and friends;
  /// top, ps, free, Node's os.cpus() and psutil all read them. Bind
  /// believable stand-ins over the ones this device blocks, like
  /// proot-distro does. They live outside the rootfs so the guest can't
  /// swap them for links to host files.
  Future<List<String>> _sysdataBinds() async {
    final dir = Directory('$filesDir/sysdata');
    await dir.create(recursive: true);
    final selinux = Directory('${dir.path}/empty');
    await selinux.create();
    final binds = ['--bind=${selinux.path}:/sys/fs/selinux'];

    final cpus = _cpuIds();
    final uptime = (int.tryParse(_uptimeMs) ?? 0) / 1000;
    final idle = uptime * cpus.length * 0.9;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String jiffies(double share) => '${(uptime * 100 * share).round()}';
    final stat = StringBuffer()
      ..writeln('cpu  ${jiffies(0.05 * cpus.length)} 0 ${jiffies(0.03 * cpus.length)} '
          '${(idle * 100).round()} 0 0 0 0 0 0');
    for (final id in cpus) {
      stat.writeln('cpu$id ${jiffies(0.05)} 0 ${jiffies(0.03)} ${jiffies(0.9)} 0 0 0 0 0 0');
    }
    stat
      ..writeln('intr 0')
      ..writeln('ctxt 0')
      ..writeln('btime ${now - uptime.round()}')
      ..writeln('processes 1')
      ..writeln('procs_running 1')
      ..writeln('procs_blocked 0')
      ..writeln('softirq 0');

    final entries = {
      '/proc/stat': stat.toString(),
      '/proc/uptime': '${uptime.toStringAsFixed(2)} ${idle.toStringAsFixed(2)}\n',
      '/proc/loadavg': '0.12 0.07 0.02 1/100 100\n',
      '/proc/version': 'Linux version $_kernelRelease (aiterm@localhost) '
          '(clang version 18) $_kernelVersion\n',
      '/proc/vmstat': '${const [
        'nr_free_pages 100000', 'nr_inactive_anon 0', 'nr_active_anon 0',
        'nr_inactive_file 0', 'nr_active_file 0', 'nr_dirty 0', 'nr_writeback 0',
        'pgpgin 0', 'pgpgout 0', 'pswpin 0', 'pswpout 0', 'pgfault 0', 'pgmajfault 0',
      ].join('\n')}\n',
      '/proc/sys/kernel/cap_last_cap': '40\n',
      '/proc/sys/fs/inotify/max_user_watches': '8192\n',
      '/proc/sys/kernel/overflowuid': '65534\n',
      '/proc/sys/kernel/overflowgid': '65534\n',
    };
    for (final MapEntry(key: real, value: content) in entries.entries) {
      if (_readable(real)) continue; // the real file is fine on this device
      final stub = File('${dir.path}/${real.substring(1).replaceAll('/', '_')}');
      await stub.writeAsString(content);
      binds.add('--bind=${stub.path}:$real');
    }
    return binds;
  }

  List<int> _cpuIds() {
    try {
      final ids = RegExp(r'^processor\s*:\s*(\d+)', multiLine: true)
          .allMatches(File('/proc/cpuinfo').readAsStringSync())
          .map((m) => int.parse(m.group(1)!))
          .toList();
      if (ids.isNotEmpty) return ids;
    } catch (_) {}
    return List.generate(Platform.numberOfProcessors, (i) => i);
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

  static bool _readable(String path) {
    try {
      final f = File(path).openSync();
      try {
        f.readSync(1);
      } finally {
        f.closeSync();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canRead(String path) async {
    try {
      await Directory(path).list().first;
      return true;
    } catch (_) {
      return false;
    }
  }
}
