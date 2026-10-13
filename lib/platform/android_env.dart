import 'package:flutter/services.dart';

/// App directories, read once at startup.
class AppPaths {
  /// Where Android extracted the jniLibs (proot lives here; it's the only
  /// place an app may exec its own binaries from).
  final String nativeLibDir;
  final String filesDir;
  final String cacheDir;

  /// Milliseconds since boot when the app started.
  final int uptimeMs;

  /// When the phone booted (fixed; Linux's btime).
  final DateTime bootTime;

  AppPaths({
    required this.nativeLibDir,
    required this.filesDir,
    required this.cacheDir,
    required this.uptimeMs,
    DateTime? bootTime,
  }) : bootTime = bootTime ?? DateTime.now().subtract(Duration(milliseconds: uptimeMs));
}

/// The small "aiterm/env" channel (MainActivity.kt).
class AndroidEnv {
  static const _channel = MethodChannel('aiterm/env');

  static Future<AppPaths> paths() async {
    final p = (await _channel.invokeMapMethod<String, String>('paths'))!;
    return AppPaths(
      nativeLibDir: p['nativeLibDir']!,
      filesDir: p['filesDir']!,
      cacheDir: p['cacheDir']!,
      uptimeMs: int.tryParse(p['uptimeMs'] ?? '') ?? 0,
      bootTime: switch (int.tryParse(p['bootTimeMs'] ?? '')) {
        final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
        null => null,
      },
    );
  }

  /// Opens [url] in the user's browser. Throws [PlatformException] if no app
  /// can handle it.
  static Future<void> openUrl(String url) => _channel.invokeMethod('openUrl', {'url': url});

  /// Whether the app may read and write phone storage (All files access).
  static Future<bool> storageAccess() async => await _channel.invokeMethod<bool>('storageAccess') ?? false;

  /// Opens the system screen to grant All files access (Android 11+).
  static Future<void> requestStorageAccess() => _channel.invokeMethod('requestStorageAccess');

  /// Asks for the microphone; true once granted.
  static Future<bool> requestMic() async => await _channel.invokeMethod<bool>('requestMic') ?? false;
}
