import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../files/files_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/fade_indexed_stack.dart';
import '../terminal/terminal_screen.dart';
import 'navigation.dart';
import 'services.dart';
import 'theme.dart';

/// The top-level layout: a row of text tabs over the three screens. All
/// screens stay mounted, so terminals keep running and Files keeps its place.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _screens = [ProjectsScreen(), TerminalScreen(), FilesScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nav = context.services.navigation;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.surface,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !nav.handleBack()) SystemNavigator.pop();
        },
        child: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: nav,
              builder: (context, _) => Column(
                children: [
                  _TabRow(selected: nav.tab, onSelect: nav.open),
                  Expanded(
                    child: FadeIndexedStack(index: nav.tab.index, rise: 6, children: _screens),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text tabs with an accent underline that slides to the selected tab.
class _TabRow extends StatefulWidget {
  const _TabRow({required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  State<_TabRow> createState() => _TabRowState();
}

class _TabRowState extends State<_TabRow> {
  final _keys = {for (final t in AppTab.values) t: GlobalKey()};
  final _rowKey = GlobalKey();
  Rect? _indicator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_TabRow old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Underline under the label's text, measured after layout.
  void _measure() {
    final row = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final label = _keys[widget.selected]!.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || label == null || !mounted) return;
    final topLeft = label.localToGlobal(Offset.zero, ancestor: row);
    final rect = topLeft & label.size;
    if (rect != _indicator) setState(() => _indicator = rect);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final indicator = _indicator;
    return Container(
      height: 44,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Stack(
        key: _rowKey,
        children: [
          Row(
            children: [
              const SizedBox(width: 6),
              for (final t in AppTab.values)
                InkWell(
                  onTap: () => widget.onSelect(t),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: AnimatedDefaultTextStyle(
                      duration: Motion.standard,
                      curve: Motion.enter,
                      style: TextStyle(
                        color: t == widget.selected ? c.text : c.textMuted,
                        fontSize: 13,
                        fontWeight: t == widget.selected ? FontWeight.w600 : FontWeight.w400,
                        fontFamily: 'JetBrainsMono',
                      ),
                      child: Text(t.name, key: _keys[t]),
                    ),
                  ),
                ),
            ],
          ),
          if (indicator != null)
            AnimatedPositioned(
              duration: Motion.standard,
              curve: Motion.move,
              left: indicator.left,
              width: indicator.width,
              bottom: 0,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(1)),
              ),
            ),
        ],
      ),
    );
  }
}
