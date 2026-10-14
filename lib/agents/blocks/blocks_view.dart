import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_thinking_orbs/flutter_thinking_orbs.dart';

import '../../app/icons.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../platform/haptics.dart';
import '../../shared/action_sheet.dart';
import '../../shared/line_diff.dart';
import '../../shared/markdown_view.dart';
import '../../shared/sheet.dart';
import '../acp/agent_chat.dart';
import '../acp/attachments.dart';
import 'history_screen.dart';

import 'dart:io';

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
    return _ChatHaptics(
      chat: chat,
      child: ListenableBuilder(
        listenable: chat,
        builder: (context, _) => Column(
          children: [
            _ChatBar(
              chat: chat,
              chats: chats,
              onSelect: onSelect,
              onNew: onNew,
              onTerminal: onTerminal,
              onClose: onClose,
            ),
            Expanded(child: _body(context)),
            if (chat.asks.firstOrNull case final ask?)
              switch (ask) {
                PermissionRequest() => _PermissionCard(key: ObjectKey(ask), chat: chat, request: ask),
                QuestionRequest() => _QuestionCard(key: ObjectKey(ask), chat: chat, request: ask),
              },
            _Composer(key: ValueKey(chat), chat: chat),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    switch (chat.state) {
      // Only an install is worth a wait screen; starting happens behind a
      // usable chat (a message typed meanwhile goes out when it's up).
      case ChatState.preparing when chat.detail != null && chat.entries.isEmpty:
        return _Centered(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 16),
            Text('Setting up ${chat.name}', style: Theme.of(context).textTheme.titleSmall),
            if (chat.detail case final d?) ...[
              const SizedBox(height: 8),
              Text(
                d,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: codeStyle(c.textMuted, size: 12),
              ),
            ],
          ],
        );
      case ChatState.signedOut:
        return _Centered(
          children: [
            Icon(AppIcons.login, size: 32, color: c.textMuted),
            const SizedBox(height: 12),
            Text('Sign in to ${chat.name}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => onTerminal(chat), child: const Text('Sign in')),
            TextButton(onPressed: chat.start, child: const Text('Try again')),
          ],
        );
      case ChatState.failed when chat.entries.isEmpty:
        return _Centered(
          children: [
            Icon(AppIcons.error, fill: 1, size: 32, color: c.danger),
            const SizedBox(height: 12),
            Text('${chat.name} didn\'t start', style: Theme.of(context).textTheme.titleMedium),
            if (chat.detail case final d?) ...[
              const SizedBox(height: 8),
              Text(
                d,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: codeStyle(c.danger, size: 12),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: chat.start, child: const Text('Try again')),
            TextButton(onPressed: () => onTerminal(chat), child: const Text('Open in terminal')),
          ],
        );
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
    showActionSheet(
      context,
      title: chat.name,
      actions: [
        for (final o in chat.options)
          if (o.id != 'mode') SheetAction(AppIcons.tune, '${o.name}: ${o.valueName}', () => _choose(context, chat, o)),
        SheetAction(AppIcons.add, 'New chat', chat.restart),
        SheetAction(AppIcons.terminal, 'Open in terminal', () => onTerminal(chat)),
        null,
        SheetAction(AppIcons.close, 'Close', () => onClose(chat)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = chat.options.where((o) => o.id == 'mode').firstOrNull;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
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
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.name,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Starting: the chat is already usable meanwhile.
                        if (chat.state == ChatState.starting || chat.state == ChatState.preparing) ...[
                          const SizedBox(width: 10),
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                        ],
                      ],
                    ),
                  ),
          ),
          if (mode != null)
            TextButton.icon(
              onPressed: () => _choose(context, chat, mode),
              icon: const Icon(AppIcons.tune, size: 18),
              label: Text(mode.valueName),
            ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(AppIcons.history),
            onPressed: () => openChatHistory(context, cwd: chat.cwd, agent: chat.agent.id),
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
///
/// Smooth while the agent streams: replies parse once per change, each
/// block paints on its own layer, and when the user has scrolled up to
/// read, growth below is offset so what they're reading stays put. The
/// arrow glides back to the latest.
class _Entries extends StatefulWidget {
  const _Entries({required this.chat});
  final AgentChat chat;

  @override
  State<_Entries> createState() => _EntriesState();
}

class _EntriesState extends State<_Entries> {
  final _scroll = ScrollController();

  /// Laid-out heights by row id, and last frame's (to measure growth).
  final _heights = <Object, double>{};
  var _before = <Object, double>{};
  var _order = <Object>[];
  var _away = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final away = _scroll.hasClients && _scroll.position.pixels > 320;
      if (away != _away) setState(() => _away = away);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the rows on screen still when rows below them (the newest)
  /// grow or arrive while the user reads further up.
  void _hold(List<Object> ids) {
    final old = _order, before = _before;
    _order = ids;
    _before = Map.of(_heights);
    if (!_scroll.hasClients || old.isEmpty) return;
    final position = _scroll.position;
    if (position.pixels <= 1) return; // at the latest: follow it
    final anchor = old.where((id) => id != 'working' && ids.contains(id)).firstOrNull;
    if (anchor == null) return;
    double? below(List<Object> order, Map<Object, double> heights) {
      var sum = 0.0;
      for (final id in order) {
        final h = heights[id];
        if (h == null) return null;
        sum += h;
        if (id == anchor) return sum;
      }
      return null;
    }

    final was = below(old, before), now = below(ids, _heights);
    if (was == null || now == null || (now - was).abs() < 0.5) return;
    position.jumpTo((position.pixels + now - was).clamp(0.0, position.maxScrollExtent + (now - was).abs()));
  }

  void _latest() {
    Haptics.tick();
    _scroll.animateTo(0, duration: Motion.standard * 2, curve: Motion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final thinking = context.services.settings.showThinking;
    final shown = [
      for (final e in chat.entries)
        if (e is! ThoughtEntry || thinking) e,
    ];
    final working = chat.busy && chat.asks.isEmpty;
    final items = [if (working) null, ...shown.reversed];
    final ids = [for (final e in items) e?.id ?? 'working'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hold(ids);
    });
    if (items.isEmpty) {
      return Center(child: Icon(AppIcons.agent, size: 40, color: context.colors.border));
    }
    return Stack(
      children: [
        SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: items.length,
            // Rows keep their identity as new blocks arrive below them.
            findChildIndexCallback: (key) {
              final i = ids.indexOf((key as ValueKey).value as Object);
              return i < 0 ? null : i;
            },
            itemBuilder: (context, i) {
              final e = items[i];
              final id = ids[i];
              return _Measured(
                key: ValueKey(id),
                onHeight: (h) => _heights[id] = h,
                child: RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: switch (e) {
                      null => _Working(chat: chat),
                      UserEntry() => _UserBlock(entry: e),
                      MessageEntry() => MarkdownView(e.text.toString()),
                      ThoughtEntry() => _ThoughtBlock(entry: e),
                      ToolEntry() => _ToolBlock(entry: e),
                      PlanEntry() => _PlanBlock(entry: e),
                      NoticeEntry() => _NoticeBlock(entry: e),
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: AnimatedScale(
            scale: _away ? 1 : 0,
            duration: Motion.quick,
            curve: Motion.enter,
            child: IconButton.filledTonal(
              tooltip: 'Latest',
              style: IconButton.styleFrom(
                backgroundColor: context.colors.surfaceAlt,
                foregroundColor: context.colors.text,
                side: BorderSide(color: context.colors.border),
              ),
              onPressed: _away ? _latest : null,
              icon: const Icon(AppIcons.arrowDownward),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports its child's laid-out height (no rebuilds).
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({super.key, required this.onHeight, super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);
  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// The agent at work: a thinking orb whose motion (and the word beside
/// it) follows what it's doing now.
class _Working extends StatelessWidget {
  const _Working({required this.chat});
  final AgentChat chat;

  (OrbState, String) _activity() => switch (chat.entries.lastOrNull) {
    ToolEntry(kind: ToolKind.search) => (OrbState.searching, 'Searching'),
    ToolEntry(kind: ToolKind.read || ToolKind.fetch) => (OrbState.searching, 'Reading'),
    ToolEntry(kind: ToolKind.edit || ToolKind.delete || ToolKind.move) => (OrbState.composing, 'Editing'),
    ToolEntry(kind: ToolKind.execute) => (OrbState.working, 'Running'),
    ToolEntry() => (OrbState.working, 'Working'),
    MessageEntry() => (OrbState.composing, 'Writing'),
    PlanEntry() => (OrbState.shaping, 'Planning'),
    _ => (OrbState.solving, 'Thinking'),
  };

  @override
  Widget build(BuildContext context) {
    final (state, label) = _activity();
    return Row(
      children: [
        ThinkingOrb(state: state, size: 24, semanticLabel: label),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: context.colors.textMuted)),
      ],
    );
  }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entry.attachments.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: entry.text.isEmpty ? 0 : 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final a in entry.attachments) _AttachmentChip(attachment: a)],
              ),
            ),
          if (entry.text.isNotEmpty) Text(entry.text, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// A block: a tappable header that expands to its body.
class _Block extends StatefulWidget {
  const _Block({required this.entry, required this.header, this.body, this.expanded = false, this.onLongPress});

  /// Holds whether it's open (see [ChatEntry.open]).
  final ChatEntry entry;
  final Widget header;
  final Widget? body;

  /// Open until the user says otherwise.
  final bool expanded;
  final VoidCallback? onLongPress;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  bool get _open => widget.entry.open ?? widget.expanded;

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
            onTap: body == null
                ? null
                : () {
                    Haptics.tick();
                    setState(() => widget.entry.open = !_open);
                  },
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
    final output = [
      for (final c in entry.content)
        if (c is ToolText) c.text,
    ].join('\n');
    showActionSheet(
      context,
      title: entry.title,
      actions: [
        if (entry.command case final cmd?)
          SheetAction(AppIcons.copy, 'Copy command', () => Clipboard.setData(ClipboardData(text: cmd))),
        if (output.isNotEmpty)
          SheetAction(AppIcons.copy, 'Copy output', () => Clipboard.setData(ClipboardData(text: output))),
        if (entry.paths.isNotEmpty)
          SheetAction(AppIcons.copy, 'Copy path', () => Clipboard.setData(ClipboardData(text: entry.paths.join('\n')))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diffs = [for (final d in entry.content.whereType<ToolDiff>()) (d, lineDiff(d.oldText, d.newText))];
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
      entry: entry,
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
                          color: switch (l.op) {
                            '+' => c.diffAdded,
                            '-' => c.diffRemoved,
                            _ => c.surfaceAlt,
                          },
                          padding: const EdgeInsets.only(right: 12),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: ' ${l.op} ',
                                  style: codeStyle(switch (l.op) {
                                    '+' => c.success,
                                    '-' => c.danger,
                                    _ => c.textMuted,
                                  }, size: 12),
                                ),
                                TextSpan(text: l.text, style: codeStyle(c.text, size: 12)),
                              ],
                            ),
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
      entry: entry,
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
      entry: entry,
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
                    child: Text(
                      text,
                      style: TextStyle(
                        color: status == PlanStatus.done ? c.textMuted : c.text,
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
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
        Expanded(
          child: Text(entry.text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}

/// The frame every ask shares: a block pinned above the message box with a
/// warning edge (it needs you), a header, scrollable content (capped, so
/// the choices stay in reach), then the choices, always last, full width,
/// one per row.
class _AskFrame extends StatelessWidget {
  const _AskFrame({required this.icon, required this.title, this.literal = false, this.content, required this.choices});
  final IconData icon;
  final String title;

  /// The title is a command or path (mono).
  final bool literal;
  final Widget? content;
  final List<Widget> choices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 18, color: c.warning),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: literal ? codeStyle(c.text) : Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              if (content != null) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
                  child: SingleChildScrollView(child: content),
                ),
              ],
              const SizedBox(height: 12),
              for (final (i, choice) in choices.indexed) ...[if (i > 0) const SizedBox(height: 8), choice],
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width choice: the agent's preferred one filled, the rest outlined,
/// declines in the danger color.
Widget _choice(
  BuildContext context,
  String label,
  VoidCallback onPressed, {
  bool primary = false,
  bool decline = false,
}) {
  final c = context.colors;
  final style = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
    alignment: Alignment.center,
    foregroundColor: decline && !primary ? WidgetStatePropertyAll(c.danger) : null,
  );
  final text = Text(label, textAlign: TextAlign.center);
  return primary
      ? FilledButton(style: style, onPressed: onPressed, child: text)
      : OutlinedButton(style: style, onPressed: onPressed, child: text);
}

/// The agent asks before a tool runs: what it wants to do (the command,
/// the edit, the plan), then its choices in its own order.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({super.key, required this.chat, required this.request});
  final AgentChat chat;
  final PermissionRequest request;

  @override
  Widget build(BuildContext context) {
    final tool = request.tool;
    void pick(PermissionChoice choice) {
      choice.allows ? Haptics.confirm() : Haptics.reject();
      chat.answer(request, choice);
    }

    final texts = [
      for (final t in tool?.content ?? const <ToolContent>[])
        if (t is ToolText) t.text,
    ];
    final diffs = [
      for (final d in tool?.content ?? const <ToolContent>[])
        if (d is ToolDiff) d,
    ];
    final command = tool?.command;
    final title = tool?.title.isNotEmpty == true ? tool!.title : 'Permission';
    return _AskFrame(
      icon: tool == null ? AppIcons.lock : _kindIcon(tool.kind),
      title: title,
      literal: command != null && command == title,
      content: texts.isEmpty && diffs.isEmpty && (command == null || command == title)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (command != null && command != title) CodeBox(command),
                for (final d in diffs) ...[
                  const SizedBox(height: 6),
                  _DiffBox(path: d.path, lines: lineDiff(d.oldText, d.newText)),
                ],
                for (final t in texts) ...[const SizedBox(height: 6), MarkdownView(t)],
              ],
            ),
      choices: [
        for (final (i, o) in request.choices.indexed)
          _choice(context, o.name, () => pick(o), primary: i == 0, decline: !o.allows),
      ],
    );
  }
}

/// The agent asks a question (Claude's AskUserQuestion): pick an answer,
/// or type your own. A single pick-one question answers on tap.
class _QuestionCard extends StatefulWidget {
  const _QuestionCard({super.key, required this.chat, required this.request});
  final AgentChat chat;
  final QuestionRequest request;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _picked = <String, Set<String>>{};
  final _typed = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final t in _typed.values) {
      t.dispose();
    }
    super.dispose();
  }

  List<AskField> get _choices => [
    for (final f in widget.request.fields)
      if (f.kind != AskFieldKind.text) f,
  ];

  /// One pick-one question: a tap is the answer.
  bool get _instant => _choices.length == 1 && _choices.single.kind == AskFieldKind.single;

  Map<String, Object?> _content() => {
    for (final f in widget.request.fields)
      if (f.kind == AskFieldKind.text)
        if (_typed[f.key]?.text.trim() case final t? when t.isNotEmpty) f.key: t else ...{}
      else if (_picked[f.key] case final p? when p.isNotEmpty)
        f.key: f.kind == AskFieldKind.multi ? p.toList() : p.first,
  };

  void _submit() {
    Haptics.confirm();
    widget.chat.answerQuestion(widget.request, _content());
  }

  void _tap(AskField f, String value) {
    Haptics.tick();
    setState(() {
      final set = _picked.putIfAbsent(f.key, () => <String>{});
      if (f.kind == AskFieldKind.multi) {
        set.contains(value) ? set.remove(value) : set.add(value);
      } else {
        set
          ..clear()
          ..add(value);
      }
    });
    if (_instant) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final request = widget.request;
    final single = request.fields.length <= 2 && _choices.length == 1;
    final answered = _content().isNotEmpty;
    return _AskFrame(
      icon: AppIcons.help,
      title: request.message.isEmpty ? 'Question' : request.message,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in request.fields) ...[
            if (!single && (f.title ?? f.description) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(f.description ?? f.title!, style: Theme.of(context).textTheme.titleSmall),
              ),
            if (f.kind == AskFieldKind.text)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  controller: _typed.putIfAbsent(
                    f.key,
                    () => TextEditingController()..addListener(() => setState(() {})),
                  ),
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: f.title ?? 'Your answer'),
                ),
              )
            else
              for (final (value, label, description) in f.options)
                _Option(
                  label: label,
                  description: description,
                  multi: f.kind == AskFieldKind.multi,
                  selected: _picked[f.key]?.contains(value) ?? false,
                  onTap: () => _tap(f, value),
                ),
          ],
        ],
      ),
      choices: [
        if (!_instant || answered) _choice(context, 'Answer', answered ? _submit : () {}, primary: answered),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.textMuted),
          onPressed: () {
            Haptics.tick();
            widget.chat.skipQuestion(request);
          },
          child: const Text('Skip'),
        ),
      ],
    );
  }
}

