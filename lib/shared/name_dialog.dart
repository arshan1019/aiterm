import 'package:flutter/material.dart';
import 'form.dart';

/// Asks for a name (new file, rename…). Returns the trimmed name, or null
/// if cancelled or left empty.
///
/// The dialog owns its text controller and disposes it when the dialog
/// itself goes away: disposing it in the caller right after `showDialog`
/// returns breaks the text field while the dialog is still animating out.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? hint,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, action: action, initial: initial, hint: hint),
  );
  return name == null || name.isEmpty ? null : name;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, required this.initial, this.hint});

  final String title, action, initial;
  final String? hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: _stemLength(widget.initial));

  /// Preselect the name without its extension, as file managers do.
  static int _stemLength(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? dot : name.length;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _text.text.trim());

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      fields: [
        TextField(
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hint),
          onSubmitted: (_) => _submit(),
        ),
      ],
      action: widget.action,
      onAction: _submit,
    );
  }
}
