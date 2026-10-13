import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../assistant/error_fixes.dart';
import '../../platform/android_env.dart';
import '../../shared/settled_size.dart';
import '../terminal_session.dart';
import 'notice.dart';
import 'terminal_selection.dart';

/// Renders one [TerminalSession]: the terminal itself, link/selection
/// handling, and notices floating over its top edge.
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session, required this.visible});

  final TerminalSession session;

  /// This tab is selected and the Terminal screen is showing.
  final bool visible;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _viewKey = GlobalKey<TerminalViewState>();
  final _focus = FocusNode();

  // Rebuilt only when their inputs change, so unrelated rebuilds don't hand
  // TerminalView new objects and force a full repaint.
  TerminalTheme? _theme;
  AppColors? _themeColors;
  TerminalStyle? _style;
  double? _styleSize;

  TerminalSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    // Start once the view has laid out and the terminal knows its real
    // size, so the shell draws its first prompt at the right width.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didUpdateWidget(TerminalPane old) {
    super.didUpdateWidget(old);
    // Hidden tabs stay mounted; hand the keyboard to the one now showing.
    if (widget.visible && !old.visible) _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted || _session.state.value != SessionState.idle) return;
    final linux = context.services.linux;
    _session.start(linux.sessionSpec, alpine: !linux.usesAndroidShell);
  }

  void _restart() {
    final linux = context.services.linux;
    _session.restart(linux.sessionSpec, alpine: !linux.usesAndroidShell);
  }

  Future<void> _openUrl(String url) async {
    try {
      await AndroidEnv.openUrl(url);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Could not open the link')));
      }
    }
  }

  /// Keeps content where xterm's resize will leave it while the keyboard
  /// slides (see [keyboardOffset]).
  double _keyboardOffset(double settledHeight, double availableHeight) {
    final render = _viewKey.currentState?.renderTerminal;
    if (render == null) return 0;
    final buffer = _session.terminal.buffer;
    return keyboardOffset(
      settledHeight: settledHeight,
      availableHeight: availableHeight,
      lineHeight: render.lineHeight,
      cursorRow: buffer.cursorY,
      scrollbackLines: buffer.scrollBack,
    );
  }

  TerminalTheme _themeFor(AppColors c) {
    if (_theme == null || _themeColors != c) {
      _themeColors = c;
      _theme = _terminalTheme(c);
    }
    return _theme!;
  }

  TerminalStyle _styleFor(double size) {
    if (_style == null || _styleSize != size) {
      _styleSize = size;
      _style = TerminalStyle(fontFamily: 'JetBrainsMono', fontSize: size, height: 1.25);
    }
    return _style!;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.services.settings;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: SettledSize(
              offsetFor: _keyboardOffset,
              child: TerminalSelection(
                terminal: _session.terminal,
                controller: _session.selection,
                viewKey: _viewKey,
                visible: widget.visible,
                onPaste: _session.paste,
                onOpenUrl: _openUrl,
                child: ListenableBuilder(
                  listenable: settings,
                  builder: (context, _) => TerminalView(
                    _session.terminal,
                    key: _viewKey,
                    controller: _session.selection,
                    focusNode: _focus,
                    autofocus: widget.visible,
                    backgroundOpacity: 0,
                    theme: _themeFor(c),
                    textStyle: _styleFor(settings.fontSize),
                    // No suggestions or autocorrect: predictive keyboards
                    // rewrite composed text and move the cursor.
                    keyboardType: TextInputType.visiblePassword,
                    deleteDetection: true,
                    cursorType: TerminalCursorType.block,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: ListenableBuilder(
            listenable: Listenable.merge([_session.state, _session.fix]),
            builder: (context, _) => NoticeSlot(child: _notice()),
          ),
        ),
      ],
    );
  }

  Widget? _notice() {
    if (_session.state.value == SessionState.exited) {
      return Notice(
        key: const ValueKey('exited'),
        icon: Icons.power_settings_new_rounded,
        title: _session.error ?? 'Session ended',
        isError: _session.error != null,
        action: 'Restart',
        onAction: _restart,
      );
    }
    final ErrorFix? fix = _session.fix.value;
    if (fix == null) return null;
    return Notice(
      key: ValueKey(fix),
      icon: Icons.lightbulb_outline_rounded,
      title: fix.problem,
      detail: fix.needsInput ? '${fix.command}…' : fix.command,
      action: 'Insert',
      onAction: () {
        _session.insert(fix.command);
        _session.fix.value = null;
      },
      onDismiss: _session.dismissFix,
    );
  }
}

TerminalTheme _terminalTheme(AppColors c) => TerminalTheme(
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
