import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/core/key_mapping.dart';

void main() {
  int? ctrl(String ch) => ctrlCode(ch.codeUnitAt(0));
  String? mod(String ch, {bool ctrl = false, bool alt = false}) =>
      modifiedChar(ch.codeUnitAt(0), ctrl: ctrl, alt: alt);

  test('ctrl letters in either case', () {
    expect(ctrl('c'), 3);
    expect(ctrl('C'), 3);
    expect(ctrl('d'), 4);
    expect(ctrl('z'), 26);
  });

  test('ctrl punctuation and digit aliases', () {
    expect(ctrl(' '), 0);
    expect(ctrl('['), 27);
    expect(ctrl('/'), 31);
    expect(ctrl('8'), 127);
    expect(ctrl('1'), isNull);
  });

  test('alt prefixes ESC to the key as typed', () {
    expect(mod('b', alt: true), '\x1bb');
    expect(mod('B', alt: true), '\x1bB');
    expect(mod('c', ctrl: true, alt: true), '\x1b\x03');
    expect(mod('1', ctrl: true), isNull);
  });
}
