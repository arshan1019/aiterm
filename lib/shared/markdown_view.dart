import 'package:flutter/material.dart';
import '../app/theme.dart';

/// A block of Markdown, as agents write it.
sealed class MdBlock {
  const MdBlock();
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level;
  final String text;
}

/// A list item; [marker] is "•" or "1.".
class MdItem extends MdBlock {
  const MdItem(this.marker, this.text, this.indent);
  final String marker;
  final String text;
  final int indent;
}

class MdCode extends MdBlock {
  const MdCode(this.code, this.language);
  final String code;
  final String? language;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);
  final String text;
}

final _item = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _fence = RegExp(r'^\s*(```|~~~)\s*([\w+-]*)');

final _parsed = <String, List<MdBlock>>{};

/// [parseMarkdown], remembered for the last few sources: a streaming chat
/// rebuilds every frame, but only the reply being written changes.
List<MdBlock> parsedMarkdown(String source) {
  final hit = _parsed.remove(source);
  if (hit != null) return _parsed[source] = hit;
  if (_parsed.length >= 64) _parsed.remove(_parsed.keys.first);
  return _parsed[source] = parseMarkdown(source);
}

/// Splits Markdown into blocks: fenced code, headings, list items, quotes
/// and paragraphs. An unclosed fence (still streaming) runs to the end.
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isNotEmpty) blocks.add(MdParagraph(para.join(' ')));
    para.clear();
  }

  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flush();
      final code = <String>[];
      final close = fence.group(1)!;
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith(close)) {
        code.add(lines[i]);
        i++;
      }
      final language = fence.group(2)!;
      blocks.add(MdCode(code.join('\n'), language.isEmpty ? null : language));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
    } else if (_heading.firstMatch(line) case final h?) {
      flush();
      blocks.add(MdHeading(h.group(1)!.length, h.group(2)!.trim()));
    } else if (_item.firstMatch(line) case final m?) {
      flush();
      final marker = m.group(2)!;
      blocks.add(MdItem(RegExp(r'\d').hasMatch(marker) ? marker : '•', m.group(3)!, m.group(1)!.length ~/ 2));
    } else if (line.trimLeft().startsWith('>')) {
      flush();
      blocks.add(MdQuote(line.trimLeft().substring(1).trim()));
    } else if (blocks.isNotEmpty && blocks.last is MdItem && para.isEmpty && line.startsWith('  ')) {
      final last = blocks.removeLast() as MdItem;
      blocks.add(MdItem(last.marker, '${last.text} ${line.trim()}', last.indent));
    } else {
      para.add(line.trim());
    }
  }
  flush();
  return blocks;
}

final _inline = RegExp(r'`([^`]+)`|\*\*(.+?)\*\*|__(.+?)__|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])');

/// Inline Markdown as spans: `code` in mono, **bold**, *italic*.
List<InlineSpan> markdownSpans(String text, AppColors c, {TextStyle? base}) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: codeStyle(c.text, size: (base?.fontSize ?? 15) - 1).copyWith(backgroundColor: c.surfaceAlt)));
    } else if (m.group(2) != null || m.group(3) != null) {
      spans.add(TextSpan(text: m.group(2) ?? m.group(3), style: const TextStyle(fontWeight: FontWeight.w600)));
    } else {
      spans.add(TextSpan(text: m.group(4), style: const TextStyle(fontStyle: FontStyle.italic)));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// Markdown from an agent: prose in the sans, code in mono (the rule:
/// mono means machine text).
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.source, {super.key, this.color});

  final String source;

  /// Text color (muted for thinking); the theme's text when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context).textTheme;
    final body = theme.bodyLarge!.copyWith(color: color ?? c.text);
    Widget rich(String text, TextStyle style) => Text.rich(TextSpan(style: style, children: markdownSpans(text, c, base: style)));
    final blocks = parsedMarkdown(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, b) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : (b is MdItem && blocks[i - 1] is MdItem ? 4 : 10)),
            child: switch (b) {
              MdParagraph(:final text) => rich(text, body),
              MdHeading(:final level, :final text) =>
                rich(text, (level <= 2 ? theme.titleMedium : theme.titleSmall)!.copyWith(color: color ?? c.text)),
              MdItem(:final marker, :final text, :final indent) => Padding(
                  padding: EdgeInsets.only(left: 16.0 * indent),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: marker == '•' ? 18 : 26, child: Text(marker, style: body.copyWith(color: c.textMuted))),
                      Expanded(child: rich(text, body)),
                    ],
                  ),
                ),
              MdQuote(:final text) => Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border, width: 3))),
                  child: rich(text, body.copyWith(color: c.textMuted)),
                ),
              MdCode(:final code) => CodeBox(code),
            },
          ),
      ],
    );
  }
}

/// Code or command output: mono on a tone step, scrolling sideways rather
/// than wrapping.
class CodeBox extends StatelessWidget {
  const CodeBox(this.code, {super.key, this.maxLines});

  final String code;

  /// Lines shown before the rest is cut (null: all).
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var text = code;
    if (maxLines != null) {
      final lines = code.split('\n');
      if (lines.length > maxLines!) text = lines.take(maxLines!).join('\n');
    }
    return Container(
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.medium)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: codeStyle(c.text, size: 12.5)),
      ),
    );
  }
}
