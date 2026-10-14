import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../assistant/ask_sheet.dart';
import '../git/git_screen.dart';
import '../preview/preview_controller.dart';
import '../preview/preview_screen.dart';
import '../shared/action_sheet.dart';
import '../shared/fade_indexed_stack.dart';
import '../shared/name_dialog.dart';
import '../shared/sheet.dart';
import 'terminal_session.dart';
import 'widgets/extra_keys_bar.dart';
import 'widgets/tab_strip.dart';
import 'widgets/terminal_pane.dart';

/// One scope's terminals: the Terminal tab's ([project] null) or a
/// project's, in its workspace. Tab strip, the selected tab's terminal,
/// and the key bar.
class TerminalDeck extends StatefulWidget {
  const TerminalDeck({
    super.key,
    this.project,
    required this.showing,
    required this.onNew,
    this.onReview,
    this.onPreview,
    this.onGitHere,
  });

  final String? project;

  /// This deck is on screen (its tab is selected and no page covers it).
  final bool showing;

  /// The strip's + button.
  final VoidCallback onNew;

  /// Where "Review changes", "Preview" and "Git changes here" go; by
  /// default a page over the current screen. A workspace uses its own tabs.
  final void Function(ReviewHint hint)? onReview;
  final ValueChanged<int>? onPreview;
  final ValueChanged<String>? onGitHere;

  @override
  State<TerminalDeck> createState() => _TerminalDeckState();
}

class _TerminalDeckState extends State<TerminalDeck> {
  late final _services = context.services;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  TerminalSession? get _active => _services.tabs.activeIn(widget.project);

  /// Volume Down held = Ctrl (as in Termux), only while this deck shows.
  bool _onHardwareKey(KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.audioVolumeDown) return false;
    final modifiers = _active?.modifiers;
    if (modifiers == null) return false;
    if (!widget.showing) {
      modifiers.volumeCtrl = false;
      return false;
    }
    if (e is KeyDownEvent) modifiers.volumeCtrl = true;
    if (e is KeyUpEvent) modifiers.volumeCtrl = false;
    return true;
  }

  void _openAsk(TerminalSession session) {
    showAppSheet<void>(
      context,
      title: 'What do you want to do?',
      builder: (_) =>
          AskSheet(alpine: !_services.linux.usesAndroidShell, onInsert: session.insert, onAppAction: _services.perform),
    );
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _review(ReviewHint hint) =>
      widget.onReview != null ? widget.onReview!(hint) : _push(GitScreen(folder: hint.folder));

  void _preview(int port) => widget.onPreview != null ? widget.onPreview!(port) : _push(PreviewScreen(port: port));

  void _gitHere(String cwd) => widget.onGitHere != null ? widget.onGitHere!(cwd) : _push(GitScreen(folder: cwd));

  void _tabMenu(TerminalSession session) {
    final tabs = _services.tabs;
    final hasOthers = tabs.inScope(widget.project).any((t) => t != session && !t.pinned);
    showActionSheet(
      context,
      title: session.title,
      actions: [
        SheetAction(
          session.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          session.pinned ? 'Unpin' : 'Pin',
          () => tabs.togglePin(session),
        ),
        SheetAction(Icons.drive_file_rename_outline_rounded, 'Rename', () => _rename(session)),
        if (session.cwd case final cwd? when !_services.linux.usesAndroidShell)
          SheetAction(Icons.call_split_rounded, 'Git changes here', () => _gitHere(cwd)),
        if (hasOthers) SheetAction(Icons.tab_unselected_rounded, 'Close other tabs', () => tabs.closeOthers(session)),
        if (!session.pinned) SheetAction(Icons.close_rounded, 'Close', () => tabs.close(session), danger: true),
      ],
    );
  }

  Future<void> _rename(TerminalSession session) async {
    final name = await showNameDialog(context, title: 'Rename tab', action: 'Rename', initial: session.title);
    if (name != null) session.rename(name);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _services.tabs;
    return ColoredBox(
      color: context.colors.bg,
      child: ListenableBuilder(
        listenable: tabs,
        builder: (context, _) {
          final scoped = tabs.inScope(widget.project);
          final active = tabs.activeIn(widget.project);
          if (active == null) return const SizedBox.expand();
          return Column(
            children: [
              TabStrip(tabs: tabs, scope: widget.project, onMenu: _tabMenu, onNew: widget.onNew),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FadeIndexedStack(
                        index: scoped.indexOf(active),
                        duration: Motion.quick,
                        children: [
                          for (final s in scoped)
                            TerminalPane(
                              key: ValueKey(s.id),
                              session: s,
                              visible: widget.showing && s.id == active.id,
                              onReview: _review,
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: _PortAnnouncement(preview: _services.preview, onPreview: _preview),
                    ),
                  ],
                ),
              ),
              ExtraKeysBar(key: ValueKey(active.id), session: active, onAsk: () => _openAsk(active)),
            ],
          );
        },
      ),
    );
  }
}

/// "localhost:5173 is live · Preview", sliding up when a dev server starts.
class _PortAnnouncement extends StatelessWidget {
  const _PortAnnouncement({required this.preview, required this.onPreview});

  final PreviewController preview;
  final ValueChanged<int> onPreview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: preview,
      builder: (context, _) {
        final port = preview.announced;
        return AnimatedSwitcher(
          duration: Motion.standard,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: port == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : Material(
                  key: ValueKey(port),
                  color: c.surface,
                  elevation: 6,
                  shadowColor: Colors.black38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: c.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_tethering_rounded, size: 16, color: c.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('localhost:$port is live', style: TextStyle(color: c.text, fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: () {
                            preview.dismiss();
                            onPreview(port);
                          },
                          child: const Text('Preview'),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: 16, color: c.textMuted),
                          onPressed: preview.dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
