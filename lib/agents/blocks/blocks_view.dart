import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/icons.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../platform/haptics.dart';
import '../../shared/action_sheet.dart';
import '../../shared/line_diff.dart';
import '../../shared/markdown_view.dart';
import '../../shared/sheet.dart';
import '../acp/agent_chat.dart';

/// An agent as blocks: each message, tool call and plan is its own block,
/// with the agent's permission requests pinned above the message box.
class BlocksView extends StatelessWidget {
  const BlocksView({
    super.key,
    required this.chats,
    required this.chat,
    required this.onSelect,
    required this.onNew,
    required this.onTerminal,
    required this.onClose,
  });

  /// The project's chats (a chip each when there are several).
  final List<AgentChat> chats;
  final AgentChat chat;
  final ValueChanged<AgentChat> onSelect;

  /// Another agent or a terminal in this project.
  final VoidCallback onNew;

  /// The agent's own UI in a terminal (and where sign-in happens).
  final ValueChanged<AgentChat> onTerminal;
  final ValueChanged<AgentChat> onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Column(
        children: [
          _ChatBar(chat: chat, chats: chats, onSelect: onSelect, onNew: onNew, onTerminal: onTerminal, onClose: onClose),
          Expanded(child: _body(context)),
          if (chat.permissions.firstOrNull case final request?) _PermissionCard(chat: chat, request: request),
          _Composer(key: ValueKey(chat), chat: chat),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    switch (chat.state) {
      case ChatState.preparing || ChatState.starting when chat.entries.isEmpty:
        return _Centered(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 16),
          Text(chat.state == ChatState.preparing ? 'Setting up ${chat.name}' : 'Starting ${chat.name}',
              style: Theme.of(context).textTheme.titleSmall),
          if (chat.detail case final d?) ...[
            const SizedBox(height: 8),
            Text(d, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: codeStyle(c.textMuted, size: 12)),
          ],
        ]);
      case ChatState.signedOut:
        return _Centered(children: [
          Icon(AppIcons.login, size: 32, color: c.textMuted),
          const SizedBox(height: 12),
          Text('Sign in to ${chat.name}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => onTerminal(chat), child: const Text('Sign in')),
          TextButton(onPressed: chat.start, child: const Text('Try again')),
        ]);
      case ChatState.failed when chat.entries.isEmpty:
        return _Centered(children: [
          Icon(AppIcons.error, fill: 1, size: 32, color: c.danger),
          const SizedBox(height: 12),
          Text('${chat.name} didn\'t start', style: Theme.of(context).textTheme.titleMedium),
          if (chat.detail case final d?) ...[
            const SizedBox(height: 8),
            Text(d, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: codeStyle(c.danger, size: 12)),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: chat.start, child: const Text('Try again')),
          TextButton(onPressed: () => onTerminal(chat), child: const Text('Open in terminal')),
        ]);
      default:
        return _Entries(chat: chat);
    }
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

/// The agent (or a chip per agent), its mode, and the chat's menu.
class _ChatBar extends StatelessWidget {
  const _ChatBar({
    required this.chat,
    required this.chats,
    required this.onSelect,
    required this.onNew,
    required this.onTerminal,
    required this.onClose,
  });

  final AgentChat chat;
  final List<AgentChat> chats;
  final ValueChanged<AgentChat> onSelect;
  final VoidCallback onNew;
  final ValueChanged<AgentChat> onTerminal;
  final ValueChanged<AgentChat> onClose;

  void _menu(BuildContext context) {
    showActionSheet(context, title: chat.name, actions: [
      for (final o in chat.options)
        if (o.id != 'mode') SheetAction(AppIcons.tune, '${o.name}: ${o.valueName}', () => _choose(context, chat, o)),
      SheetAction(AppIcons.add, 'New chat', chat.restart),
      SheetAction(AppIcons.terminal, 'Open in terminal', () => onTerminal(chat)),
      null,
      SheetAction(AppIcons.close, 'Close', () => onClose(chat)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = chat.options.where((o) => o.id == 'mode').firstOrNull;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            child: chats.length > 1
                ? ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final other in chats)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Center(
                            child: ChoiceChip(
                              label: Text(other.name),
                              selected: other == chat,
                              showCheckmark: false,
                              onSelected: (_) => onSelect(other),
                            ),
                          ),
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(chat.name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                  ),
          ),
          if (mode != null)
            TextButton.icon(
              onPressed: () => _choose(context, chat, mode),
              icon: const Icon(AppIcons.tune, size: 18),
              label: Text(mode.valueName),
            ),
          IconButton(tooltip: 'New', icon: const Icon(AppIcons.add), onPressed: onNew),
          IconButton(tooltip: 'Chat actions', icon: const Icon(AppIcons.moreVert), onPressed: () => _menu(context)),
        ],
      ),
    );
  }
}

