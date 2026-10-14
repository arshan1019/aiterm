import 'package:flutter/material.dart';
import '../app/theme.dart';

/// The label over a form field ("Name", "Folder"): sentence case.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.colors.textMuted)),
      );
}

/// A label above a full-width field: every form in the app lines up the
/// same way (no floating labels inside borderless filled boxes).
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [FieldLabel(label), child],
      );
}

/// The app's dialog: title, optional explanation, content, then Cancel and
/// one primary action on the right. Same paddings everywhere.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.fields = const [],
    required this.action,
    required this.onAction,
    this.danger = false,
    this.cancel = 'Cancel',
  });

  final String title;
  final String? message;
  final List<Widget> fields;
  final String action;

  /// Null disables the action (e.g. until the form is valid).
  final VoidCallback? onAction;
  final bool danger;
  final String cancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TextStyle(color: c.text, fontSize: 17, fontWeight: FontWeight.w600)),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.45)),
              ],
              for (final field in fields) ...[const SizedBox(height: 16), field],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(cancel, style: TextStyle(color: c.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: danger ? FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.bg) : null,
                    onPressed: onAction,
                    child: Text(action),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks to confirm [action]; true when confirmed.
Future<bool> confirmAction(BuildContext context,
        {required String title, required String message, required String action, bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AppDialog(
        title: title,
        message: message,
        action: action,
        danger: danger,
        onAction: () => Navigator.pop(d, true),
      ),
    ) ??
    false;
