import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/shared/line_diff.dart';
import 'package:aiterm/shared/markdown_view.dart';

void main() {
  group('line diff', () {
    test('marks removed and added lines, keeping the rest', () {
      final d = lineDiff('a\nb\nc\nd\n', 'a\nB\nc\nd\ne\n');
      expect(d.map((l) => '$l'), [' a', '-b', '+B', ' c', ' d', '+e']);
      expect(diffCounts(d), (2, 1));
      expect(d[2].newNo, 2);
      expect(d[1].oldNo, 2);
    });

    test('a new file is all added', () {
      expect(lineDiff(null, 'x\ny').map((l) => '$l'), ['+x', '+y']);
    });

    test('hunks keep two lines of context and mark skipped stretches', () {
      final old = [for (var i = 1; i <= 20; i++) 'l$i'].join('\n');
      final now = old.replaceFirst('l10', 'ten');
      final h = diffHunks(lineDiff(old, now));
      expect(h.map((l) => l?.toString()), [' l8', ' l9', '-l10', '+ten', ' l11', ' l12']);
      final two = old.replaceFirst('l2\n', 'two\n').replaceFirst('l18', 'eighteen');
      expect(diffHunks(lineDiff(old, two)).where((l) => l == null), hasLength(1));
    });

    test('huge inputs fall back to removed-then-added', () {
      final d = lineDiff('a\nb', 'c\nd', limit: 1);
      expect(d.map((l) => '$l'), ['-a', '-b', '+c', '+d']);
    });
  });

  group('markdown', () {
    test('splits paragraphs, headings, lists, quotes and code', () {
      final b = parseMarkdown('# Plan\n\nFirst line\ncontinues.\n\n- one\n- two\n  more\n1. three\n> note\n\n```dart\nvoid main() {}\n```\nAfter');
      expect(b.map((x) => x.runtimeType), [MdHeading, MdParagraph, MdItem, MdItem, MdItem, MdQuote, MdCode, MdParagraph]);
      expect((b[1] as MdParagraph).text, 'First line continues.');
      expect((b[3] as MdItem).text, 'two more');
      expect((b[4] as MdItem).marker, '1.');
      expect((b[6] as MdCode).code, 'void main() {}');
      expect((b[6] as MdCode).language, 'dart');
    });

    test('a fence still streaming runs to the end', () {
      final b = parseMarkdown('Here:\n```\nnpm test');
      expect((b.last as MdCode).code, 'npm test');
    });
  });
}