/// Picks a mode or model from the agent's choices.
void _choose(BuildContext context, AgentChat chat, ChatOption option) {
  showAppSheet<void>(
    context,
    title: option.name,
    inset: false,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, name) in option.choices)
          ListTile(
            title: Text(name),
            trailing: value == option.value ? Icon(AppIcons.check, color: sheet.colors.accent) : null,
            onTap: () {
              Navigator.pop(sheet);
              Haptics.tick();
              chat.choose(option, value);
            },
          ),
      ],
    ),
  );
}

/// The conversation, newest at the bottom (and kept in view).
class _Entries extends StatelessWidget {
  const _Entries({required this.chat});
  final AgentChat chat;

  @override
  Widget build(BuildContext context) {
    final thinking = context.services.settings.showThinking;
    final shown = [for (final e in chat.entries) if (e is! ThoughtEntry || thinking) e];
    final working = chat.busy && chat.permissions.isEmpty;
    final items = [if (working) null, ...shown.reversed];
    if (items.isEmpty) {
      return Center(child: Icon(AppIcons.agent, size: 40, color: context.colors.border));
    }
    return SelectionArea(
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final e = items[i];
          return Padding(
            key: e == null ? const ValueKey('working') : ValueKey(e.id),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: switch (e) {
              null => const _Working(),
              UserEntry() => _UserBlock(entry: e),
              MessageEntry() => MarkdownView(e.text.toString()),
              ThoughtEntry() => _ThoughtBlock(entry: e),
              ToolEntry() => _ToolBlock(entry: e),
              PlanEntry() => _PlanBlock(entry: e),
              NoticeEntry() => _NoticeBlock(entry: e),
            },
          );
        },
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Working', style: TextStyle(color: context.colors.textMuted)),
        ],
      );
}

class _UserBlock extends StatelessWidget {
  const _UserBlock({required this.entry});
  final UserEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.large)),
      child: Text(entry.text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

/// A block: a tappable header that expands to its body.
class _Block extends StatefulWidget {
  const _Block({required this.header, this.body, this.expanded = false, this.onLongPress});

  final Widget header;
  final Widget? body;
  final bool expanded;
  final VoidCallback? onLongPress;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  late var _open = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = widget.body;
    return Material(
      color: c.surface,
      shape: cardShape(c),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: body == null ? null : () => setState(() => _open = !_open),
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    Haptics.longPress();
                    widget.onLongPress!();
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: widget.header),
                    if (body != null) Icon(_open ? AppIcons.expandLess : AppIcons.expandMore, color: c.textMuted),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.standard,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: _open && body != null
                ? Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: body)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Running, waiting, done or failed, with color never the only signal.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph(this.status);
  final ToolStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 18,
      height: 18,
      child: switch (status) {
        ToolStatus.running => Padding(
            padding: const EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
        ToolStatus.pending => Icon(AppIcons.circle, size: 18, color: c.textMuted),
        ToolStatus.done => Icon(AppIcons.checkCircle, fill: 1, size: 18, color: c.success),
        ToolStatus.failed => Icon(AppIcons.error, fill: 1, size: 18, color: c.danger),
      },
    );
  }
}

