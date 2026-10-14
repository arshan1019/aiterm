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
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) =>
          AppSheet(title: title, leading: leading, inset: inset, closable: dismissible, child: builder(sheet)),
    );

/// Every bottom sheet's frame, so they all look and behave alike: the drag
/// handle (from the theme), a title 12 dp below it with a visible Close
/// (the handle alone is easy to miss), content on the same 20 dp side
/// insets (list rows too), scrolling when tall, above the keyboard, at most
/// 85% of the screen and 640 dp wide. Back closes it too.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, this.title, this.leading, this.inset = true, this.closable = true, required this.child});

  static const sideInset = 20.0;

  final String? title;

  /// Before the title (GitHub's mark on its sign-in).
  final Widget? leading;

  /// Pads [child] at the sides; false for full-width rows (lists), which
  /// get the same inset inside them.
  final bool inset;

  /// Shows Close; false when the sheet has its own way out (Cancel).
  final bool closable;
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
                  padding: EdgeInsets.fromLTRB(sideInset, closable ? 0 : 12, closable ? 8 : sideInset, closable ? 0 : 12),
                  child: Row(
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: 12)],
                      Expanded(
                        child: Text(title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.text)),
                      ),
                      if (closable)
                        IconButton(
                          tooltip: 'Close',
                          icon: Icon(Icons.close_rounded, color: c.textMuted),
                          onPressed: () => Navigator.maybePop(context),
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
