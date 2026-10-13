import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../app_theme.dart';
import '../core/app_controller.dart';
import '../core/distro_manager.dart';
import '../core/error_fixes.dart';
import '../core/pty_channel.dart';
import '../core/shell_env.dart';
import '../core/tool_call.dart';
import '../widgets/ask_sheet.dart';
import '../widgets/extra_keys_bar.dart';

enum _Phase { loading, setup, running, exited }

class TerminalScreen extends StatefulWidget {
  final AppColors colors;
  const TerminalScreen({super.key, required this.colors});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _distro = DistroManager.instance;
  final _app = AppController.instance;
  final _terminal = Terminal(maxLines: 10000);
  PtySession? _session;
  StreamSubscription<String>? _outputSub;

  _Phase _phase = _Phase.loading;
  bool _useAndroidShell = false;
  String? _status;
  double? _progress;
  String? _error;

  // Sticky modifiers from the key bar; they apply to the next key only.
  bool _ctrl = false;
  bool _alt = false;
  bool _applyingModifier = false;

  // The keyboard animates the view height frame by frame. Telling the shell
  // about every intermediate size makes it redraw its prompt dozens of times
  // (the "cursor jumps"), so only the settled size is sent.
  Timer? _resizeTimer;

  // Output since the user last pressed Enter, scanned for known errors.
  final _recent = StringBuffer();
  Timer? _fixTimer;
  ErrorFix? _fix;
  ErrorFix? _dismissed;

