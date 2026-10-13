import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Keys a phone keyboard lacks. Two rows of equal-width keys so the bar
/// lines up on every screen width.
enum ExtraKey { ask, esc, slash, dash, pipe, up, tab, ctrl, alt, left, down, right }

class ExtraKeysBar extends StatelessWidget {
  static const rowHeight = 36.0;

  final AppColors colors;
  final void Function(ExtraKey key) onKey;
  final bool ctrl;
  final bool alt;
  final bool askEnabled;

  const ExtraKeysBar({
    super.key,
    required this.colors,
    required this.onKey,
    this.ctrl = false,
    this.alt = false,
    this.askEnabled = true,
  });

  static const _rows = [
    [ExtraKey.ask, ExtraKey.esc, ExtraKey.slash, ExtraKey.dash, ExtraKey.pipe, ExtraKey.up],
    [ExtraKey.tab, ExtraKey.ctrl, ExtraKey.alt, ExtraKey.left, ExtraKey.down, ExtraKey.right],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            SizedBox(
              height: rowHeight,
              child: Row(children: [for (final k in row) Expanded(child: _key(k))]),
            ),
        ],
      ),
    );
  }

  Widget _key(ExtraKey k) {
    final active = (k == ExtraKey.ctrl && ctrl) || (k == ExtraKey.alt && alt);
    final enabled = k != ExtraKey.ask || askEnabled;
    final fg = !enabled
        ? colors.border
        : active
            ? colors.bg
            : k == ExtraKey.ask
                ? colors.accent
                : colors.text;
    final icon = switch (k) {
      ExtraKey.up => Icons.keyboard_arrow_up,
      ExtraKey.down => Icons.keyboard_arrow_down,
      ExtraKey.left => Icons.keyboard_arrow_left,
      ExtraKey.right => Icons.keyboard_arrow_right,
      _ => null,
    };
    final label = switch (k) {
      ExtraKey.ask => '✦',
      ExtraKey.esc => 'ESC',
      ExtraKey.slash => '/',
      ExtraKey.dash => '-',
      ExtraKey.pipe => '|',
      ExtraKey.tab => 'TAB',
      ExtraKey.ctrl => 'CTRL',
      ExtraKey.alt => 'ALT',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: active ? colors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? () => onKey(k) : null,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 20, color: fg)
                : Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: k == ExtraKey.ask ? 16 : 12,
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
