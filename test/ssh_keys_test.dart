import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/ssh/ssh_keys.dart';

class FakeSsh implements SshPlatform {
  final keys = <String, String>{};
  String? agentPath;
  Object? failCreate;

  @override
  Future<List<SshKey>> list() async => [for (final e in keys.entries) SshKey(e.key, e.value)];
  @override
  Future<SshKey> create(String name) async {
    if (failCreate != null) throw failCreate!;
    keys[name] = 'ecdsa-sha2-nistp256 AAAA $name@aiterm';
    return SshKey(name, keys[name]!);
  }

  @override
  Future<void> delete(String name) async => keys.remove(name);
  @override
  Future<void> startAgent(String path) async => agentPath = path;
}

void main() {
  late FakeSsh platform;
  late SshKeys keys;
  setUp(() {
    platform = FakeSsh();
    keys = SshKeys(platform);
  });

  test('loads, creates and deletes keys', () async {
    await keys.load();
    expect(keys.keys, isEmpty);
    final k = await keys.create('laptop');
    expect(k!.publicKey, startsWith('ecdsa-sha2-nistp256 '));
    expect(keys.keys.map((k) => k.name), ['laptop']);
    await keys.delete('laptop');
    expect(keys.keys, isEmpty);
  });

  test('a refused name shows the reason', () async {
    platform.failCreate = Exception('Use letters, digits, . _ -');
    expect(await keys.create('bad name'), isNull);
    expect(keys.error, contains('letters'));
  });

  test('the agent socket lives in the guest /tmp', () async {
    await keys.startAgent(rootfs: '/data/x/alpine');
    expect(platform.agentPath, '/data/x/alpine/tmp/aiterm-agent.sock');
    expect(SshKeys.guestSocket, '/tmp/aiterm-agent.sock');
  });
}
