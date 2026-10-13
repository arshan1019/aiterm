import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/core/link_detector.dart';

class Rows implements RowSource {
  final List<String> rows;
  final Set<int> wrapped;
  @override
  final int width;
  Rows(this.width, List<String> raw, {this.wrapped = const {}})
      : rows = [for (final r in raw) r.padRight(width)];
  @override
  int get rowCount => rows.length;
  @override
  String row(int y) => rows[y];
  @override
  bool isWrapped(int y) => wrapped.contains(y);
}

void main() {
  test('single-row URL, trailing punctuation dropped', () {
    final src = Rows(60, ['Open https://example.com/a?b=1. now']);
    final link = linkAt(src, const CellPos(10, 0))!;
    expect(link.url, 'https://example.com/a?b=1');
    expect(link.begin, const CellPos(5, 0));
    expect(link.end, const CellPos(30, 0));
    expect(linkAt(src, const CellPos(1, 0)), isNull);
  });

  test('soft-wrapped URL selected from any row', () {
    const url = 'https://claude.ai/oauth/authorize?code=true&client_id=abc123&state=xyz';
    final src = Rows(30, [url.substring(0, 30), url.substring(30, 60), url.substring(60), ''],
        wrapped: {1, 2});
    for (final y in [0, 1, 2]) {
      final link = linkAt(src, CellPos(3, y))!;
      expect(link.url, url);
      expect(link.begin, const CellPos(0, 0));
      expect(link.end, CellPos(url.length - 60, 2));
    }
  });

  test('program-wrapped URL with padding (Ink style)', () {
    const url = 'https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a&redirect=x';
    // Rows padded by one column on each side, wrapped by the program.
    final src = Rows(32, [
      ' Browser didn\'t open? Use this:',
      '',
      ' ${url.substring(0, 30)} ',
      ' ${url.substring(30, 60)} ',
      ' ${url.substring(60)}',
      '',
      ' Paste code here if prompted >',
    ]);
    final link = linkAt(src, const CellPos(5, 3))!;
    expect(link.url, url);
    expect(link.begin, const CellPos(1, 2));
    expect(link.end, CellPos(1 + url.length - 60, 4));
  });

  test('does not join ordinary short lines', () {
    final src = Rows(40, ['see https://a.io', 'next line here']);
    expect(linkAt(src, const CellPos(6, 0))!.url, 'https://a.io');
  });

  test('balanced parentheses stay, unbalanced closer dropped', () {
    final src = Rows(80, ['(https://en.wikipedia.org/wiki/Foo_(bar)) x']);
    expect(linkAt(src, const CellPos(5, 0))!.url, 'https://en.wikipedia.org/wiki/Foo_(bar)');
  });

  test('covers', () {
    const link = Link('u', CellPos(2, 1), CellPos(5, 3));
    expect(link.covers(const CellPos(3, 1), const CellPos(4, 3)), isTrue);
    expect(link.covers(const CellPos(1, 1), const CellPos(4, 3)), isFalse);
    expect(link.covers(const CellPos(3, 1), const CellPos(5, 3)), isFalse);
  });
}
