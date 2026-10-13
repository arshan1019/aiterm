import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import '../assistant/error_fixes.dart';
import '../linux/session_spec.dart';
import '../platform/pty.dart';
import 'key_mapping.dart';

enum SessionState { idle, starting, running, exited }

/// Sticky CTRL/ALT from the key bar (next key only) and Volume Down held as
/// Ctrl, as in Termux.
class Modifiers extends ChangeNotifier {
  bool _ctrl = false, _alt = false, _volume = false;

  bool get volumeCtrl => _volume;
  set volumeCtrl(bool v) {
    if (v == _volume) return;
    _volume = v;
    notifyListeners();
  }

  bool get ctrl => _ctrl;
  bool get alt => _alt;

  void toggleCtrl() {
    _ctrl = !_ctrl;
    notifyListeners();
  }

  void toggleAlt() {
    _alt = !_alt;
    notifyListeners();
  }

  /// The modifiers for the next key; the sticky ones are used up.
  ({bool ctrl, bool alt}) take() {
    final m = (ctrl: _ctrl || _volume, alt: _alt);
    if (_ctrl || _alt) {
      _ctrl = _alt = false;
      notifyListeners();
    }
    return m;
  }

  bool get any => _ctrl || _alt || _volume;
}

/// One terminal tab: the emulator, the shell's PTY, and what's derived from
/// its output. Lives outside the widget tree, so tabs keep running while
/// hidden and widgets only render.
class TerminalSession {
  TerminalSession({required this.id, required this._title, this._customTitle = false, this._pinned = false}) {
    terminal.onOutput = _onInput;
    terminal.onResize = (cols, rows, _, _) => _onResize(rows, cols);
    terminal.onTitleChange = _onShellTitle;
  }

  final int id;
  final terminal = _AppTerminal();
  final selection = TerminalController();
  final modifiers = Modifiers();

  final state = ValueNotifier(SessionState.idle);

  /// Why the last start failed, if it did.
  String? error;

  /// A suggested fix for the newest error in the output, if recognised.
  final fix = ValueNotifier<ErrorFix?>(null);

  /// Called when the tab's title or pin changes (the tab strip listens).
  VoidCallback? onMetaChanged;

  String _title;
  bool _customTitle;
  bool _pinned;
  String get title => _title;
  bool get customTitle => _customTitle;
  bool get pinned => _pinned;

  set pinned(bool v) {
    _pinned = v;
    onMetaChanged?.call();
  }

  void rename(String name) {
    _title = name;
    _customTitle = true;
    onMetaChanged?.call();
  }

  PtySession? _pty;
  StreamSubscription<String>? _output;
  bool _alpine = true;
  bool _applyingModifier = false;
  bool _disposed = false;

  // The keyboard animation resizes the view repeatedly; only the settled
  // size goes to the shell, so it redraws its prompt once.
  Timer? _resizeTimer;

  // Output since the last Enter, scanned for known errors once it settles.
  final _recent = StringBuffer();
  Timer? _fixTimer;
  ErrorFix? _dismissed;

  /// Starts the shell at the terminal's current size. Call after the view
  /// has laid out, so the first prompt is drawn at the right width.
  Future<void> start(Future<SessionSpec> Function() spec, {required bool alpine}) async {
    if (state.value == SessionState.starting || state.value == SessionState.running) return;
    _alpine = alpine;
    error = null;
    fix.value = null;
    _setState(SessionState.starting);
    try {
      final s = await spec();
      final pty = await PtyHost.instance.start(
        argv: s.argv,
        env: s.env,
        cwd: s.cwd,
        rows: terminal.viewHeight,
        cols: terminal.viewWidth,
      );
      if (_disposed) {
        pty.stop();
        return;
      }
      _pty = pty;
      // Streaming decode: a character split across two reads must not
      // become replacement glyphs.
      _output = pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((text) {
        terminal.write(text);
        _watchForErrors(text);
      });
      pty.exitCode.then((code) {
        if (_disposed || _pty != pty) return;
        terminal.write('\r\n[process exited: $code]\r\n');
        _pty = null;
        _setState(SessionState.exited);
      });
      _setState(SessionState.running);
    } catch (e) {
      error = '$e';
      _setState(SessionState.exited);
    }
  }

  /// The tab may be closed while a start is still in flight.
  void _setState(SessionState s) {
    if (!_disposed) state.value = s;
  }

  Future<void> restart(Future<SessionSpec> Function() spec, {required bool alpine}) async {
    _stopShell();
    _setState(SessionState.idle);
    await start(spec, alpine: alpine);
  }

  /// Text typed by the user or pasted; goes through the modifiers.
  void _onInput(String data) {
    if (!_applyingModifier && modifiers.any && data.runes.length == 1) {
      final m = modifiers.take();
      _applyingModifier = true;
      final handled = terminal.charInput(data.runes.first, ctrl: m.ctrl, alt: m.alt);
      _applyingModifier = false;
      if (handled) return;
    }
    _pty?.write(data);
    if (data.contains('\r')) {
      // A new command started: earlier errors no longer apply.
      _recent.clear();
      fix.value = null;
    }
  }

  /// A key from the key bar (arrows, Esc, Tab), with the modifiers applied.
  void sendKey(TerminalKey key) {
    final m = modifiers.take();
    terminal.keyInput(key, ctrl: m.ctrl, alt: m.alt);
  }

  /// Text from the key bar ("/", "-", "|"), with the modifiers applied.
  void sendText(String text) => terminal.textInput(text);

  /// Types [command] at the prompt without pressing Enter.
  void insert(String command) => _pty?.write(command);

  void paste(String text) => terminal.paste(text);

  void dismissFix() {
    _dismissed = fix.value;
    fix.value = null;
  }

  void _onResize(int rows, int cols) {
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 80), () => _pty?.resize(rows, cols));
  }

  void _onShellTitle(String raw) {
    final t = raw.trim();
    if (_customTitle || t.isEmpty || t == _title) return;
    _title = t.length > 24 ? '${t.substring(0, 24)}…' : t;
    onMetaChanged?.call();
  }

  void _watchForErrors(String text) {
    _recent.write(text);
    if (_recent.length > 8000) {
      final keep = _recent.toString().substring(_recent.length - 4000);
      _recent
        ..clear()
        ..write(keep);
    }
    _fixTimer?.cancel();
    // Judge the whole error once output pauses, not a fragment of it.
    _fixTimer = Timer(const Duration(milliseconds: 500), () {
      final f = detectFix(_recent.toString(), alpine: _alpine);
      if (f != fix.value && f != _dismissed) fix.value = f;
    });
  }

  void _stopShell() {
    _output?.cancel();
    _output = null;
    _pty?.stop();
    _pty = null;
  }

  void dispose() {
    _disposed = true;
    _resizeTimer?.cancel();
    _fixTimer?.cancel();
    _stopShell();
    selection.dispose();
    modifiers.dispose();
    state.dispose();
    fix.dispose();
  }
}

/// xterm's own mapping misses Ctrl+Space and friends and sends Alt+b as
/// ESC B; the Termux rules apply to the key bar and hardware keyboards.
class _AppTerminal extends Terminal {
  _AppTerminal() : super(maxLines: 10000);

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) {
    if (!ctrl && !alt) return false;
    final out = modifiedChar(charCode, ctrl: ctrl, alt: alt);
    if (out == null) return false;
    onOutput?.call(out);
    return true;
  }
}
