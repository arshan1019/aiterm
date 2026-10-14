import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../assistant/error_fixes.dart';
import '../../keep_alive/keep_alive.dart';
import '../../keep_alive/keep_alive_view.dart';
import '../../platform/android_env.dart';
import '../../shared/settled_size.dart';
import '../terminal_session.dart';
import 'notice.dart';
import 'terminal_selection.dart';
import '../../app/icons.dart';

/// Renders one [TerminalSession]: the terminal itself, link/selection
/// handling, and notices floating over its top edge.
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session, required this.visible, required this.onReview});

  final TerminalSession session;

  /// Opens the changes a [ReviewHint] points at.
  final void Function(ReviewHint hint) onReview;

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
    // Hidden tabs stay mounted. Hand the keyboard over only if it's already
    // open; switching tabs must never pop it up (tapping the terminal does).
    if (widget.visible && !old.visible && MediaQuery.viewInsetsOf(context).bottom > 0) {
      _focus.requestFocus();
    }
    if (widget.visible) WidgetsBinding.instance.addPostFrameCallback((_) => _session.seen());
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
      _theme = _terminalTheme(c, TerminalPalette.of(context));
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
                // Scrolling repaints only the terminal, not what's around it.
                child: RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: settings,
                    builder: (context, _) => TerminalView(
                      _session.terminal,
                      key: _viewKey,
                      controller: _session.selection,
                      focusNode: _focus,
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
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: ListenableBuilder(
            listenable: Listenable.merge([_session.state, _session.fix, _session.review, _session.killed, context.services.keepAlive]),
            builder: (context, _) => NoticeSlot(child: _notice()),
          ),
        ),
      ],
    );
  }

  /// Android killed something here and keep-alive isn't fully set up.
  bool get _killedByAndroid {
    final steps = context.services.keepAlive.steps;
    return _session.killed.value && steps.isNotEmpty && !allDone(steps);
  }

  Widget? _notice() {
    if (_session.state.value == SessionState.exited) {
      final killed = _killedByAndroid;
      return Notice(
        key: ValueKey('exited $killed'),
        icon: AppIcons.power,
        title: killed ? 'Android stopped this session' : _session.error ?? 'Session ended',
        isError: killed || _session.error != null,
        action: 'Restart',
        onAction: _restart,
        secondary: killed ? 'Keep alive' : null,
        onSecondary: () => showKeepAlive(context),
      );
    }
    if (_killedByAndroid) {
      return Notice(
        key: const ValueKey('killed'),
        icon: AppIcons.warning,
        title: 'Android stopped a process here (signal 9)',
        detail: 'Let aiterm keep agents running in the background',
        isError: true,
        action: 'Fix',
        onAction: () => showKeepAlive(context),
        onDismiss: () => _session.killed.value = false,
      );
    }
    final ErrorFix? fix = _session.fix.value;
    if (fix == null) return _review();
    return Notice(
      key: ValueKey(fix),
      icon: AppIcons.lightbulb,
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

  Widget? _review() {
    final hint = _session.review.value;
    if (hint == null) return null;
    return Notice(
      key: ValueKey(hint),
      icon: AppIcons.branch,
      title: hint.title,
      action: 'Review',
      onAction: () {
        _session.review.value = null;
        widget.onReview(hint);
      },
      onDismiss: () => _session.review.value = null,
    );
  }
}

TerminalTheme _terminalTheme(AppColors c, TerminalPalette t) => TerminalTheme(
  cursor: c.accent,
  selection: c.accent.withValues(alpha: 0.35),
  foreground: c.text,
  background: c.bg,
  black: c.bg,
  red: t.red,
  green: t.green,
  yellow: t.yellow,
  blue: t.blue,
  magenta: t.magenta,
  cyan: t.cyan,
  white: c.text,
  brightBlack: c.textMuted,
  brightRed: t.brightRed,
  brightGreen: t.brightGreen,
  brightYellow: t.brightYellow,
  brightBlue: t.brightBlue,
  brightMagenta: t.brightMagenta,
  brightCyan: t.brightCyan,
  brightWhite: c.text,
  searchHitBackground: c.accent,
  searchHitBackgroundCurrent: c.accent,
  searchHitForeground: c.bg,
);
