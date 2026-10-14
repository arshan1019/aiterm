import 'package:flutter/material.dart';
import '../shared/form.dart';
import '../app/theme.dart';
import 'file_system_service.dart';
import '../app/icons.dart';

/// A plain text editor for one file. Asks before discarding unsaved edits.
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({super.key, required this.entry, required this.fs});

  final FsEntry entry;
  final FileSystemService fs;

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  final _text = TextEditingController();
  final _dirty = ValueNotifier(false);
  bool _loading = true;
  String _saved = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(() => _dirty.value = _text.text != _saved);
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _dirty.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _saved = await widget.fs.readText(widget.entry.path);
    } catch (_) {
      _saved = '';
    }
    _text.text = _saved;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final text = _text.text;
    await widget.fs.writeText(widget.entry.path, text);
    _saved = text;
    _dirty.value = false;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmAction(context,
        title: 'Discard changes?', message: 'Your edits to this file will be lost.', action: 'Discard', danger: true);
    if (discard && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder(
      valueListenable: _dirty,
      builder: (context, dirty, body) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
            actions: [
              AnimatedSwitcher(
                duration: Motion.quick,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: dirty
                    ? IconButton(
                        key: const ValueKey('save'),
                        tooltip: 'Save',
                        icon: Icon(AppIcons.check, color: c.accent),
                        onPressed: _save,
                      )
                    : const SizedBox(key: ValueKey('none'), width: 48),
              ),
            ],
          ),
          body: body,
        ),
      ),
      child: AnimatedSwitcher(
        duration: Motion.standard,
        child: _loading
            ? const SizedBox.expand(key: ValueKey('loading'))
            : Padding(
                key: const ValueKey('text'),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(color: c.text, fontSize: 13, height: 1.45),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
      ),
    );
  }
}
