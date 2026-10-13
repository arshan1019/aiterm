import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../assistant/ask_sheet.dart';
import '../preview/preview_controller.dart';
import '../preview/preview_screen.dart';
import '../shared/action_sheet.dart';
import '../shared/fade_indexed_stack.dart';
import '../shared/name_dialog.dart';
import 'terminal_session.dart';
import 'widgets/extra_keys_bar.dart';
import 'widgets/setup_view.dart';
import 'widgets/tab_strip.dart';
import 'widgets/terminal_pane.dart';

/// The Terminal tab: first-run setup, then the tabbed terminals.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final linux = context.services.linux;
    return ListenableBuilder(
      listenable: linux,
      builder: (context, _) => AnimatedSwitcher(
        duration: Motion.standard,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        child: linux.installed || linux.usesAndroidShell
            ? const _Workspace(key: ValueKey('workspace'))
            : const SetupView(key: ValueKey('setup')),
      ),
    );
  }
}

class _Workspace extends StatefulWidget {
  const _Workspace({super.key});

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
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

  /// Volume Down held = Ctrl (as in Termux), only while a terminal shows.
  bool _onHardwareKey(KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.audioVolumeDown) return false;
    final modifiers = _services.tabs.active.modifiers;
    if (_services.navigation.tab != AppTab.terminal) {
      modifiers.volumeCtrl = false;
      return false;
    }
    if (e is KeyDownEvent) modifiers.volumeCtrl = true;
    if (e is KeyUpEvent) modifiers.volumeCtrl = false;
    return true;
  }

  void _openAsk(TerminalSession session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          AskSheet(alpine: !_services.linux.usesAndroidShell, onInsert: session.insert, onAppAction: _services.perform),
    );
  }

  void _tabMenu(TerminalSession session) {
    final tabs = _services.tabs;
    final hasOthers = tabs.tabs.any((t) => t != session && !t.pinned);
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
    final nav = _services.navigation;
    return ColoredBox(
      color: context.colors.bg,
      child: ListenableBuilder(
        listenable: Listenable.merge([tabs, nav]),
        builder: (context, _) {
          final active = tabs.active;
          final showing = nav.tab == AppTab.terminal;
          return Column(
            children: [
              TabStrip(tabs: tabs, onMenu: _tabMenu),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FadeIndexedStack(
                        index: tabs.activeIndex,
                        duration: Motion.quick,
                        children: [
                          for (final s in tabs.tabs)
                            TerminalPane(key: ValueKey(s.id), session: s, visible: showing && s.id == active.id),
                        ],
                      ),
                    ),
                    Positioned(left: 8, right: 8, bottom: 8, child: _PortAnnouncement(preview: _services.preview)),
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
  const _PortAnnouncement({required this.preview});

  final PreviewController preview;

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
                            Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => PreviewScreen(port: port)));
                          },
                          child: const Text('Preview'),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
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
