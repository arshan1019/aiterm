# xterm 4.0.0, vendored

Upstream: https://github.com/TerminalStudio/xterm.dart (MIT, see LICENSE),
copied from the pub.dev 4.0.0 release (`lib/` only). Changes, all in
`lib/src/core/escape/parser.dart` and marked `aiterm patch`:

1. **Private SGR is ignored.** `CSI > 4 ; 1 m` (modifyOtherKeys, sent by
   Claude Code and other TUIs at startup) and `CSI ? 4 m` were applied as
   SGR 4 + 1: everything turned underlined and bold until the program
   exited.
2. **Colon sub-parameters.** Digits after `:` merged into the parameter
   (`4:0` read as 40, `4:3` as 43). Now `4:0` ends underline, `4:n`
   underlines, and `38:5:n` / `38:2:[cs]:r:g:b` set colours.
3. **Empty SGR parameters are 0** (`CSI ; 4 m` = reset, then underline).
4. **38 / 48 / 58 consume their arguments**, also when truncated, so
   `58;5;4` (underline colour 4) no longer turns underline on and a short
   `38;5` can't throw.
5. **SGR 22 ends bold as well as faint.**
6. **DCS, SOS, PM and APC strings are consumed** up to ST/BEL instead of
   being printed as text.

Tests: `test/escape_sequences_test.dart` in the app.
7. **Only `< = > ?` are private prefixes.** `:` and `;` were too, so
   `CSI ; 4 m` lost its first parameter.
8. **Mouse wheel buttons are 64–67** (`lib/src/core/mouse/button.dart`).
   They were 64 + 4 … 64 + 7, X11's button numbers on top of the
   protocol's 64, so every wheel event carried the Shift bit: full-screen
   programs that scroll on the wheel (Claude Code, less, vim) saw
   Shift+wheel and didn't scroll.
9. **X10/UTF-8 mouse rows** were reported one row too low
   (`lib/src/core/mouse/reporter.dart`, `32 + y + 1` → `32 + y`).
