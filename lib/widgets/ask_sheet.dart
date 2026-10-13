import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/needle_service.dart';

/// "What do you want to do?" — asks Needle, shows the commands it maps to,
/// and types the chosen one into the shell without pressing Enter, so the
/// user always reviews it before it runs.
class AskSheet extends StatefulWidget {
  final AppColors colors;
  final bool alpine;
  final void Function(String command) onInsert;

  const AskSheet({super.key, required this.colors, required this.alpine, required this.onInsert});

  @override
  State<AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<AskSheet> {
  final _needle = NeedleService.instance;
  final _input = TextEditingController();
  bool? _downloaded;
  double? _downloadProgress;
  bool _downloading = false;
  bool _thinking = false;
  List<Suggestion>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _needle.isDownloaded().then((v) => mounted ? setState(() => _downloaded = v) : null);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await _needle.download((p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
      setState(() => _downloaded = true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _ask() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _thinking = true;
      _error = null;
      _results = null;
    });
    try {
      final r = await _needle.suggest(text, alpine: widget.alpine);
      setState(() => _results = r);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What do you want to do?',
                  style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (_downloaded == null)
                Center(child: CircularProgressIndicator(color: c.accent))
              else if (_downloaded == false)
                _downloadPrompt(c)
              else ...[
                TextField(
                  controller: _input,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _ask(),
                  style: TextStyle(color: c.text),
                  decoration: InputDecoration(
                    hintText: 'e.g. install node, find big files',
                    hintStyle: TextStyle(color: c.textMuted),
                    filled: true,
                    fillColor: c.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _thinking
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                            ),
                          )
                        : IconButton(
                            icon: Icon(Icons.arrow_upward, color: c.accent),
                            onPressed: _ask,
                          ),
                  ),
                ),
                if (_results != null) ...[
                  const SizedBox(height: 12),
                  if (_results!.isEmpty)
                    Text('No matching action. Try saying it differently.',
                        style: TextStyle(color: c.textMuted))
                  else
                    for (final s in _results!) _suggestionTile(c, s),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: c.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadPrompt(AppColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggestions run on your phone with Needle, a small offline model. '
            'It needs a one-time ${NeedleService.modelSizeMb} MB download.',
            style: TextStyle(color: c.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_downloading)
            LinearProgressIndicator(
              value: _downloadProgress,
              color: c.accent,
              backgroundColor: c.surfaceAlt,
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.bg),
              onPressed: _download,
              child: const Text('Download model'),
            ),
        ],
      );

  Widget _suggestionTile(AppColors c, Suggestion s) {
    final unsure = s.confidence < 0.3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        title: Text(s.command,
            style: TextStyle(color: c.text, fontFamily: 'monospace', fontSize: 13)),
        subtitle: Text(
          unsure ? 'Not sure this is right — check before running' : s.action.replaceAll('_', ' '),
          style: TextStyle(color: unsure ? c.danger : c.textMuted, fontSize: 12),
        ),
        trailing: TextButton(
          onPressed: () {
            widget.onInsert(s.command);
            Navigator.pop(context);
          },
          child: Text('Insert', style: TextStyle(color: c.accent)),
        ),
      ),
    );
  }
}
