import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import 'commands.dart';
import 'needle.dart';
import 'tool_call.dart';

/// "What do you want to do?", typed or spoken. Commands are typed into the
/// shell without pressing Enter so the user reviews them; app actions
/// (theme, font size, tabs) run on tap.
class AskSheet extends StatefulWidget {
  const AskSheet({super.key, required this.alpine, required this.onInsert, required this.onAppAction});

  final bool alpine;
  final ValueChanged<String> onInsert;
  final ValueChanged<ToolCall> onAppAction;

  @override
  State<AskSheet> createState() => _AskSheetState();
}

enum _Mic { idle, recording, transcribing }

class _AskSheetState extends State<AskSheet> {
  late final _assistant = context.services.assistant;
  Needle get _needle => _assistant.needle;
  final _input = TextEditingController();

  bool _thinking = false;
  bool _needsModel = false;
  _Mic _mic = _Mic.idle;
  ModelFile? _downloading;
  double? _progress;
  List<Suggestion>? _results;
  String? _error;

  @override
  void dispose() {
    if (_mic == _Mic.recording) _needle.cancelRecording();
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _thinking = true;
      _error = null;
      _needsModel = false;
    });
    try {
      final r = await _assistant.suggest(text, alpine: widget.alpine);
      if (!mounted) return;
      setState(() {
        _results = r ?? const [];
        _needsModel = r == null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<void> _download(ModelFile model, {VoidCallback? then}) async {
    setState(() {
      _downloading = model;
      _progress = null;
      _error = null;
    });
    try {
      await _needle.download(model, (p) {
        if (mounted) setState(() => _progress = p);
      });
      then?.call();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _toggleMic() async {
    if (_mic == _Mic.transcribing || _downloading != null) return;
    if (!await _needle.isDownloaded(Needle.voiceModel)) {
      await _download(Needle.voiceModel);
      if (!await _needle.isDownloaded(Needle.voiceModel)) return;
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
        if (!mounted) return;
        setState(() => _mic = _Mic.idle);
        if (text.isEmpty) {
          setState(() => _error = "Didn't catch that. Try again.");
          return;
        }
        _input.text = text;
        await _ask();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mic = _Mic.idle;
          _error = '$e';
        });
      }
    }
  }

  void _choose(Suggestion s) {
    if (s.appAction case final action?) {
      widget.onAppAction(action);
    } else {
      widget.onInsert(s.command!);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Title, insets and the lift above the keyboard come from AppSheet.
    return AnimatedSize(
            duration: Motion.standard,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _field(c)),
                    const SizedBox(width: 8),
                    _micButton(c),
                  ],
                ),
                if (_downloading case final m?) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Downloading the ${m == Needle.voiceModel ? 'voice' : 'assistant'} model (${m.sizeMb} MB, one time)…',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: _progress, minHeight: 3),
                  ),
                ],
                if (_mic == _Mic.recording) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Listening… tap the mic again when you're done.",
                    style: TextStyle(color: c.accent, fontSize: 12),
                  ),
                ],
                if (_results case final results?) ...[
                  const SizedBox(height: 12),
                  if (results.isNotEmpty)
                    for (final s in results) _tile(c, s)
                  else if (_needsModel)
                    _modelPrompt(c)
                  else
                    Text('No matching action. Try saying it differently.', style: TextStyle(color: c.textMuted)),
                ],
                if (_error case final e?) ...[
                  const SizedBox(height: 8),
                  Text(e, style: TextStyle(color: c.danger, fontSize: 12)),
                ],
              ],
            ),
          );
  }

  Widget _field(AppColors c) => TextField(
    controller: _input,
    autofocus: true,
    textInputAction: TextInputAction.go,
    onSubmitted: (_) => _ask(),
    decoration: InputDecoration(
      hintText: 'e.g. install node, make a folder called app',
      suffixIcon: AnimatedSwitcher(
        duration: Motion.quick,
        child: _thinking
            ? const Padding(
                key: ValueKey('busy'),
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                key: const ValueKey('send'),
                icon: Icon(Icons.arrow_upward_rounded, color: c.accent),
                onPressed: _ask,
              ),
      ),
    ),
  );

  Widget _micButton(AppColors c) {
    final recording = _mic == _Mic.recording;
    return AnimatedContainer(
      duration: Motion.quick,
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: recording ? c.danger : c.surfaceAlt, shape: BoxShape.circle),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggleMic,
          child: AnimatedSwitcher(
            duration: Motion.quick,
            child: _mic == _Mic.transcribing
                ? const Padding(
                    key: ValueKey('busy'),
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    recording ? Icons.stop_rounded : Icons.mic_none_rounded,
                    key: ValueKey(recording),
                    color: recording ? c.bg : c.accent,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _modelPrompt(AppColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'That needs the assistant model, a one-time ${Needle.textModel.sizeMb} MB download '
        'that runs offline on your phone.',
        style: TextStyle(color: c.textMuted, height: 1.4),
      ),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _downloading == null ? () => _download(Needle.textModel, then: _ask) : null,
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
        : s.source == SuggestionSource.rules
        ? 'Exact match'
        : 'Suggested. Check it before pressing Enter';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surfaceAlt,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        child: ListTile(
          title: Text(isApp || !s.needsInput ? s.label : '${s.label}…', style: TextStyle(color: c.text, fontSize: 13)),
          subtitle: Text(hint, style: TextStyle(color: c.textMuted, fontSize: 12)),
          trailing: TextButton(onPressed: () => _choose(s), child: Text(isApp ? 'Do it' : 'Insert')),
          onTap: () => _choose(s),
        ),
      ),
    );
  }
}
