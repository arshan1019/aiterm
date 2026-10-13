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

  const AppPaths({
    required this.nativeLibDir,
    required this.filesDir,
    required this.cacheDir,
    required this.uptimeMs,
  });
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
    );
  }

  /// Opens [url] in the user's browser. Throws [PlatformException] if no app
  /// can handle it.
  static Future<void> openUrl(String url) => _channel.invokeMethod('openUrl', {'url': url});

  /// Asks for the microphone; true once granted.
  static Future<bool> requestMic() async => await _channel.invokeMethod<bool>('requestMic') ?? false;
}
