import 'package:flutter/material.dart';
import '../app_theme.dart';

/// A compact row of keys a phone keyboard doesn't have, same idea as
/// Termux's "extra keys" row. Each entry sends raw bytes to the session.
class ExtraKeysBar extends StatelessWidget {
  final AppColors colors;
  final void Function(String data) onKey;

  const ExtraKeysBar({super.key, required this.colors, required this.onKey});

  static const _keys = <(String, String)>[
    ('ESC', '\x1b'),
    ('TAB', '\t'),
    ('CTRL+C', '\x03'),
    ('/', '/'),
    ('-', '-'),
    ('|', '|'),
    ('~', '~'),
    ('↑', '\x1b[A'),
    ('↓', '\x1b[B'),
    ('←', '\x1b[D'),
    ('→', '\x1b[C'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: colors.surfaceAlt,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: _keys.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final (label, data) = _keys[i];
          return _KeyButton(label: label, colors: colors, onTap: () => onKey(data));
        },
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final AppColors colors;
  final VoidCallback onTap;

  const _KeyButton({required this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