/// One answer to pick: a radio (pick one) or a check (pick several), the
/// label and its explanation, the whole row tappable.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    this.description,
    required this.multi,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String? description;
  final bool multi, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: selected ? c.accentContainer : c.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.medium),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    multi
                        ? (selected ? AppIcons.checkBox : AppIcons.checkBoxBlank)
                        : (selected ? AppIcons.radioOn : AppIcons.radioOff),
                    fill: selected ? 1 : 0,
                    size: 20,
                    color: selected ? c.onAccentContainer : c.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(color: selected ? c.onAccentContainer : c.text, fontSize: 15)),
                        if (description case final d?)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              d,
                              style: TextStyle(color: selected ? c.onAccentContainer : c.textMuted, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
  final _focus = FocusNode();
  bool get _focused => _focus.hasFocus;
  final _files = <ChatAttachment>[];
  var _picking = false;

  Future<void> _attach() async {
    setState(() => _picking = true);
    try {
      final picked = await pickAttachments(context.services);
      if (mounted && picked.isNotEmpty) {
        Haptics.tick();
        setState(() => _files.addAll(picked));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t attach: $e')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty && _files.isEmpty) return;
    Haptics.tick();
    final files = [..._files];
    _text.clear();
    setState(_files.clear);
    widget.chat.send(text, attachments: files);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chat = widget.chat;
    final ready = chat.accepting;
    final typed = _text.text;
    final canSend = ready && (typed.trim().isNotEmpty || _files.isNotEmpty);
    final matches = typed.startsWith('/') && !typed.contains(' ')
        ? [
            for (final cmd in chat.commands)
              if ('/${cmd.$1}'.startsWith(typed)) cmd,
          ].take(5).toList()
        : const <(String, String)>[];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: c.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The agent's commands for what's typed after "/".
              if (matches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: c.surface,
                    shape: cardShape(c),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (name, description) in matches)
                          ListTile(
                            title: Text('/$name', style: codeStyle(c.text)),
                            subtitle: description.isEmpty
                                ? null
                                : Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              Haptics.tick();
                              _text.text = '/$name ';
                              _text.selection = TextSelection.collapsed(offset: _text.text.length);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              // One container: attachments, the growing text, attach and
              // send inside it (the pattern of Messages, Gemini, Claude).
              AnimatedContainer(
                duration: Motion.quick,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _focused ? c.outline : c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in _files)
                              _AttachmentChip(attachment: f, onRemove: () => setState(() => _files.remove(f))),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Attach',
                          onPressed: ready && !_picking ? _attach : null,
                          icon: _picking
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(AppIcons.attach, color: c.textMuted),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            focusNode: _focus,
                            enabled: ready,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: 'Message ${chat.name}',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              // 24dp line + 12 + 12: as tall as the buttons.
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        chat.busy
                            ? IconButton(
                                tooltip: 'Stop',
                                style: _roundButton(background: c.text, foreground: c.bg, c: c),
                                onPressed: () {
                                  Haptics.tick();
                                  chat.cancel();
                                },
                                icon: const Icon(AppIcons.stop, fill: 1, size: 20),
                              )
                            : IconButton(
                                tooltip: 'Send',
                                // Mint either way: the bright accent on dark,
                                // the tonal pair on light.
                                style: dark
                                    ? _roundButton(background: c.accent, foreground: c.bg, c: c)
                                    : _roundButton(
                                        background: c.accentContainer,
                                        foreground: c.onAccentContainer,
                                        c: c,
                                      ),
                                onPressed: canSend ? _send : null,
                                icon: const Icon(AppIcons.arrowUpward, size: 22),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A file sent (or about to be) with a message: the picture itself for an
/// image, else its name; × removes it before sending.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final file = File(attachment.hostPath);
    final image = attachment.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(Radii.medium),
            child: Image.file(
              file,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              cacheWidth: 168,
              errorBuilder: (_, _, _) => Icon(AppIcons.description, color: c.textMuted),
            ),
          )
        : null;
    return Semantics(
      label: attachment.name,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
          border: Border.all(color: c.border),
        ),
        padding: EdgeInsets.only(left: image == null ? 10 : 0, right: onRemove == null ? 10 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?image,
            if (image == null) ...[
              Icon(AppIcons.description, size: 18, color: c.textMuted),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: codeStyle(c.text, size: 12),
                ),
              ),
            ],
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove ${attachment.name}',
                icon: Icon(AppIcons.close, size: 18, color: c.textMuted),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// Send and Stop: 40dp circles inside the box, 48dp to touch; disabled
/// stays legible (muted on a tone).
ButtonStyle _roundButton({required Color background, required Color foreground, required AppColors c}) =>
    IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      minimumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: c.border,
      disabledForegroundColor: c.textMuted,
    );

/// The chat's moments felt, on the frame they show and only while the chat
/// is on screen with the app in front: a click asking for an answer, a
/// confirm when a turn finishes, a reject when it fails.
class _ChatHaptics extends StatefulWidget {
  const _ChatHaptics({required this.chat, required this.child});
  final AgentChat chat;
  final Widget child;

  @override
  State<_ChatHaptics> createState() => _ChatHapticsState();
}

class _ChatHapticsState extends State<_ChatHaptics> {
  late var _asks = widget.chat.asks.length;
  late var _busy = widget.chat.busy;
  late var _failed = widget.chat.state == ChatState.failed;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ChatHaptics old) {
    super.didUpdateWidget(old);
    if (old.chat != widget.chat) {
      old.chat.removeListener(_changed);
      widget.chat.addListener(_changed);
      _asks = widget.chat.asks.length;
      _busy = widget.chat.busy;
      _failed = widget.chat.state == ChatState.failed;
    }
  }

  @override
  void dispose() {
    widget.chat.removeListener(_changed);
    super.dispose();
  }

  bool get _seen =>
      mounted &&
      TickerMode.valuesOf(context).enabled &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _changed() {
    final chat = widget.chat;
    final asks = chat.asks.length, busy = chat.busy, failed = chat.state == ChatState.failed;
    final seen = _seen;
    if (seen) {
      if (asks > _asks) {
        Haptics.attention();
      } else if (failed && !_failed) {
        Haptics.reject();
      } else if (_busy && !busy) {
        final last = chat.entries.lastOrNull;
        // Stop was the user's own tap (it clicked already).
        if (last is NoticeEntry && last.error) {
          Haptics.reject();
        } else if (!(last is NoticeEntry && last.text == 'Stopped.')) {
          Haptics.confirm();
        }
      }
    }
    _asks = asks;
    _busy = busy;
    _failed = failed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