  // Rebuilt only when their inputs change, so unrelated setState calls don't
  // hand TerminalView new objects and force a repaint.
  TerminalTheme? _theme;
  AppColors? _themeColors;
  TerminalStyle _style = const TerminalStyle();
  double? _styleSize;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _onUserInput;
    _terminal.onResize = (w, h, _, _) {
      _resizeTimer?.cancel();
      _resizeTimer = Timer(const Duration(milliseconds: 120), () => _session?.resize(h, w));
    };
    _app.addListener(_onAppChanged);
    _boot();
  }

  void _onUserInput(String data) {
    if (!_applyingModifier && (_ctrl || _alt) && data.runes.length == 1) {
      final ctrl = _ctrl, alt = _alt;
      setState(() => _ctrl = _alt = false);
      _applyingModifier = true;
      final handled = _terminal.charInput(data.toLowerCase().codeUnitAt(0), ctrl: ctrl, alt: alt);
      _applyingModifier = false;
      if (handled) return;
    }
    _session?.write(data);
    if (data.contains('\r')) {
      // A new command started: earlier errors no longer apply.
      _recent.clear();
      if (_fix != null) setState(() => _fix = null);
    }
  }

  void _onExtraKey(ExtraKey k) {
    void key(TerminalKey t) {
      final ctrl = _ctrl, alt = _alt;
      if (ctrl || alt) setState(() => _ctrl = _alt = false);
      _terminal.keyInput(t, ctrl: ctrl, alt: alt);
    }

    switch (k) {
      case ExtraKey.ask:
        _openAsk();
      case ExtraKey.ctrl:
        setState(() => _ctrl = !_ctrl);
      case ExtraKey.alt:
        setState(() => _alt = !_alt);
      case ExtraKey.esc:
        key(TerminalKey.escape);
      case ExtraKey.tab:
        key(TerminalKey.tab);
      case ExtraKey.up:
        key(TerminalKey.arrowUp);
      case ExtraKey.down:
        key(TerminalKey.arrowDown);
      case ExtraKey.left:
        key(TerminalKey.arrowLeft);
      case ExtraKey.right:
        key(TerminalKey.arrowRight);
      case ExtraKey.slash:
        _terminal.textInput('/');
      case ExtraKey.dash:
        _terminal.textInput('-');
      case ExtraKey.pipe:
        _terminal.textInput('|');
    }
  }

  void _onAppChanged() {
    if (mounted && _app.fontSize != _styleSize) setState(() {});
  }

  Future<void> _boot() async {
    try {
      await _distro.init();
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (_distro.installed) {
      await _start();
    } else {
      setState(() => _phase = _Phase.setup);
    }
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _status = 'Starting';
      _progress = null;
    });
    try {
      await _distro.install((status, progress) {
        if (mounted) {
          setState(() {
            _status = status;
            _progress = progress;
          });
        }
      });
      await _start();
    } catch (e) {
      setState(() {
        _status = null;
        _error = '$e';
      });
    }
  }

  Future<void> _start() async {
    await _outputSub?.cancel();
    await _session?.dispose();
    final session = PtySession();
    _session = session;
    try {
      final spec = _useAndroidShell ? await ShellEnv.androidShell() : await _distro.sessionSpec();
      await session.start(
        argv: spec.argv,
        env: spec.env,
        cwd: spec.cwd,
        rows: _terminal.viewHeight,
        cols: _terminal.viewWidth,
      );
      // Streaming decode: a multi-byte character split across two reads
      // must not turn into replacement glyphs.
      _outputSub = session.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((text) {
        _terminal.write(text);
        _watchForErrors(text);
      });
      session.onExit.listen((code) {
        _terminal.write('\r\n[process exited: $code]\r\n');
        if (mounted) setState(() => _phase = _Phase.exited);
      });
      setState(() {
        _phase = _Phase.running;
        _fix = null;
      });
    } catch (e) {
      setState(() {
        _phase = _distro.installed || _useAndroidShell ? _Phase.exited : _Phase.setup;
        _error = '$e';
      });
    }
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
    // Wait for output to settle so we judge the whole error, not a fragment.
    _fixTimer = Timer(const Duration(milliseconds: 500), () {
      final fix = detectFix(_recent.toString(), alpine: !_useAndroidShell);
      if (mounted && fix != _fix && fix != _dismissed) setState(() => _fix = fix);
    });
  }

  void _performAppAction(ToolCall a) {
    switch (a.tool) {
      case 'set_font_size':
        _app.changeFontSize(a.args['change'] == 'smaller' ? -1 : 1);
      case 'set_theme':
        _app.setDark(a.args['theme'] != 'light');
      case 'open_tab':
        _app.openTab(switch (a.args['tab']) {
          'files' => AppController.tabFiles,
          'settings' => AppController.tabSettings,
          _ => AppController.tabTerminal,
        });
      case 'show_in_files':
        _app.showInFiles(a.args['path'] ?? '~');
      case 'restart_shell':
        _error = null;
        _start();
    }
  }

  void _openAsk() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => AskSheet(
        colors: widget.colors,
        alpine: !_useAndroidShell,
        onInsert: (cmd) => _session?.write(cmd),
        onAppAction: _performAppAction,
      ),
    );
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    _fixTimer?.cancel();
    _outputSub?.cancel();
    _app.removeListener(_onAppChanged);
    _session?.dispose();
    super.dispose();
  }

  TerminalTheme _themeFor(AppColors c) {
    if (_theme == null || !identical(_themeColors, c)) {
      _themeColors = c;
      _theme = _buildTheme(c);
    }
    return _theme!;
  }

  TerminalStyle _styleFor(double size) {
    if (_styleSize != size) {
      _styleSize = size;
      _style = TerminalStyle(fontFamily: 'JetBrainsMono', fontSize: size, height: 1.25);
    }
    return _style;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.colors;
    switch (_phase) {
      case _Phase.loading:
        return Center(child: CircularProgressIndicator(color: c.accent, strokeWidth: 2));
      case _Phase.setup:
        return _SetupView(
          colors: c,
          status: _status,
          progress: _progress,
          error: _error,
          onInstall: _status == null ? _install : null,
          onSkip: _status == null
              ? () {
                  _useAndroidShell = true;
                  _start();
                }
              : null,
        );
      case _Phase.running:
      case _Phase.exited:
        return ColoredBox(
          color: c.bg,
          child: Column(
            children: [
              Expanded(
                // Notices float over the top of the terminal instead of taking
                // rows from it: changing the terminal's height reflows every
                // line and resizes the shell.
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                        child: TerminalView(
                          _terminal,
                          autofocus: true,
                          backgroundOpacity: 0,
                          theme: _themeFor(c),
                          textStyle: _styleFor(_app.fontSize),
                          // No suggestions or autocorrect: predictive keyboards
                          // rewrite composed text and move the cursor.
                          keyboardType: TextInputType.visiblePassword,
                          deleteDetection: true,
                          cursorType: TerminalCursorType.block,
                        ),
                      ),
                    ),
                    if (_phase == _Phase.exited)
                      _Notice(
                        colors: c,
                        icon: Icons.power_settings_new,
                        title: _error ?? 'Session ended',
                        isError: _error != null,
                        action: 'Restart',
                        onAction: () {
                          _error = null;
                          _start();
                        },
                      )
                    else if (_fix case final fix?)
                      _Notice(
                        colors: c,
                        icon: Icons.lightbulb_outline,
                        title: fix.problem,
                        detail: fix.needsInput ? '${fix.command}…' : fix.command,
                        action: 'Insert',
                        onAction: () {
                          _session?.write(fix.command);
                          setState(() => _fix = null);
                        },
                        onDismiss: () => setState(() {
                          _dismissed = fix;
                          _fix = null;
                        }),
                      ),
                  ],
                ),
              ),
              ExtraKeysBar(
                colors: c,
                onKey: _onExtraKey,
                ctrl: _ctrl,
                alt: _alt,
                askEnabled: _phase == _Phase.running,
              ),
            ],
          ),
        );
    }
  }

  TerminalTheme _buildTheme(AppColors c) => TerminalTheme(
        cursor: c.accent,
        selection: c.accent.withValues(alpha: 0.35),
        foreground: c.text,
        background: c.bg,
        black: c.bg,
        red: const Color(0xFFE2685A),
        green: const Color(0xFF6FBF73),
        yellow: const Color(0xFFD9B35C),
        blue: const Color(0xFF6C9EE5),
        magenta: const Color(0xFFB07CD1),
        cyan: const Color(0xFF5EC4A8),
        white: c.text,
        brightBlack: c.textMuted,
        brightRed: const Color(0xFFE2685A),
        brightGreen: const Color(0xFF6FBF73),
        brightYellow: const Color(0xFFD9B35C),
        brightBlue: const Color(0xFF6C9EE5),
        brightMagenta: const Color(0xFFB07CD1),
        brightCyan: const Color(0xFF5EC4A8),
        brightWhite: c.text,
        searchHitBackground: c.accent,
        searchHitBackgroundCurrent: c.accent,
        searchHitForeground: c.bg,
      );
}

