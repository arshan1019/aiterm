import 'package:flutter/material.dart';
import '../app/theme.dart';

/// One destination of a [BottomTabs] bar.
class BottomTab {
  const BottomTab(this.label, this.icon, {this.badge, this.badgeColor});

  final String label;

  /// Outlined; filled while selected.
  final IconData icon;

  /// A count ("3") or a dot (""), shown on the icon; null for none.
  final String? badge;

  /// The badge's color; the accent when null.
  final Color? badgeColor;
}

/// Navigation at the bottom, in thumb reach (Material navigation bar,
/// Apple tab bar, Samsung One UI's interaction area): icons with labels.
/// Hidden while the keyboard is open, so it never takes rows from typing.
class BottomTabs extends StatelessWidget {
  const BottomTabs({super.key, required this.tabs, required this.selected, required this.onSelect});

  final List<BottomTab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border, width: 0.5))),
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: onSelect,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: Motion.standard,
        destinations: [
          for (final (i, t) in tabs.indexed)
            NavigationDestination(
              icon: _withBadge(_FillIcon(t.icon, filled: i == selected), t.badge, t.badgeColor ?? c.accent, c),
              label: t.label,
            ),
        ],
      ),
    );
  }

  static Widget _withBadge(Widget child, String? badge, Color color, AppColors c) {
    if (badge == null) return child;
    return Badge(
      backgroundColor: color,
      textColor: c.bg,
      smallSize: 8,
      label: badge.isEmpty ? null : Text(badge),
      isLabelVisible: true,
      child: child,
    );
  }
}

/// An icon whose fill animates in when it becomes selected.
class _FillIcon extends StatelessWidget {
  const _FillIcon(this.icon, {required this.filled});

  final IconData icon;
  final bool filled;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: filled ? 1 : 0),
        duration: Motion.standard,
        curve: Motion.move,
        builder: (context, fill, _) => Icon(icon, fill: fill),
      );
}
