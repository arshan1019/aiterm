/// Finds the URL under a terminal cell, including URLs that span rows.
///
/// A long URL reaches the next row in one of two ways: the terminal wraps
/// it (the row is flagged as wrapped), or the program wraps it itself with
/// real newlines, as TUI frameworks like Ink (Claude Code) do. The second
/// kind is recognised when a row's URL text runs to the right edge and the
/// next row carries on with URL characters near the left edge.
library;

class CellPos {
  final int x, y;
  const CellPos(this.x, this.y);

  @override
  bool operator ==(Object other) => other is CellPos && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => '($x, $y)';
}

class Link {
  final String url;

  /// First cell of the URL.
  final CellPos begin;

  /// One past the last cell, matching xterm's exclusive selection end.
  final CellPos end;

  const Link(this.url, this.begin, this.end);

  /// True when the cells from [a] to [b] (inclusive) lie within this link.
  bool covers(CellPos a, CellPos b) => !_before(a, begin) && _before(b, end);

  static bool _before(CellPos a, CellPos b) => a.y < b.y || (a.y == b.y && a.x < b.x);
}

/// Row access, so the detector can run on xterm's buffer or plain strings.
abstract class RowSource {
  int get rowCount;
  int get width;

  /// Row text with exactly one character per cell (blank cells as spaces).
  String row(int y);

  /// True when row [y] is a terminal soft-wrap continuation of row y-1.
  bool isWrapped(int y);
}

final _urlPattern = RegExp(r'''(?:https?|ftp|file)://[^\s<>"'`]+''');
final _urlChar = RegExp(r'''[^\s<>"'`]''');
const _maxRows = 24;

Link? linkAt(RowSource src, CellPos at) {
  if (at.y < 0 || at.y >= src.rowCount) return null;
  var top = at.y, bottom = at.y;
  while (top > 0 && at.y - top < _maxRows && _continues(src, top - 1)) {
    top--;
  }
  while (bottom + 1 < src.rowCount && bottom - at.y < _maxRows && _continues(src, bottom)) {
    bottom++;
  }

  // Join the rows, remembering which cell each character came from.
  final text = StringBuffer();
  final cells = <CellPos>[];
  for (var y = top; y <= bottom; y++) {
    final row = src.row(y);
    var from = 0, to = row.length;
    final hardBefore = y > top && !src.isWrapped(y);
    final hardAfter = y < bottom && !src.isWrapped(y + 1);
    if (hardBefore) from = row.length - row.trimLeft().length;
    if (hardAfter) to = row.trimRight().length;
    for (var x = from; x < to; x++) {
      text.write(row[x]);
      cells.add(CellPos(x, y));
    }
  }

  final index = cells.indexOf(at);
  if (index < 0) return null;
  for (final m in _urlPattern.allMatches(text.toString())) {
    final end = m.start + _trimmedLength(m.group(0)!);
    if (index >= m.start && index < end) {
      final last = cells[end - 1];
      return Link(text.toString().substring(m.start, end), cells[m.start], CellPos(last.x + 1, last.y));
    }
  }
  return null;
}

/// Whether row [y]'s text carries on into row y+1.
bool _continues(RowSource src, int y) {
  if (src.isWrapped(y + 1)) return true;
  final row = src.row(y).trimRight();
  final next = src.row(y + 1);
  if (row.isEmpty || row.length < src.width - 2) return false; // didn't reach the edge
  final lastToken = row.substring(row.lastIndexOf(' ') + 1);
  final lead = next.length - next.trimLeft().length;
  if (lead > 4 || next.trim().isEmpty) return false;
  final firstToken = next.trimLeft().split(' ').first;
  return lastToken.isNotEmpty &&
      lastToken.split('').every(_urlChar.hasMatch) &&
      firstToken.split('').every(_urlChar.hasMatch) &&
      !firstToken.contains('://');
}

/// Drops sentence punctuation and unbalanced closing brackets at the end.
int _trimmedLength(String url) {
  var n = url.length;
  while (n > 0) {
    final c = url[n - 1];
    if ('.,;:!?'.contains(c)) {
      n--;
    } else if (')]}'.contains(c)) {
      final open = '([{'[')]}'.indexOf(c)];
      final s = url.substring(0, n);
      if (open.allMatches(s).length < c.allMatches(s).length) {
        n--;
      } else {
        break;
      }
    } else {
      break;
    }
  }
  return n;
}
