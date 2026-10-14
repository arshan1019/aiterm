import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../platform/haptics.dart';
import '../terminal_session.dart';
import '../terminal_tabs.dart';
import '../../app/icons.dart';

/// The row of terminal tabs. Tap to switch; tap the active tab or
/// long-press any tab for pin / rename / close.
class TabStrip extends StatefulWidget {
  const TabStrip({super.key, required this.tabs, this.scope, required this.onMenu, required this.onNew});

  final TerminalTabs tabs;

  /// Whose tabs: a project's (its folder), or the Terminal tab's (null).
  final String? scope;
  final ValueChanged<TerminalSession> onMenu;
  final VoidCallback onNew;

  static const height = 44.0;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _scroll = ScrollController();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _count = widget.tabs.inScope(widget.scope).length;
    widget.tabs.addListener(_onTabs);
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_onTabs);
    _scroll.dispose();
    super.dispose();
  }

  void _onTabs() {
    final count = widget.tabs.inScope(widget.scope).length;
    if (count > _count) {
      // A tab was opened at the end: bring it into view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.standard, curve: Motion.move);
        }
      });
    }
    _count = count;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: TabStrip.height,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.tabs,
              builder: (context, _) {
                final tabs = widget.tabs.inScope(widget.scope);
                final activeId = widget.tabs.activeIn(widget.scope)?.id;
                return ListView.builder(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(6, 5, 0, 5),
                  itemCount: tabs.length,
                  itemBuilder: (context, i) => _Tab(
                    key: ValueKey(tabs[i].id),
                    session: tabs[i],
                    active: tabs[i].id == activeId,
                    onTap: () => tabs[i].id == activeId
                        ? widget.onMenu(tabs[i])
                        : widget.tabs.select(tabs[i]),
                    onLongPress: () {
                      Haptics.longPress();
                      widget.onMenu(tabs[i]);
                    },
                    onClose: () => widget.tabs.close(tabs[i]),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 42,
            child: IconButton(
              tooltip: 'New tab',
              iconSize: 20,
              onPressed: widget.onNew,
              icon: Icon(AppIcons.add, color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.session,
    required this.active,
    required this.onTap,
    required this.onLongPress,
    required this.onClose,
  });

  final TerminalSession session;
  final bool active;
  final VoidCallback onTap, onLongPress, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final closable = active && !session.pinned;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: Motion.standard,
          curve: Motion.enter,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: active ? c.surface : c.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? c.border : c.bg, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Working (accent) or waiting for you (amber); idle shows nothing.
              if (session.activity.value case SessionActivity.working || SessionActivity.needsInput) ...[
                Semantics(
                  label: session.activity.value == SessionActivity.working ? 'Working' : 'Needs input',
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: session.activity.value == SessionActivity.working ? c.accent : c.warning,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (session.pinned) ...[
                Icon(AppIcons.pushPin, fill: 1, size: 12, color: active ? c.accent : c.textMuted),
                const SizedBox(width: 4),
              ],
              AnimatedDefaultTextStyle(
                duration: Motion.standard,
                style: TextStyle(
                  color: active ? c.text : c.textMuted,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(session.title),
              ),
              // The close button slides out of the active tab.
              AnimatedSize(
                duration: Motion.standard,
                curve: Motion.move,
                child: closable
                    ? Semantics(
                        button: true,
                        label: 'Close ${session.title}',
                        onTap: onClose,
                        excludeSemantics: true,
                        child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                          child: Icon(AppIcons.close, size: 16, color: c.textMuted),
                        ),
                      ),
                      )
                    : const SizedBox(width: 6, height: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
