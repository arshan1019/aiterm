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
    await File(_marker).writeAsString(fileName);
    await _provision();

    installed = true;
    notifyListeners();
  }

  /// Helpers the app keeps in the guest. Rewritten on every launch so
  /// existing installs pick up fixes with an app update.
  Future<void> _provision() async {
    await File('$rootfs/etc/profile.d/aiterm.sh').writeAsString(_profile);
    final installer = File('$rootfs/usr/local/bin/install-claude');
    await installer.parent.create(recursive: true);
    await installer.writeAsString(_installClaude);
    await Process.run('/system/bin/chmod', ['755', installer.path]);
  }

  // ~/.local/bin first so the native Claude Code wins over npm's wrapper.
  static const _profile = r'''
export PATH="$HOME/.local/bin:$PATH"
command -v rg >/dev/null 2>&1 && export USE_BUILTIN_RIPGREP=0
''';

  // npm's @anthropic-ai/claude-code is a wrapper whose real binary is an
  // optional dependency; npm silently skips it when that download fails.
  // The native installer has a musl build that runs under proot.
  static const _installClaude = r'''#!/bin/sh
set -e
echo "Installing dependencies..."
apk add --no-cache bash curl libgcc libstdc++ ripgrep
echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
# Drop a broken npm copy so it can't shadow the native one.
npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
echo
echo "Done. Run: claude"
''';

  Future<SessionSpec> sessionSpec() async {
    await init();
    if (installed) await _provision();
    // proot links against libtalloc.so.2, but jniLibs must be named lib*.so.
    // nativeLibDir moves on every app update, so rebuild the link each time.
    final libDir = Directory('$filesDir/lib');
    await libDir.create(recursive: true);
    final talloc = Link('${libDir.path}/libtalloc.so.2');
    if (await talloc.exists()) await talloc.delete();
    await talloc.create('$nativeLibDir/libtalloc.so');
    final tmp = Directory('$cacheDir/proot-tmp');
    await tmp.create(recursive: true);

    final argv = <String>[
      '$nativeLibDir/libproot.so',
      '--kill-on-exit',
      '--link2symlink',
      '-0',
      '-r', rootfs,
      '-b', '/dev',
      '-b', '/proc',
      '-b', '/sys',
      if (await _canRead('/storage/emulated/0')) ...['-b', '/storage/emulated/0:/sdcard'],
      '-w', '/root',
      '/usr/bin/env', '-i',
      'HOME=/root',
      'USER=root',
      'TERM=xterm-256color',
      'LANG=C.UTF-8',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      '/bin/sh', '-l',
    ];
    final env = {
      'PROOT_LOADER': '$nativeLibDir/libproot-loader.so',
      'PROOT_TMP_DIR': tmp.path,
      'LD_LIBRARY_PATH': '${libDir.path}:$nativeLibDir',
    };
    return SessionSpec(argv, env, filesDir);
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
