import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../assistant/ask_sheet.dart';
import '../shared/fade_indexed_stack.dart';
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
      builder: (_) => AskSheet(
        alpine: !_services.linux.usesAndroidShell,
        onInsert: session.insert,
        onAppAction: _services.perform,
      ),
    );
  }

  void _tabMenu(TerminalSession session) {
    final tabs = _services.tabs;
    final hasOthers = tabs.tabs.any((t) => t != session && !t.pinned);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final c = sheet.colors;
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
              leading: Icon(icon, size: 20, color: color ?? c.textMuted),
              title: Text(label, style: TextStyle(color: color ?? c.text, fontSize: 14)),
              onTap: () {
                Navigator.pop(sheet);
                onTap();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(session.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, session.pinned ? 'Unpin' : 'Pin',
                  () => tabs.togglePin(session)),
              item(Icons.drive_file_rename_outline_rounded, 'Rename', () => _rename(session)),
              if (hasOthers) item(Icons.tab_unselected_rounded, 'Close other tabs', () => tabs.closeOthers(session)),
              if (!session.pinned) item(Icons.close_rounded, 'Close', () => tabs.close(session), color: c.danger),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rename(TerminalSession session) async {
    final controller = TextEditingController(text: session.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Rename tab', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(dialog, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) session.rename(name);
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
                child: FadeIndexedStack(
                  index: tabs.activeIndex,
                  duration: Motion.quick,
                  children: [
                    for (final s in tabs.tabs)
                      TerminalPane(key: ValueKey(s.id), session: s, visible: showing && s.id == active.id),
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
