import 'package:flutter/material.dart';
import '../app/theme.dart';

/// One destination of a [BottomTabs] bar.
class BottomTab {
  const BottomTab(this.label, this.icon, this.selectedIcon, {this.badge});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// A count ("3") or a dot (""), shown on the icon; null for none.
  final String? badge;
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
          for (final t in tabs)
            NavigationDestination(
              icon: _withBadge(t.icon, t.badge, c),
              selectedIcon: _withBadge(t.selectedIcon, t.badge, c),
              label: t.label,
            ),
        ],
      ),
    );
  }

  static Widget _withBadge(IconData icon, String? badge, AppColors c) {
    final child = Icon(icon);
    if (badge == null) return child;
    return Badge(
      backgroundColor: c.accent,
      textColor: c.bg,
      smallSize: 8,
      label: badge.isEmpty ? null : Text(badge),
      isLabelVisible: true,
      child: child,
    );
  }
}
