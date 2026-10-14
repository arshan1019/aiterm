/// One line of a diff: kept (' '), removed ('-') or added ('+').
class DiffLine {
  const DiffLine(this.op, this.text, {this.oldNo, this.newNo});
  final String op;
  final String text;
  final int? oldNo, newNo;

  @override
  bool operator ==(Object other) => other is DiffLine && other.op == op && other.text == text;
  @override
  int get hashCode => Object.hash(op, text);
  @override
  String toString() => '$op$text';
}

List<String> _lines(String? s) {
  if (s == null || s.isEmpty) return const [];
  final lines = s.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// The lines that changed from [oldText] to [newText] (null: a new file),
/// by longest common subsequence. Past [limit] cells of work (huge files)
/// it shows everything old as removed and everything new as added.
List<DiffLine> lineDiff(String? oldText, String newText, {int limit = 4000000}) {
  final a = _lines(oldText), b = _lines(newText);
  // Common head and tail cost nothing.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final out = <DiffLine>[
    for (var i = 0; i < start; i++) DiffLine(' ', a[i], oldNo: i + 1, newNo: i + 1),
  ];
  final n = endA - start, m = endB - start;
  if (n * m > limit) {
    for (var i = start; i < endA; i++) {
      out.add(DiffLine('-', a[i], oldNo: i + 1));
    }
    for (var j = start; j < endB; j++) {
      out.add(DiffLine('+', b[j], newNo: j + 1));
    }
  } else {
    // lcs[i][j]: common length of a[start+i..] and b[start+j..].
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = a[start + i] == b[start + j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n || j < m) {
      if (i < n && j < m && a[start + i] == b[start + j]) {
        out.add(DiffLine(' ', a[start + i], oldNo: start + i + 1, newNo: start + j + 1));
        i++;
        j++;
      } else if (i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1])) {
        // Removed before added, as git shows it.
        out.add(DiffLine('-', a[start + i], oldNo: start + i + 1));
        i++;
      } else {
        out.add(DiffLine('+', b[start + j], newNo: start + j + 1));
        j++;
      }
    }
  }
  for (var k = 0; k < a.length - endA; k++) {
    out.add(DiffLine(' ', a[endA + k], oldNo: endA + k + 1, newNo: endB + k + 1));
  }
  return out;
}

/// The changed lines with [context] kept lines around them; null entries
/// mark skipped stretches.
List<DiffLine?> diffHunks(List<DiffLine> diff, {int context = 2}) {
  final keep = List<bool>.filled(diff.length, false);
  for (var i = 0; i < diff.length; i++) {
    if (diff[i].op == ' ') continue;
    for (var k = i - context; k <= i + context; k++) {
      if (k >= 0 && k < diff.length) keep[k] = true;
    }
  }
  final out = <DiffLine?>[];
  for (var i = 0; i < diff.length; i++) {
    if (keep[i]) {
      out.add(diff[i]);
    } else if (out.isNotEmpty && out.last != null) {
      out.add(null);
    }
  }
  if (out.isNotEmpty && out.last == null) out.removeLast();
  return out;
}

/// "+3 −1".
(int, int) diffCounts(List<DiffLine> diff) =>
    (diff.where((l) => l.op == '+').length, diff.where((l) => l.op == '-').length);