/// A one-line notice pinned to the top of the terminal.
class _Notice extends StatelessWidget {
  final AppColors colors;
  final IconData icon;
  final String title;
  final String? detail;
  final bool isError;
  final String action;
  final VoidCallback onAction;
  final VoidCallback? onDismiss;

  const _Notice({
    required this.colors,
    required this.icon,
    required this.title,
    this.detail,
    this.isError = false,
    required this.action,
    required this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Positioned(
      left: 8,
      right: 8,
      top: 8,
      child: Material(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isError ? c.danger : c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isError ? c.danger : c.text, fontSize: 12)),
                    if (detail != null)
                      Text(detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(onPressed: onAction, child: Text(action, style: TextStyle(color: c.accent))),
              if (onDismiss != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 16, color: c.textMuted),
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupView extends StatelessWidget {
  final AppColors colors;
  final String? status;
  final double? progress;
  final String? error;
  final VoidCallback? onInstall;
  final VoidCallback? onSkip;

  const _SetupView({
    required this.colors,
    required this.status,
    required this.progress,
    required this.error,
    required this.onInstall,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set up Linux',
                  style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Downloads Alpine Linux (~4 MB) and runs it with proot. '
                'You get apk, so you can install node, git, python, and tools '
                'like Claude Code.',
                style: TextStyle(color: c.textMuted, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (status != null) ...[
                Text(status!, style: TextStyle(color: c.text, fontSize: 13)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  color: c.accent,
                  backgroundColor: c.surfaceAlt,
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.bg,
                    ),
                    onPressed: onInstall,
                    child: const Text('Install Alpine'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: onSkip,
                    child: Text('Use Android shell instead',
                        style: TextStyle(color: c.textMuted)),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: c.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
