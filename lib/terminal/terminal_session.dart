import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import '../assistant/error_fixes.dart';
import '../linux/session_spec.dart';
import '../platform/pty.dart';
import '../preview/ports.dart';
import 'key_mapping.dart';
import 'shell_integration.dart';

enum SessionState { idle, starting, running, exited }

/// Builds what to run for a tab, starting in [cwd] (a guest path) if given.
typedef SpecFor = Future<SessionSpec> Function(String? cwd);

/// Something in a session worth telling the user about.
/// "Claude Code changed 4 files": shown over the tab, opens the changes.
class ReviewHint {
  const ReviewHint(this.title, this.folder);
  final String title;

  /// Repository root (guest path).
  final String folder;
}

sealed class SessionSignal {
  const SessionSignal();
}

/// A command finished (from shell integration prompt marks).
class CommandSignal extends SessionSignal {
  const CommandSignal(this.command);
  final CommandDone command;
}

/// The program asked for a notification (OSC 9 / OSC 777).
class NotifySignal extends SessionSignal {
  const NotifySignal(this.notification);
  final ShellNotification notification;
}

/// The terminal bell (many programs ring it when they need attention).
class BellSignal extends SessionSignal {
  const BellSignal();
}

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
  TerminalSession({
    required this.id,
    required this._title,
    this._customTitle = false,
    this._pinned = false,
    this.restoredScrollback,
    this.savedPtyId,
    this.project,
    this.agent,
    this.launch = const [],
    List<String> startupCommands = const [],
    PtyBackend? backend,
  })  : _backend = backend ?? PtyHost.instance,
        _startup = startupCommands {
    terminal.onOutput = _onInput;
    terminal.onResize = (cols, rows, _, _) => _onResize(rows, cols);
    terminal.onTitleChange = _onShellTitle;
    terminal.onPrivateOSC = _onOsc;
    terminal.onBell = () => onSignal?.call(const BellSignal());
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

  /// Changes worth reviewing (an agent in this tab edited files).
  final review = ValueNotifier<ReviewHint?>(null);

  /// Android killed a process here (exit 137: signal 9), usually the
  /// background limits keep-alive lifts. Cleared by the next command.
  final killed = ValueNotifier(false);

  /// The project folder (guest path) this tab was opened for, if any.
  final String? project;

  /// The agent (catalog id) this tab runs, if any.
  final String? agent;

  /// What the tab was opened to run (e.g. the agent). Runs again whenever
  /// the tab gets a fresh shell: after a restart, or when the app comes
  /// back and the old shell is gone.
  final List<String> launch;

  /// Called when the tab's title or pin changes (the tab strip listens).
  VoidCallback? onMetaChanged;

  /// Receives finished commands, notifications and bells.
  void Function(SessionSignal signal)? onSignal;

  /// The shell's current folder (guest path), from shell integration.
  String? cwd;

  /// Output from before the app restarted, shown above the new shell.
  final String? restoredScrollback;
  bool _restoredShown = false;

  /// Something worth saving changed (folder, output).
  VoidCallback? onPersistable;

  /// Local ports the output says a server is listening on.
  void Function(Set<int> ports)? onPortsMentioned;

  final _commands = CommandTracker();

  /// A command is running (shell integration saw Enter but no prompt yet).
  bool get busy => _commands.busy;

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

  final PtyBackend _backend;

  /// Typed into the shell once, when it first starts (e.g. an agent).
  List<String> _startup;
  PtySession? _pty;

  /// The PTY this tab had when it was saved; reattached if still running.
  final int? savedPtyId;

  /// The running shell's PTY id, saved so a restarted UI can reattach.
  int? get ptyId => _pty?.id;
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
  Future<void> start(SpecFor spec, {required bool alpine}) async {
    if (state.value == SessionState.starting || state.value == SessionState.running) return;
    _alpine = alpine;
    error = null;
    fix.value = null;
    _setState(SessionState.starting);
    showRestoredScrollback();
    try {
      final s = await spec(cwd);
      final pty = await _backend.start(
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
      _connect(pty);
      for (final command in _startup) {
        pty.write('$command\r');
      }
      _startup = const [];
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

  void _connect(PtySession pty) {
    _pty = pty;
    // Streaming decode: a character split across two reads must not
    // become replacement glyphs.
    _output = pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((text) {
      terminal.write(text);
      _watchForErrors(text);
      if (onPortsMentioned != null && text.contains(':')) {
        final ports = portsMentionedIn(text);
        if (ports.isNotEmpty) onPortsMentioned!(ports);
      }
    });
    pty.exitCode.then((code) {
      if (_disposed || _pty != pty) return;
      if (code == _sigkill) killed.value = true;
      terminal.write('\r\n[process exited: $code]\r\n');
      _pty = null;
      _setState(SessionState.exited);
    });
  }

  /// Reconnects to a shell that kept running while the UI was gone,
  /// redrawing the terminal from its recent output.
  void attach(PtyAttachment a) {
    if (_disposed) return;
    terminal.write(utf8.decode(a.replay, allowMalformed: true));
    _connect(a.session);
    a.session.resize(terminal.viewHeight, terminal.viewWidth);
    _setState(SessionState.running);
  }

  Future<void> restart(SpecFor spec, {required bool alpine}) async {
    _stopShell();
    _startup = launch;
    killed.value = false;
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
      _commands.onEnter();
      // A new command started: earlier errors no longer apply.
      _recent.clear();
      fix.value = null;
      killed.value = false;
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

  void _onOsc(String code, List<String> args) {
    switch (parseOsc(code, args)) {
      case CwdChanged(:final path):
        if (path != cwd) {
          cwd = path;
          onPersistable?.call();
        }
      case ShellNotification n:
        onSignal?.call(NotifySignal(n));
      case final ShellEvent e:
        if (_commands.onEvent(e) case final done?) {
          if (done.exitCode == _sigkill) killed.value = true;
          onSignal?.call(CommandSignal(done));
        }
      case null:
    }
  }

  /// The main screen's text, oldest first, at most [maxLines] lines. A
  /// full-screen app on the alternate screen (vim, a TUI) isn't included.
  String scrollbackText({int maxLines = 2000}) {
    final lines = terminal.mainBuffer.lines;
    final out = <String>[];
    for (var y = 0; y < lines.length; y++) {
      final line = lines[y];
      final text = line.getText().trimRight();
      if (line.isWrapped && out.isNotEmpty) {
        out[out.length - 1] += text;
      } else {
        out.add(text);
      }
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out.skip(out.length > maxLines ? out.length - maxLines : 0).join('\n');
  }

  /// Writes [restoredScrollback] into the terminal, once, with a marker.
  void showRestoredScrollback() {
    final text = restoredScrollback;
    if (text == null || _restoredShown) return;
    _restoredShown = true;
    terminal.write('${text.split('\n').join('\r\n')}\r\n\x1b[2m── restored from your last session ──\x1b[0m\r\n');
  }

  /// The last non-blank line of output, as plain text.
  String? lastOutputLine() {
    final lines = terminal.buffer.lines;
    for (var y = lines.length - 1; y >= 0; y--) {
      final text = lines[y].getText().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
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

  /// [stopShell] is false when only the UI is going away: the shell keeps
  /// running in the background service for the next UI to reattach.
  void dispose({bool stopShell = true}) {
    _disposed = true;
    _resizeTimer?.cancel();
    _fixTimer?.cancel();
    if (stopShell) {
      _stopShell();
    } else {
      _output?.cancel();
    }
    selection.dispose();
    modifiers.dispose();
    state.dispose();
    fix.dispose();
    review.dispose();
    killed.dispose();
  }

  /// 128 + SIGKILL, as shells and the PTY report a killed process.
  static const _sigkill = 137;
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
