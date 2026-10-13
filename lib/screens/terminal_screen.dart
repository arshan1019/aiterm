import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../app_theme.dart';
import '../core/app_controller.dart';
import '../core/distro_manager.dart';
import '../core/error_fixes.dart';
import '../core/key_mapping.dart';
import '../core/pty_channel.dart';
import '../core/shell_env.dart';
import '../core/tool_call.dart';
import '../widgets/ask_sheet.dart';
import '../widgets/extra_keys_bar.dart';

enum _Phase { loading, setup, ready }

class _TabInfo {
  final int id;
  String title;
  bool customTitle;
  bool pinned;
  _TabInfo(this.id, this.title, {this.customTitle = false, this.pinned = false});
}

/// Terminal tabs, each with its own shell. Pinned tabs sit first, can't be
/// closed by accident, and are reopened when the app starts.
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
  _Phase _phase = _Phase.loading;
  bool _useAndroidShell = false;
  String? _status;
  double? _progress;
  String? _error;

  final _tabs = <_TabInfo>[];
  int _activeId = 0;
  int _nextId = 1;
  final _stripScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _stripScroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _distro.init();
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (_distro.installed) {
      await _openSaved();
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
      await _openSaved();
    } catch (e) {
      setState(() {
        _status = null;
        _error = '$e';
      });
    }
  }

  File get _savedFile => File('${_distro.filesDir}/terminal_tabs.json');

  Future<void> _openSaved() async {
    try {
      final saved = jsonDecode(await _savedFile.readAsString()) as List;
      for (final t in saved.cast<Map<String, dynamic>>()) {
        _tabs.add(_TabInfo(_nextId++, t['title'] as String, customTitle: t['custom'] == true, pinned: true));
      }
    } catch (_) {
      // First run, or an unreadable file: start with one plain tab.
    }
    if (_tabs.isEmpty) _tabs.add(_TabInfo(_nextId++, 'shell'));
    setState(() {
      _activeId = _tabs.first.id;
      _phase = _Phase.ready;
    });
  }

  Future<void> _savePinned() async {
    try {
      await _savedFile.writeAsString(
        jsonEncode([
          for (final t in _tabs.where((t) => t.pinned)) {'title': t.title, 'custom': t.customTitle},
        ]),
      );
    } catch (_) {}
  }

  String _freshTitle() {
    final used = _tabs.map((t) => t.title).toSet();
    if (!used.contains('shell')) return 'shell';
    var n = 2;
    while (used.contains('shell $n')) {
      n++;
    }
    return 'shell $n';
  }

  void _newTab() {
    final tab = _TabInfo(_nextId++, _freshTitle());
    setState(() {
      _tabs.add(tab);
      _activeId = tab.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stripScroll.hasClients) {
        _stripScroll.animateTo(
          _stripScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _close(_TabInfo tab) {
    final i = _tabs.indexOf(tab);
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) _tabs.add(_TabInfo(_nextId++, _freshTitle()));
      if (tab.id == _activeId) _activeId = _tabs[i.clamp(0, _tabs.length - 1)].id;
    });
    if (tab.pinned) _savePinned();
  }

  void _togglePin(_TabInfo tab) {
    setState(() {
      tab.pinned = !tab.pinned;
      // Keep pinned tabs grouped at the front, in the order they were pinned.
      _tabs.remove(tab);
      final pinnedCount = _tabs.where((t) => t.pinned).length;
      _tabs.insert(pinnedCount, tab);
    });
    _savePinned();
  }

  Future<void> _rename(_TabInfo tab) async {
    final c = widget.colors;
    final controller = TextEditingController(text: tab.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Rename tab', style: TextStyle(color: c.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: c.text),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      tab.title = name;
      tab.customTitle = true;
    });
    if (tab.pinned) _savePinned();
  }

  void _onShellTitle(_TabInfo tab, String title) {
    final t = title.trim();
    if (tab.customTitle || t.isEmpty || t == tab.title || !mounted) return;
    setState(() => tab.title = t.length > 24 ? '${t.substring(0, 24)}…' : t);
  }

  void _tabMenu(_TabInfo tab) {
    final c = widget.colors;
    final others = _tabs.where((t) => t != tab && !t.pinned).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: color ?? c.textMuted),
          title: Text(label, style: TextStyle(color: color ?? c.text)),
          onTap: () {
            Navigator.pop(ctx);
            onTap();
          },
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              item(
                tab.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                tab.pinned ? 'Unpin' : 'Pin',
                () => _togglePin(tab),
              ),
              item(Icons.drive_file_rename_outline, 'Rename', () => _rename(tab)),
              if (others.isNotEmpty)
                item(Icons.tab_unselected, 'Close other tabs', () {
                  for (final t in others) {
                    _close(t);
                  }
                }),
              if (!tab.pinned) item(Icons.close, 'Close', () => _close(tab), color: c.danger),
            ],
          ),
        );
      },
    );
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
                  _openSaved();
                }
              : null,
        );
      case _Phase.ready:
        final active = _tabs.indexWhere((t) => t.id == _activeId);
        return ColoredBox(
          color: c.bg,
          child: Column(
            children: [
              _TabStrip(
                colors: c,
                tabs: _tabs,
                activeId: _activeId,
                scroll: _stripScroll,
                onSelect: (t) => setState(() => _activeId = t.id),
                onClose: _close,
                onMenu: _tabMenu,
                onNew: _newTab,
              ),
              Expanded(
                child: IndexedStack(
                  index: active < 0 ? 0 : active,
                  children: [
                    for (final t in _tabs)
                      TerminalPane(
                        key: ValueKey(t.id),
                        colors: c,
                        active: t.id == _activeId,
                        useAndroidShell: _useAndroidShell,
                        onTitle: (title) => _onShellTitle(t, title),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _TabStrip extends StatelessWidget {
  final AppColors colors;
  final List<_TabInfo> tabs;
  final int activeId;
  final ScrollController scroll;
  final ValueChanged<_TabInfo> onSelect;
  final ValueChanged<_TabInfo> onClose;
  final ValueChanged<_TabInfo> onMenu;
  final VoidCallback onNew;

  const _TabStrip({
    required this.colors,
    required this.tabs,
    required this.activeId,
    required this.scroll,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(6, 5, 0, 5),
              itemCount: tabs.length,
              itemBuilder: (context, i) {
                final t = tabs[i];
                final active = t.id == activeId;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Material(
                    color: active ? c.surface : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                      side: BorderSide(color: active ? c.border : Colors.transparent, width: 0.5),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: active ? () => onMenu(t) : () => onSelect(t),
                      onLongPress: () => onMenu(t),
                      child: Padding(
                        padding: EdgeInsets.only(left: 10, right: active && !t.pinned ? 2 : 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (t.pinned) ...[
                              Icon(Icons.push_pin, size: 12, color: active ? c.accent : c.textMuted),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              t.title,
                              style: TextStyle(
                                color: active ? c.text : c.textMuted,
                                fontSize: 12,
                                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            if (active && !t.pinned)
                              InkResponse(
                                radius: 12,
                                onTap: () => onClose(t),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(Icons.close, size: 13, color: c.textMuted),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 40,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              tooltip: 'New tab',
              onPressed: onNew,
              icon: Icon(Icons.add, color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PaneState { starting, running, exited }

/// One shell session: terminal, PTY, key bar, error fixes and assistant.
class TerminalPane extends StatefulWidget {
  final AppColors colors;
  final bool active;
  final bool useAndroidShell;
  final ValueChanged<String> onTitle;

  const TerminalPane({
    super.key,
    required this.colors,
    required this.active,
    required this.useAndroidShell,
    required this.onTitle,
  });

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _distro = DistroManager.instance;
  final _app = AppController.instance;
  final _terminal = _Terminal();
  PtySession? _session;
  StreamSubscription<String>? _outputSub;

  final _focus = FocusNode();
  _PaneState _phase = _PaneState.starting;
  String? _error;
  bool get _useAndroidShell => widget.useAndroidShell;

  // Sticky modifiers from the key bar; they apply to the next key only.
  bool _ctrl = false;
  bool _alt = false;
  bool _applyingModifier = false;

  // Volume Down held = Ctrl, as in Termux.
  bool _volumeCtrl = false;

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
    _terminal.onTitleChange = widget.onTitle;
    _app.addListener(_onAppChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _start();
  }

  @override
  void didUpdateWidget(TerminalPane old) {
    super.didUpdateWidget(old);
    // Hidden tabs stay alive in an IndexedStack; hand the keyboard over.
    if (widget.active && !old.active) _focus.requestFocus();
  }

  bool _onHardwareKey(KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.audioVolumeDown) return false;
    // Only while this tab's terminal is on screen; elsewhere it's volume.
    if (!mounted || !widget.active || _app.tab != AppController.tabTerminal) {
      _volumeCtrl = false;
      return false;
    }
    if (e is KeyDownEvent) _volumeCtrl = true;
    if (e is KeyUpEvent) _volumeCtrl = false;
    return true;
  }

  void _onUserInput(String data) {
    final ctrl = _ctrl || _volumeCtrl, alt = _alt;
    if (!_applyingModifier && (ctrl || alt) && data.runes.length == 1) {
      if (_ctrl || _alt) setState(() => _ctrl = _alt = false);
      _applyingModifier = true;
      final handled = _terminal.charInput(data.runes.first, ctrl: ctrl, alt: alt);
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
      final ctrl = _ctrl || _volumeCtrl, alt = _alt;
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
      _outputSub = session.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((text) {
        _terminal.write(text);
        _watchForErrors(text);
      });
      session.onExit.listen((code) {
        _terminal.write('\r\n[process exited: $code]\r\n');
        if (mounted) setState(() => _phase = _PaneState.exited);
      });
      if (!mounted) return;
      setState(() {
        _phase = _PaneState.running;
        _fix = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PaneState.exited;
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
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _session?.dispose();
    _focus.dispose();
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
    final c = widget.colors;
    if (_phase == _PaneState.starting) {
      return Center(child: CircularProgressIndicator(color: c.accent, strokeWidth: 2));
    }
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
                      focusNode: _focus,
                      autofocus: widget.active,
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
                if (_phase == _PaneState.exited)
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
          ExtraKeysBar(colors: c, onKey: _onExtraKey, ctrl: _ctrl, alt: _alt, askEnabled: _phase == _PaneState.running),
        ],
      ),
    );
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

/// xterm's own mapping misses Ctrl+Space and friends and sends Alt+b as
/// ESC B; use the Termux rules for both the key bar and hardware keyboards.
class _Terminal extends Terminal {
  _Terminal() : super(maxLines: 10000);

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) {
    if (!ctrl && !alt) return false;
    final out = modifiedChar(charCode, ctrl: ctrl, alt: alt);
    if (out == null) return false;
    onOutput?.call(out);
    return true;
  }
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
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isError ? c.danger : c.text, fontSize: 12),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onAction,
                child: Text(action, style: TextStyle(color: c.accent)),
              ),
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
              Text(
                'Set up Linux',
                style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
              ),
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
                LinearProgressIndicator(value: progress, color: c.accent, backgroundColor: c.surfaceAlt),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.bg),
                    onPressed: onInstall,
                    child: const Text('Install Alpine'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: onSkip,
                    child: Text('Use Android shell instead', style: TextStyle(color: c.textMuted)),
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
