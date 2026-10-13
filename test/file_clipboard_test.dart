import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/files/file_clipboard.dart';
import 'package:aiterm/files/file_system_service.dart';
import 'package:aiterm/files/files_browser.dart';

void main() {
  late Directory root, linux, phone;
  final fs = FileSystemService();

  setUp(() {
    root = Directory.systemTemp.createTempSync('aiterm_clip');
    linux = Directory('${root.path}/linux')..createSync();
    phone = Directory('${root.path}/phone')..createSync();
    File('${linux.path}/notes.txt').writeAsStringSync('hello');
    Directory('${linux.path}/proj/src').createSync(recursive: true);
    File('${linux.path}/proj/src/main.dart').writeAsStringSync('void main() {}');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<FsEntry> entry(String path) async =>
      (await fs.list(File(path).parent.path)).firstWhere((e) => e.path == path);

  test('copy a file to another location keeps the original', () async {
    final clip = FileClipboard();
    clip.copy([await entry('${linux.path}/notes.txt')]);
    expect(clip.hasItems, isTrue);
    final done = await clip.paste(phone.path);
    expect(done, ['${phone.path}/notes.txt']);
    expect(File('${phone.path}/notes.txt').readAsStringSync(), 'hello');
    expect(File('${linux.path}/notes.txt').existsSync(), isTrue);
    expect(clip.hasItems, isTrue, reason: 'a copy can be pasted again');
  });

  test('copy a folder copies everything inside', () async {
    final clip = FileClipboard()..copy([await entry('${linux.path}/proj')]);
    await clip.paste(phone.path);
    expect(File('${phone.path}/proj/src/main.dart').readAsStringSync(), 'void main() {}');
  });

  test('move removes the original and empties the clipboard', () async {
    final clip = FileClipboard()..cut([await entry('${linux.path}/proj')]);
    await clip.paste(phone.path);
    expect(Directory('${linux.path}/proj').existsSync(), isFalse);
    expect(File('${phone.path}/proj/src/main.dart').existsSync(), isTrue);
    expect(clip.hasItems, isFalse);
  });

  test('a name that already exists gets a numbered copy, never overwritten', () async {
    File('${phone.path}/notes.txt').writeAsStringSync('keep me');
    final clip = FileClipboard()..copy([await entry('${linux.path}/notes.txt')]);
    expect(await clip.paste(phone.path), ['${phone.path}/notes (2).txt']);
    expect(await clip.paste(phone.path), ['${phone.path}/notes (3).txt']);
    expect(File('${phone.path}/notes.txt').readAsStringSync(), 'keep me');
  });

  test('pasting a copy into its own folder makes a numbered copy', () async {
    final clip = FileClipboard()..copy([await entry('${linux.path}/notes.txt')]);
    expect(await clip.paste(linux.path), ['${linux.path}/notes (2).txt']);
  });

  test('a folder cannot be pasted inside itself', () async {
    final clip = FileClipboard()..copy([await entry('${linux.path}/proj')]);
    expect(() => clip.paste('${linux.path}/proj/src'), throwsA(isA<FileSystemException>()));
  });

  test('moving into the same folder does nothing', () async {
    final clip = FileClipboard()..cut([await entry('${linux.path}/notes.txt')]);
    expect(await clip.paste(linux.path), isEmpty);
    expect(File('${linux.path}/notes.txt').existsSync(), isTrue);
  });

  group('locations', () {
    test('switching location starts fresh at its root, with its own crumbs', () async {
      final b = FilesBrowser(root: linux.path, rootfs: null, locations: [
        FilesLocation.linux(linux.path),
        FilesLocation.phone(phone.path),
      ]);
      await b.load();
      expect(b.location.kind, LocationKind.linux);
      await b.switchTo(LocationKind.phone);
      expect(b.current, phone.path);
      expect(b.crumbs.first.label, 'Phone');
      expect(b.canGoBack, isFalse, reason: 'history belongs to a location');
      await b.switchTo(LocationKind.linux);
      expect(b.current, linux.path);
      expect(b.crumbs.first.label, '~');
    });
  });
}
