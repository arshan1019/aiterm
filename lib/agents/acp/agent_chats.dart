import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../shared/fs_atomic.dart';
import 'acp_host.dart';
import 'agent_chat.dart';

/// What a project's agent tab shows when it has both.
enum AgentView { blocks, terminal }

/// Makes (but doesn't start) a chat with [agent] in [cwd] on [host]: the
/// [number]th with that agent there (1 resumes the remembered session).
typedef ChatFactory = AgentChat Function(String agent, String cwd, AcpHost host, int number);

/// The open agent chats (any number per agent per project, sharing one
/// agent process each), each project's view, and the sessions to pick up
/// again after a restart.
class AgentChats extends ChangeNotifier implements ChatSessions {
  AgentChats(this._file, {required AcpHost Function(String agent, String cwd) host, required ChatFactory chat})
      : _newHost = host,
        _newChat = chat;

  final File _file;
  final AcpHost Function(String agent, String cwd) _newHost;
  final ChatFactory _newChat;

  final _hosts = <String, AcpHost>{};
  final _chats = <AgentChat>[];
  final _numbers = <AgentChat, int>{};
  final _active = <String, AgentChat>{};
  final _views = <String, AgentView>{};
  var _sessions = <String, String>{};
  Future<void> _saving = Future.value();

  static String _key(String agent, String cwd) => '$agent\n$cwd';

  Future<void> load() async {
    try {
      _sessions = (jsonDecode(await _file.readAsString()) as Map).cast<String, String>();
    } catch (_) {
      // None yet, or unreadable: start fresh.
    }
  }

  /// The chats in project [cwd], oldest first.
  List<AgentChat> inProject(String cwd) => [for (final c in _chats) if (c.cwd == cwd) c];

  /// The chat project [cwd] shows.
  AgentChat? active(String cwd) => _active[cwd] ?? inProject(cwd).lastOrNull;

  AgentView viewOf(String cwd) => _views[cwd] ?? AgentView.blocks;

  void show(String cwd, AgentView view) {
    if (_views[cwd] == view) return;
    _views[cwd] = view;
    notifyListeners();
  }

  /// Opens [agent] in [cwd] and shows it: back to its latest chat there, or
  /// with [fresh] (or none open yet) a new chat on the same agent process.
  ///
  /// [session] opens that past chat (from History), or goes to the chat
  /// already showing it.
  AgentChat open(String agent, String cwd, {bool fresh = false, String? session}) {
    final mine = [for (final c in _chats) if (c.agent.id == agent && c.cwd == cwd) c];
    final showing = session == null ? null : mine.where((c) => c.sessionId == session).firstOrNull;
    final AgentChat chat;
    if (showing != null) {
      chat = showing;
    } else if (mine.isNotEmpty && !fresh && session == null) {
      chat = _active[cwd]?.agent.id == agent ? _active[cwd]! : mine.last;
    } else {
      final host = _hosts[_key(agent, cwd)] ??= _newHost(agent, cwd);
      // The lowest free number: closing "Claude Code 2" frees 2.
      final taken = {for (final c in mine) _numbers[c]};
      var number = 1;
      while (taken.contains(number)) {
        number++;
      }
      chat = _watch(_newChat(agent, cwd, host, number));
      _numbers[chat] = number;
      _chats.add(chat);
      chat.start(load: session);
    }
    _active[cwd] = chat;
    _views[cwd] = AgentView.blocks;
    notifyListeners();
    return chat;
  }

  final _seen = <AgentChat, (ChatState, int)>{};
  final _listeners = <AgentChat, VoidCallback>{};

  /// Passes on only what the workspace shows (state, waiting for the user),
  /// not every streamed chunk; the chat's own view listens to the chat.
  AgentChat _watch(AgentChat chat) {
    void listener() {
      final now = (chat.state, chat.asks.length);
      if (_seen[chat] == now) return;
      _seen[chat] = now;
      notifyListeners();
    }

    _listeners[chat] = listener;
    chat.addListener(listener);
    return chat;
  }

  void select(AgentChat chat) {
    _active[chat.cwd] = chat;
    notifyListeners();
  }

  /// Ends [chat] (the first chat's session stays remembered for next time);
  /// the agent process stops with the last chat on it.
  void close(AgentChat chat) {
    if (!_chats.remove(chat)) return;
    final listener = _listeners.remove(chat);
    if (listener != null) chat.removeListener(listener);
    _seen.remove(chat);
    _numbers.remove(chat);
    if (_active[chat.cwd] == chat) _active.remove(chat.cwd);
    chat.dispose();
    final key = _key(chat.agent.id, chat.cwd);
    if (!_chats.any((c) => _key(c.agent.id, c.cwd) == key)) _hosts.remove(key)?.dispose();
    notifyListeners();
  }

  /// [agent]'s past chats in [cwd], newest first (ACP `session/list`);
  /// null when the agent keeps no list. Starts the agent if needed.
  Future<List<PastChat>?> history(String agent, String cwd) async {
    final key = _key(agent, cwd);
    final host = _hosts[key] ??= _newHost(agent, cwd);
    try {
      await host.ensure();
      if (!host.can('list')) return null;
      final found = <PastChat>[];
      String? cursor;
      for (var page = 0; page < 10; page++) {
        final r = await host.request('session/list', {'cwd': cwd, 'cursor': ?cursor});
        for (final s in (r['sessions'] as List? ?? const []).whereType<Map>()) {
          final id = s['sessionId'];
          if (id is! String) continue;
          final title = (s['title'] as String?)?.trim();
          found.add(PastChat(
            id,
            title == null || title.isEmpty ? null : title,
            DateTime.tryParse('${s['updatedAt']}')?.toLocal(),
          ));
        }
        cursor = r['nextCursor'] as String?;
        if (cursor == null) break;
      }
      found.sort((a, b) => (b.updated ?? DateTime(0)).compareTo(a.updated ?? DateTime(0)));
      return found;
    } finally {
      // Started only to list: stop it again.
      if (!_chats.any((c) => _key(c.agent.id, c.cwd) == key)) _hosts.remove(key)?.dispose();
    }
  }

  /// The chat showing session [id] in [cwd], if one is open.
  AgentChat? showing(String cwd, String id) => inProject(cwd).where((c) => c.sessionId == id).firstOrNull;

  /// A chat in [cwd] is waiting for the user (a permission or a question).
  bool needsInput(String cwd) => inProject(cwd).any((c) => c.asks.isNotEmpty);

  @override
  String? sessionFor(String agent, String cwd) => _sessions[_key(agent, cwd)];

  @override
  void remember(String agent, String cwd, String? sessionId) {
    final key = _key(agent, cwd);
    if (_sessions[key] == sessionId) return;
    if (sessionId == null) {
      _sessions.remove(key);
    } else {
      _sessions[key] = sessionId;
    }
    final json = jsonEncode(_sessions);
    _saving = _saving.then((_) => writeFileAtomic(_file.path, json)).catchError((Object _) {});
  }

  @visibleForTesting
  Future<void> get saved => _saving;
}

/// A conversation the agent kept: its session, title and last activity.
class PastChat {
  const PastChat(this.id, this.title, this.updated);
  final String id;
  final String? title;
  final DateTime? updated;
}
