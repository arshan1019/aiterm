/// Control-key mapping as Termux does it: letters of either case, plus the
/// digit and punctuation aliases terminals have always accepted
/// (Ctrl+Space / Ctrl+2 = NUL, Ctrl+[ = ESC, Ctrl+/ = ^_, Ctrl+8 = DEL).
int? ctrlCode(int c) {
  if (c >= 0x61 && c <= 0x7a) return c - 0x60; // a-z
  if (c >= 0x41 && c <= 0x5a) return c - 0x40; // A-Z
  return switch (String.fromCharCode(c)) {
    ' ' || '2' || '@' => 0,
    '[' || '3' => 27,
    r'\' || '4' => 28,
    ']' || '5' => 29,
    '^' || '6' => 30,
    '_' || '7' || '/' => 31,
    '8' || '?' => 127,
    _ => null,
  };
}

/// Bytes for [c] typed with modifiers, or null if the combination has no
/// terminal encoding. Alt is ESC followed by the key as typed.
String? modifiedChar(int c, {required bool ctrl, required bool alt}) {
  var code = c;
  if (ctrl) {
    final mapped = ctrlCode(c);
    if (mapped == null) return null;
    code = mapped;
  }
  final ch = String.fromCharCode(code);
  return alt ? '\x1b$ch' : ch;
}
