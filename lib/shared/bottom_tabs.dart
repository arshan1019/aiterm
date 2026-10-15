import 'package:flutter/material.dart';
import '../app/icons.dart';
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
        builder: (context, fill, _) => icon == AppIcons.terminal ? _TerminalGlyph(fill: fill) : Icon(icon, fill: fill),
      );
}

/// Material Symbols' terminal glyph has no filled form, unlike the other
/// tabs' icons; drawn from its own outline (24dp grid), the frame fills in
/// and `>_` takes the selection pill's color as [fill] goes to 1.
class _TerminalGlyph extends StatelessWidget {
  const _TerminalGlyph({required this.fill});
  final double fill;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 24;
    final color = icon.color ?? context.colors.text;
    final cutout = Theme.of(context).navigationBarTheme.indicatorColor ?? context.colors.accentContainer;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _TerminalPainter(fill: fill, color: color, cutout: cutout)),
    );
  }
}

class _TerminalPainter extends CustomPainter {
  _TerminalPainter({required this.fill, required this.color, required this.cutout});
  final double fill;
  final Color color, cutout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()..isAntiAlias = true;
    final outer = RRect.fromLTRBR(2, 4, 22, 20, const Radius.circular(2));
    const inner = Rect.fromLTRB(4, 8, 20, 18);
    // The frame and title bar.
    paint.color = color;
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRRect(outer), Path()..addRect(inner)), paint);
    // The screen fills left to right, as Material Symbols' fill axis
    // sweeps the other tabs' icons.
    final filled = Rect.fromLTRB(inner.left, inner.top, inner.left + inner.width * fill, inner.bottom);
    if (fill > 0) canvas.drawRect(filled, paint);
    // ">_": ink, and cut out (the pill's color) where the fill has reached.
    final prompt = Path()
      ..moveTo(7.5, 17)
      ..lineTo(6.1, 15.6)
      ..lineTo(8.675, 13)
      ..lineTo(6.075, 10.4)
      ..lineTo(7.5, 9)
      ..lineTo(11.5, 13)
      ..close()
      ..addRect(const Rect.fromLTRB(12, 15, 18, 17));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(filled.right, 0, 24, 24));
    canvas.drawPath(prompt, paint..color = color);
    canvas.restore();
    if (fill > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, filled.right, 24));
      canvas.drawPath(prompt, paint..color = cutout);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TerminalPainter old) => old.fill != fill || old.color != color || old.cutout != cutout;
}
