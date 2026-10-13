import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// A one-line card pinned to the top of the terminal: a suggested fix, or
/// "session ended". It floats over the terminal instead of taking rows
/// from it, because changing the terminal's height reflows every line.
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.isError = false,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final bool isError;
  final String action;
  final VoidCallback onAction;

  /// A second, lesser action ("Keep alive" next to "Restart").
  final String? secondary;
  final VoidCallback? onSecondary;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 6,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isError ? c.danger : c.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isError ? c.danger : c.text, fontSize: 12)),
                  if (detail != null)
                    Text(detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (secondary != null)
              TextButton(onPressed: onSecondary, child: Text(secondary!, style: TextStyle(color: c.textMuted))),
            TextButton(onPressed: onAction, child: Text(action)),
            if (onDismiss != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 16, color: c.textMuted),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}

/// Slides notices down from the top edge and back up as they change.
class NoticeSlot extends StatelessWidget {
  const NoticeSlot({super.key, required this.child});

  /// The notice to show, keyed so a different notice animates; or null.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.standard,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child ?? const SizedBox.shrink(key: ValueKey('none')),
    );
  }
}