IconData _kindIcon(ToolKind kind) => switch (kind) {
      ToolKind.read => AppIcons.article,
      ToolKind.edit => AppIcons.edit,
      ToolKind.delete => AppIcons.delete,
      ToolKind.move => AppIcons.fileMove,
      ToolKind.search => AppIcons.search,
      ToolKind.execute => AppIcons.terminal,
      ToolKind.think => AppIcons.thinking,
      ToolKind.fetch => AppIcons.language,
      ToolKind.other => AppIcons.build,
    };

class _ToolBlock extends StatelessWidget {
  const _ToolBlock({required this.entry});
  final ToolEntry entry;

  void _actions(BuildContext context) {
    final output = [for (final c in entry.content) if (c is ToolText) c.text].join('\n');
    showActionSheet(context, title: entry.title, actions: [
      if (entry.command case final cmd?) SheetAction(AppIcons.copy, 'Copy command', () => Clipboard.setData(ClipboardData(text: cmd))),
      if (output.isNotEmpty) SheetAction(AppIcons.copy, 'Copy output', () => Clipboard.setData(ClipboardData(text: output))),
      if (entry.paths.isNotEmpty)
        SheetAction(AppIcons.copy, 'Copy path', () => Clipboard.setData(ClipboardData(text: entry.paths.join('\n')))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diffs = [
      for (final d in entry.content.whereType<ToolDiff>()) (d, lineDiff(d.oldText, d.newText)),
    ];
    var added = 0, removed = 0;
    for (final (_, lines) in diffs) {
      final (a, r) = diffCounts(lines);
      added += a;
      removed += r;
    }
    final texts = entry.content.whereType<ToolText>().toList();
    // Commands and paths are machine text: mono.
    final literal = entry.command != null || entry.kind == ToolKind.execute || entry.title.startsWith('/');
    return _Block(
      expanded: entry.status == ToolStatus.failed,
      onLongPress: () => _actions(context),
      header: Row(
        children: [
          _StatusGlyph(entry.status),
          const SizedBox(width: 10),
          Icon(_kindIcon(entry.kind), size: 18, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.title.isEmpty ? 'Tool' : entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: literal ? codeStyle(c.text) : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (diffs.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('+$added', style: codeStyle(c.success, size: 12)),
            const SizedBox(width: 4),
            Text('−$removed', style: codeStyle(c.danger, size: 12)),
          ],
        ],
      ),
      body: diffs.isEmpty && texts.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (d, lines) in diffs) ...[_DiffBox(path: d.path, lines: lines), const SizedBox(height: 8)],
                for (final t in texts) ...[MarkdownView(t.text), const SizedBox(height: 4)],
              ],
            ),
    );
  }
}

/// A file change: the changed lines with a little context, + and − marks
/// beside the color.
class _DiffBox extends StatelessWidget {
  const _DiffBox({required this.path, required this.lines});
  final String path;
  final List<DiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hunks = diffHunks(lines);
    final shown = hunks.length > 200 ? hunks.sublist(0, 200) : hunks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(path, style: codeStyle(c.textMuted, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.small),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in shown)
                  l == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text('⋯', style: codeStyle(c.textMuted, size: 12)),
                        )
                      : Container(
                          color: switch (l.op) { '+' => c.diffAdded, '-' => c.diffRemoved, _ => c.surfaceAlt },
                          padding: const EdgeInsets.only(right: 12),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: ' ${l.op} ',
                                style: codeStyle(switch (l.op) { '+' => c.success, '-' => c.danger, _ => c.textMuted }, size: 12),
                              ),
                              TextSpan(text: l.text, style: codeStyle(c.text, size: 12)),
                            ]),
                          ),
                        ),
                if (hunks.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('+${hunks.length - shown.length} lines', style: codeStyle(c.textMuted, size: 12)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThoughtBlock extends StatelessWidget {
  const _ThoughtBlock({required this.entry});
  final ThoughtEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Block(
      header: Row(
        children: [
          Icon(AppIcons.thinking, size: 18, color: c.textMuted),
          const SizedBox(width: 10),
          Text('Thinking', style: TextStyle(color: c.textMuted)),
        ],
      ),
      body: MarkdownView(entry.text.toString(), color: c.textMuted),
    );
  }
}

class _PlanBlock extends StatelessWidget {
  const _PlanBlock({required this.entry});
  final PlanEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = entry.steps.where((s) => s.$2 == PlanStatus.done).length;
    return _Block(
      expanded: true,
      header: Row(
        children: [
          Icon(AppIcons.checklist, size: 18, color: c.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text('Plan', style: Theme.of(context).textTheme.titleSmall)),
          Text('$done/${entry.steps.length}', style: codeStyle(c.textMuted, size: 12)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (text, status) in entry.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: switch (status) {
                      PlanStatus.done => const _StatusGlyph(ToolStatus.done),
                      PlanStatus.pending => const _StatusGlyph(ToolStatus.pending),
                      // The current step: a still dot (agents may leave a
                      // step open when the turn ends).
                      PlanStatus.running => SizedBox(
                          width: 18,
                          height: 18,
                          child: Center(child: Icon(AppIcons.circle, fill: 1, size: 10, color: c.accent)),
                        ),
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(color: status == PlanStatus.done ? c.textMuted : c.text, fontSize: 14, height: 20 / 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeBlock extends StatelessWidget {
  const _NoticeBlock({required this.entry});
  final NoticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = entry.error ? c.danger : c.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(entry.error ? AppIcons.error : AppIcons.stop, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(entry.text, style: TextStyle(color: color, fontSize: 13))),
      ],
    );
  }
}

/// The agent asks before a tool runs: what it wants to do, and its choices.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.chat, required this.request});
  final AgentChat chat;
  final PermissionRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tool = request.tool;
    final allow = request.choices.where((o) => o.allows).toList();
    final reject = request.choices.where((o) => !o.allows).toList();
    void pick(PermissionChoice choice) {
      choice.allows ? Haptics.confirm() : Haptics.reject();
      chat.answer(request, choice);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.large),
          side: BorderSide(color: c.warning, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(tool == null ? AppIcons.lock : _kindIcon(tool.kind), size: 18, color: c.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tool?.title.isNotEmpty == true ? tool!.title : 'Permission',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: tool?.command != null ? codeStyle(c.text) : Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, o) in allow.indexed)
                    i == 0
                        ? FilledButton(onPressed: () => pick(o), child: Text(o.name))
                        : OutlinedButton(onPressed: () => pick(o), child: Text(o.name)),
                  for (final o in reject) TextButton(onPressed: () => pick(o), child: Text(o.name)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The message box: send, or stop while the agent works. "/" lists the
/// agent's commands.
class _Composer extends StatefulWidget {
  const _Composer({super.key, required this.chat});
  final AgentChat chat;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Haptics.tick();
    _text.clear();
    widget.chat.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chat = widget.chat;
    final ready = chat.state == ChatState.ready || chat.state == ChatState.working;
    final typed = _text.text;
    final matches = typed.startsWith('/') && !typed.contains(' ')
        ? [for (final cmd in chat.commands) if ('/${cmd.$1}'.startsWith(typed)) cmd].take(5).toList()
        : const <(String, String)>[];
    return Material(
      color: c.bg,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (name, description) in matches)
              ListTile(
                dense: true,
                title: Text('/$name', style: codeStyle(c.text)),
                subtitle: description.isEmpty ? null : Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  _text.text = '/$name ';
                  _text.selection = TextSelection.collapsed(offset: _text.text.length);
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: ready,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: 'Message ${chat.name}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (chat.busy)
                    IconButton.filled(
                      tooltip: 'Stop',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: c.surfaceAlt,
                        foregroundColor: c.text,
                      ),
                      onPressed: chat.cancel,
                      icon: const Icon(AppIcons.stop, fill: 1),
                    )
                  else
                    IconButton.filled(
                      tooltip: 'Send',
                      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: ready && typed.trim().isNotEmpty ? _send : null,
                      icon: const Icon(AppIcons.send),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
