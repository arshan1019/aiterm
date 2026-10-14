import 'package:flutter/material.dart';
import '../app/theme.dart';

/// Shows [child] in the app's bottom sheet frame ([AppSheet]).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  String? title,
  Widget? leading,
  bool dismissible = true,
  bool inset = true,
  required Widget Function(BuildContext sheet) builder,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      builder: (sheet) => AppSheet(title: title, leading: leading, inset: inset, child: builder(sheet)),
    );

/// Every bottom sheet's frame, so they all look and behave alike: the drag
/// handle (from the theme), a title 12 dp below it, content on the same
/// 20 dp side insets (list rows too), scrolling when tall, above the
/// keyboard, at most 85% of the screen.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, this.title, this.leading, this.inset = true, required this.child});

  static const sideInset = 20.0;

  final String? title;

  /// Before the title (GitHub's mark on its sign-in).
  final Widget? leading;

  /// Pads [child] at the sides; false for full-width rows (lists), which
  /// get the same inset inside them.
  final bool inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(sideInset, 12, sideInset, 12),
                  child: Row(
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: 12)],
                      Expanded(
                        child: Text(title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),
              Flexible(
                child: ListTileTheme.merge(
                  contentPadding: const EdgeInsets.symmetric(horizontal: sideInset),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(inset ? sideInset : 0, 0, inset ? sideInset : 0, 16),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
