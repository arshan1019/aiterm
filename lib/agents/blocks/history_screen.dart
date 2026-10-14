import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/icons.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../platform/haptics.dart';
import '../../shared/format.dart';
import '../../shared/group.dart';
import '../acp/agent_chats.dart';
import '../agent_installer.dart';

/// A project's past chats with an agent, by title, newest first; tapping
/// one opens it as blocks, in that agent (going to it if it's open).
Future<void> openChatHistory(BuildContext context, {required String cwd, required String agent}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatHistoryScreen(cwd: cwd, agent: agent)));

/// Built to docs/DESIGN.md: a grouped list (rows on the surface tone, the
/// whole row tappable), sections by date as in Chrome's history, search
/// once the list is long, skeleton rows while the agent starts (after a
/// short delay, so they never flicker), errors inline with Try again, and
/// an empty state that's one action.
class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key, required this.cwd, required this.agent});

  final String cwd;

  /// The agent shown first (the chat's).
  final String agent;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  late var _agent = widget.agent;
  late Future<List<PastChat>?> _list = _load();
  final _search = TextEditingController();
  var _showSkeleton = false;
  Timer? _skeletonDelay;

  Future<List<PastChat>?> _load() {
    _showSkeleton = false;
    _skeletonDelay?.cancel();
    _skeletonDelay = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showSkeleton = true);
    });
    return context.services.chats.history(_agent, widget.cwd);
  }

  void _reload() => setState(() => _list = _load());

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _skeletonDelay?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _open(PastChat chat) {
    Haptics.tick();
    final s = context.services;
    Navigator.pop(context);
    s.chats.open(_agent, widget.cwd, session: chat.id);
  }

  void _newChat() {
    Haptics.tick();
    final s = context.services;
    Navigator.pop(context);
    s.chats.open(_agent, widget.cwd, fresh: true);
  }

  /// Today, Yesterday, Previous 7 days, then by month.
  static String _section(DateTime? t, DateTime now) {
    if (t == null) return 'Older';
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Previous 7 days';
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return t.year == now.year ? months[t.month - 1] : '${months[t.month - 1]} ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    // Agents with blocks on, so a past chat opens as blocks.
    final agents = [for (final a in s.agents.installed) if (s.settings.blocksFor(a.id)) a];
    final name = AgentInstaller.recipe(_agent).name;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<List<PastChat>?>(
        future: _list,
        builder: (context, snap) {
          final done = snap.connectionState == ConnectionState.done;
          final chats = snap.data;
          final query = _search.text.trim().toLowerCase();
          final shown = [
            for (final chat in chats ?? const <PastChat>[])
              if (query.isEmpty || (chat.title ?? '').toLowerCase().contains(query)) chat,
          ];
          final now = DateTime.now();
          final sections = <String, List<PastChat>>{};
          for (final chat in shown) {
            sections.putIfAbsent(_section(chat.updated, now), () => []).add(chat);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (agents.length > 1)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final a in agents)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Center(
                            child: ChoiceChip(
                              label: Text(a.name),
                              selected: a.id == _agent,
                              showCheckmark: false,
                              onSelected: (_) {
                                if (a.id == _agent) return;
                                Haptics.tick();
                                _agent = a.id;
                                _search.clear();
                                _reload();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              // Search once there's enough to look through.
              if (done && (chats?.length ?? 0) > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search chats',
                      prefixIcon: Icon(AppIcons.search, color: c.textMuted),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(tooltip: 'Clear', icon: const Icon(AppIcons.close), onPressed: _search.clear),
                    ),
                  ),
                ),
              if (!done)
                if (_showSkeleton) const _Skeleton() else const SizedBox.shrink()
              else if (snap.hasError)
                _Inline(
                  icon: AppIcons.error,
                  color: c.danger,
                  title: 'Couldn\'t load the history',
                  detail: '${snap.error}',
                  action: TextButton(onPressed: _reload, child: const Text('Try again')),
                )
              else if (chats == null)
                _Inline(icon: AppIcons.history, color: c.textMuted, title: '$name keeps no history here')
              else if (chats.isEmpty)
                _Inline(
                  icon: AppIcons.history,
                  color: c.textMuted,
                  title: 'No chats yet',
                  action: FilledButton.icon(
                    onPressed: _newChat,
                    icon: const Icon(AppIcons.add, size: 18),
                    label: Text('New $name chat'),
                  ),
                )
              else if (shown.isEmpty)
                _Inline(icon: AppIcons.search, color: c.textMuted, title: 'No chats match')
              else
                for (final MapEntry(key: section, value: list) in sections.entries) ...[
                  const SizedBox(height: 16),
                  Group(
                    title: section,
                    children: [
                      for (final chat in list)
                        ListTile(
                          minTileHeight: 56,
                          title: Text(
                            chat.title ?? 'Untitled chat',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          subtitle: chat.updated == null
                              ? null
                              : Text(timeAgo(chat.updated!), style: Theme.of(context).textTheme.bodySmall),
                          trailing: s.chats.showing(widget.cwd, chat.id) != null
                              ? Text('Open', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600))
                              : Icon(AppIcons.chevronRight, color: c.textMuted),
                          onTap: () => _open(chat),
                        ),
                    ],
                  ),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Rows the shape of the list to come, while the agent starts.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.small)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        label: 'Loading',
        child: Group(
          title: ' ',
          children: [
            for (final w in const [0.7, 0.5, 0.62, 0.45])
              SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(
                    builder: (context, box) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [bar(box.maxWidth * w, 14), const SizedBox(height: 8), bar(64, 10)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A state in place of the list: what happened, and what to do.
class _Inline extends StatelessWidget {
  const _Inline({required this.icon, required this.color, required this.title, this.detail, this.action});
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 32, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (detail case final d?) ...[
              const SizedBox(height: 8),
              Text(d, maxLines: 4, overflow: TextOverflow.ellipsis, style: codeStyle(context.colors.danger, size: 12)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}
