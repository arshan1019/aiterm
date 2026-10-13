import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SshKey {
  const SshKey(this.name, this.publicKey);
  final String name;

  /// "ecdsa-sha2-nistp256 AAAA… name@aiterm", for GitHub or authorized_keys.
  final String publicKey;
}

/// SSH keys kept in Android's keystore (android/.../SshAgent.kt).
abstract interface class SshPlatform {
  Future<List<SshKey>> list();
  Future<SshKey> create(String name);
  Future<void> delete(String name);
  Future<void> startAgent(String path);
}

/// The SSH keys screen's state. Keys never leave the keystore; Linux uses
/// them through the ssh-agent socket, after a fingerprint or screen lock.
class SshKeys extends ChangeNotifier {
  SshKeys(this._platform);

  final SshPlatform _platform;

  /// Where ssh in Linux finds the agent (exported as SSH_AUTH_SOCK).
  static const guestSocket = '/tmp/aiterm-agent.sock';

  List<SshKey> keys = const [];
  String? error;

  Future<void> load() async {
    keys = await _platform.list();
    notifyListeners();
  }

  /// Creates a key; null (with [error] set) if refused.
  Future<SshKey?> create(String name) async {
    try {
      final k = await _platform.create(name);
      error = null;
      await load();
      return k;
    } catch (e) {
      error = e is PlatformException ? e.message : '$e'.replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<void> delete(String name) async {
    await _platform.delete(name);
    await load();
  }

  Future<void> startAgent({required String rootfs}) => _platform.startAgent('$rootfs$guestSocket');
}

class SshChannel implements SshPlatform {
  static const _channel = MethodChannel('aiterm/ssh');

  static SshKey _key(Object? raw) {
    final m = raw! as Map;
    return SshKey(m['name'] as String, m['publicKey'] as String);
  }

  @override
  Future<List<SshKey>> list() async => [for (final m in await _channel.invokeListMethod<Object?>('list') ?? []) _key(m)];
  @override
  Future<SshKey> create(String name) async => _key(await _channel.invokeMethod('create', {'name': name}));
  @override
  Future<void> delete(String name) => _channel.invokeMethod('delete', {'name': name});
  @override
  Future<void> startAgent(String path) => _channel.invokeMethod('startAgent', {'path': path});
}
