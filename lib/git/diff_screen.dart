import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'git_actions.dart';
import 'git_parsers.dart';
import 'git_repo.dart';

/// One file's changes, unified, with old/new line numbers. Stage or
/// unstage it from here.
class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key, required this.repo, required this.change, required this.staged});

  final GitRepo repo;
  final GitChange change;
  final bool staged;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late final Future<FileDiff> _diff = widget.repo.diff(widget.change.path, staged: widget.staged);

  Future<void> _toggle() async {
    final repo = widget.repo, path = widget.change.path;
    final ok = await runGit(context, () => widget.staged ? repo.unstage([path]) : repo.stage([path]), repo: repo);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final path = widget.change.path;
    final slash = path.lastIndexOf('/');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(path.substring(slash + 1), overflow: TextOverflow.ellipsis),
            if (slash > 0)
              Text(path.substring(0, slash),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          TextButton(onPressed: _toggle, child: Text(widget.staged ? 'Unstage' : 'Stage')),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<FileDiff>(
        future: _diff,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}', style: TextStyle(color: c.danger)));
          }
          final d = snap.data;
          if (d == null) return const SizedBox.expand();
          if (d.binary) return _note(context, 'Binary file changed');
          if (d.hunks.isEmpty) return _note(context, 'No text changes (mode or rename only)');
          final rows = <Object>[for (final h in d.hunks) ...[h, ...h.lines]];
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '+${d.added}', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                  const TextSpan(text: '  '),
                  TextSpan(text: '−${d.removed}', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
                ]), style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: SelectionArea(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => switch (rows[i]) {
                      DiffHunk h => _HunkHeader(header: h.header),
                      DiffLine l => _Line(line: l),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _note(BuildContext context, String text) =>
      Center(child: Text(text, style: TextStyle(color: context.colors.textMuted, fontSize: 13)));
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.header});
  final String header;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      margin: const EdgeInsets.only(top: 8),
      child: Text(header, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textMuted, fontSize: 11)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});
  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color? bg, String sign, Color signColor) = switch (line.kind) {
      DiffLineKind.added => (c.accent.withValues(alpha: 0.12), '+', c.accent),
      DiffLineKind.removed => (c.danger.withValues(alpha: 0.12), '−', c.danger),
      DiffLineKind.context => (null, ' ', c.textMuted),
    };
    final gutter = TextStyle(color: c.textMuted.withValues(alpha: 0.7), fontSize: 10, height: 1.6);
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: Text('${line.oldLine ?? ''}', textAlign: TextAlign.right, style: gutter)),
          SizedBox(width: 30, child: Text('${line.newLine ?? ''}', textAlign: TextAlign.right, style: gutter)),
          SizedBox(
            width: 16,
            child: Text(sign, textAlign: TextAlign.center, style: TextStyle(color: signColor, fontSize: 12, height: 1.45)),
          ),
          Expanded(
            child: Text(line.text, style: TextStyle(color: c.text, fontSize: 12, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
