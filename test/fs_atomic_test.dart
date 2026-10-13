import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/shared/fs_atomic.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('aiterm_atomic'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('many tabs starting at once all succeed (was PathExistsException)', () async {
    final path = '${dir.path}/libtalloc.so.2';
    await Future.wait([for (var i = 0; i < 25; i++) ensureLink(path, '/data/app/x/lib/libtalloc.so')]);
    expect(Link(path).targetSync(), '/data/app/x/lib/libtalloc.so');
    expect(dir.listSync().map((e) => e.path.split('/').last), ['libtalloc.so.2'], reason: 'no temp links left');
  });

  test('a link to an old location (app updated) is replaced', () async {
    final path = '${dir.path}/libtalloc.so.2';
    Link(path).createSync('/data/app/old/lib/libtalloc.so');
    await ensureLink(path, '/data/app/new/lib/libtalloc.so');
    expect(Link(path).targetSync(), '/data/app/new/lib/libtalloc.so');
  });

  test('a correct link is left as it is', () async {
    final path = '${dir.path}/l';
    Link(path).createSync('/target');
    final before = Link(path).statSync().changed;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await ensureLink(path, '/target');
    expect(Link(path).statSync().changed, before);
  });

  test('concurrent writes never leave a mixed or partial file', () async {
    final path = '${dir.path}/aiterm.sh';
    final contents = [for (var i = 0; i < 20; i++) 'version $i\n' * 2000];
    await Future.wait([for (final c in contents) writeFileAtomic(path, c)]);
    expect(contents, contains(File(path).readAsStringSync()));
    expect(dir.listSync(), hasLength(1), reason: 'no temp files left');
  });
}
