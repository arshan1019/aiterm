import 'package:flutter/material.dart';
import '../app/theme.dart';

/// GitHub's button: the official Invertocat (assets/github, from
/// brand.github.com) in black or white only, on the highest-contrast
/// surface for the theme, unmodified, as GitHub's logo guidelines ask.
class GitHubButton extends StatelessWidget {
  const GitHubButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? Colors.white : Colors.black;
    final fg = dark ? Colors.black : Colors.white;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: context.colors.surfaceAlt,
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: onPressed,
      icon: Image.asset(
        dark ? 'assets/github/GitHub_Invertocat_Black.png' : 'assets/github/GitHub_Invertocat_White.png',
        width: 20,
        height: 20,
        excludeFromSemantics: true,
      ),
      label: Text(label),
    );
  }
}
