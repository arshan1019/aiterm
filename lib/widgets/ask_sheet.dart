import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/tool_call.dart';
import '../core/needle_service.dart';

/// "What do you want to do?" — typed or spoken. Commands are typed into the
/// shell without pressing Enter so the user reviews them; app actions (theme,
/// font size, tabs) run on tap.
class AskSheet extends StatefulWidget {
  final AppColors colors;
  final bool alpine;
  final void Function(String command) onInsert;
  final void Function(ToolCall action) onAppAction;

  const AskSheet({
    super.key,
    required this.colors,
    required this.alpine,
    required this.onInsert,
    required this.onAppAction,
  });

  @override
  State<AskSheet> createState() => _AskSheetState();
}

enum _Mic { idle, recording, transcribing }

class _AskSheetState extends State<AskSheet> {
  final _needle = NeedleService.instance;
  final _input = TextEditingController();
  bool _thinking = false;
  bool _needsModel = false;
  _Mic _mic = _Mic.idle;
  String? _downloading; // model name while downloading
  double? _progress;
  List<Suggestion>? _results;
  String? _error;

  @override
  void dispose() {
    if (_mic == _Mic.recording) _needle.cancelRecording();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _thinking = true;
      _error = null;
      _results = null;
      _needsModel = false;
    });
    try {
      // Rules answer instantly; the model is only needed when they don't.
      final hasModel = await _needle.isDownloaded(NeedleService.textModel);
      final r = hasModel ? await _needle.suggest(text, alpine: widget.alpine) : await _rulesOnly(text);
      setState(() {
        _results = r;
        _needsModel = !hasModel && r.isEmpty;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<List<Suggestion>> _rulesOnly(String text) async {
    final rule = matchRules(text);
    if (rule == null) return const [];
    final s = _needle.fromCall(rule, alpine: widget.alpine, source: 'rules');
    return s == null ? const [] : [s];
  }

  Future<void> _download(ModelFile model, {VoidCallback? then}) async {
    setState(() {
      _downloading = model.name;
      _progress = null;
      _error = null;
    });
    try {
      await _needle.download(model, (p) {
        if (mounted) setState(() => _progress = p);
      });
      then?.call();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _toggleMic() async {
    if (_mic == _Mic.transcribing || _downloading != null) return;
    if (!await _needle.isDownloaded(NeedleService.voiceModel)) {
      await _download(NeedleService.voiceModel);
      if (!await _needle.isDownloaded(NeedleService.voiceModel)) return;
    }
    try {
      if (_mic == _Mic.idle) {
        await _needle.startRecording();
        setState(() {
          _mic = _Mic.recording;
          _error = null;
        });
      } else {
        setState(() => _mic = _Mic.transcribing);
        final text = await _needle.stopAndTranscribe();
        setState(() => _mic = _Mic.idle);
        if (text.isEmpty) {
          setState(() => _error = "Didn't catch that. Try again.");
          return;
        }
        _input.text = text;
        await _ask();
      }
    } catch (e) {
      setState(() {
        _mic = _Mic.idle;
        _error = '$e';
      });
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
              Row(
                children: [
                  Expanded(child: _textField(c)),
                  const SizedBox(width: 8),
                  _micButton(c),
                ],
              ),
              if (_downloading != null) ...[
                const SizedBox(height: 12),
                Text(
                  _downloading == NeedleService.voiceModel.name
                      ? 'Downloading the voice model (${NeedleService.voiceModel.sizeMb} MB, one time)…'
                      : 'Downloading the assistant model (${NeedleService.textModel.sizeMb} MB, one time)…',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress, color: c.accent, backgroundColor: c.surfaceAlt),
              ],
              if (_mic == _Mic.recording) ...[
                const SizedBox(height: 10),
                Text('Listening… tap the mic again when you\'re done.',
                    style: TextStyle(color: c.accent, fontSize: 12)),
              ],
              if (_results != null) ...[
                const SizedBox(height: 12),
                if (_results!.isNotEmpty)
                  for (final s in _results!) _tile(c, s)
                else if (_needsModel)
                  _modelPrompt(c)
                else
                  Text('No matching action. Try saying it differently.', style: TextStyle(color: c.textMuted)),
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

  Widget _textField(AppColors c) => TextField(
        controller: _input,
        autofocus: true,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _ask(),
        style: TextStyle(color: c.text),
        decoration: InputDecoration(
          hintText: 'e.g. install node, make a folder called app',
          hintStyle: TextStyle(color: c.textMuted),
          filled: true,
          fillColor: c.surfaceAlt,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          suffixIcon: _thinking
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                )
              : IconButton(icon: Icon(Icons.arrow_upward, color: c.accent), onPressed: _ask),
        ),
      );

  Widget _micButton(AppColors c) {
    final recording = _mic == _Mic.recording;
    return Material(
      color: recording ? c.danger : c.surfaceAlt,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _toggleMic,
        child: SizedBox(
          width: 48,
          height: 48,
          child: _mic == _Mic.transcribing
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                )
              : Icon(recording ? Icons.stop : Icons.mic_none, color: recording ? c.bg : c.accent),
        ),
      ),
    );
  }

  Widget _modelPrompt(AppColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'That needs the assistant model, a one-time ${NeedleService.textModel.sizeMb} MB download '
            'that runs offline on your phone.',
            style: TextStyle(color: c.textMuted, height: 1.4),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.bg),
            onPressed: _downloading == null ? () => _download(NeedleService.textModel, then: _ask) : null,
            child: const Text('Download and retry'),
          ),
        ],
      );

  Widget _tile(AppColors c, Suggestion s) {
    final isApp = s.appAction != null;
    final hint = isApp
        ? 'Changes the app'
        : s.needsInput
            ? 'Inserted without Enter. Finish it, e.g. type the name'
            : s.source == 'rules'
                ? 'Exact match'
                : 'Suggested. Check it before pressing Enter';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        title: Text(isApp ? s.label : (s.needsInput ? '${s.label}…' : s.label),
            style: TextStyle(color: c.text, fontFamily: isApp ? null : 'JetBrainsMono', fontSize: 13)),
        subtitle: Text(hint, style: TextStyle(color: c.textMuted, fontSize: 12)),
        trailing: TextButton(
          onPressed: () {
            if (isApp) {
              widget.onAppAction(s.appAction!);
            } else {
              widget.onInsert(s.command!);
            }
            Navigator.pop(context);
          },
          child: Text(isApp ? 'Do it' : 'Insert', style: TextStyle(color: c.accent)),
        ),
      ),
    );
  }
}
