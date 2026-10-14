import 'package:flutter/material.dart';
import '../app/theme.dart';

/// A group of related rows: a sentence-case header above, the rows on one
/// tone step up from the background. No border: grouping comes from space
/// and tone (docs/DESIGN.md, "structure by space, then tone, then line").
class Group extends StatelessWidget {
  const Group({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title!, style: text.titleSmall?.copyWith(color: c.textMuted)),
          ),
        // A Material so the rows' ink shows on it.
        Material(
          color: c.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(Radii.large),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}
