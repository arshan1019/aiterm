import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/phone/phone_files.dart';

void main() {
  const tree = 'content://com.android.externalstorage.documents/tree/primary%3ADownload';

  test('a chosen folder and what is inside it round-trip through paths', () {
    final folder = PhonePath.ofTree(tree);
    expect(PhonePath.isPhone(folder), isTrue);
    expect(PhonePath.parse(folder)!.tree, tree);
    expect(PhonePath.parse(folder)!.doc, isNull);

    final sub = PhonePath.child(folder, 'primary:Download/assets');
    final file = PhonePath.child(sub, 'primary:Download/assets/logo.png');
    final p = PhonePath.parse(file)!;
    expect(p.tree, tree);
    expect(p.doc, 'primary:Download/assets/logo.png');
    expect(p.args, {'tree': tree, 'doc': 'primary:Download/assets/logo.png'});

    expect(PhonePath.parentOf(file), sub);
    expect(PhonePath.parentOf(sub), folder);
    expect(PhonePath.parentOf(folder), PhonePath.root);
    expect(PhonePath.parentOf(PhonePath.root), isNull);
  });

  test('a single chosen file is named by its uri', () {
    const uri = 'content://com.android.providers.downloads.documents/document/msf%3A42';
    final path = PhonePath.ofFile(uri);
    final p = PhonePath.parse(path)!;
    expect(p.uri, uri);
    expect(p.args, {'tree': null, 'doc': uri});
    expect(PhonePath.parentOf(path), PhonePath.root);
  });

  test('Linux paths are not phone paths', () {
    expect(PhonePath.isPhone('/root/app'), isFalse);
    expect(PhonePath.isPhone('phone:'), isTrue);
    expect(PhonePath.parse('phone:'), isNull);
  });
}
