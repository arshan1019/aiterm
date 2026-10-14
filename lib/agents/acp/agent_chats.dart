import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../shared/fs_atomic.dart';
import 'agent_chat.dart';

/// What a project's agent tab shows when it has both.
enum AgentView { blocks, terminal }

/// The open agent chats (one per agent per project), each project's view,
/// and the sessions to pick up again after a restart.
class AgentChats extends ChangeNotifier implements ChatSessions {
  AgentChats(this._file, this._create);

  final File _file;

  /// Makes (but doesn't start) agent [agent]'s chat in folder [cwd].
  final AgentChat Function(String agent, String cwd) _create;

  final _chats = <String, AgentChat>{};
  final _active = <String, String>{};
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
  List<AgentChat> inProject(String cwd) => [for (final c in _chats.values) if (c.cwd == cwd) c];

  /// The chat project [cwd] shows.
  AgentChat? active(String cwd) => _chats[_active[cwd] ?? ''] ?? inProject(cwd).lastOrNull;

  AgentView viewOf(String cwd) => _views[cwd] ?? AgentView.blocks;

  void show(String cwd, AgentView view) {
    if (_views[cwd] == view) return;
    _views[cwd] = view;
    notifyListeners();
  }

  /// Opens (or goes back to) [agent]'s chat in [cwd] and shows it.
  AgentChat open(String agent, String cwd) {
    final key = _key(agent, cwd);
    var chat = _chats[key];
    if (chat == null) {
      chat = _chats[key] = _watch(_create(agent, cwd));
      chat.start();
    }
    _active[cwd] = key;
    _views[cwd] = AgentView.blocks;
    notifyListeners();
    return chat;
  }

  final _seen = <AgentChat, (ChatState, bool)>{};
  final _listeners = <AgentChat, VoidCallback>{};

  /// Passes on only what the workspace shows (state, waiting for the user),
  /// not every streamed chunk; the chat's own view listens to the chat.
  AgentChat _watch(AgentChat chat) {
    void listener() {
      final now = (chat.state, chat.permissions.isNotEmpty);
      if (_seen[chat] == now) return;
      _seen[chat] = now;
      notifyListeners();
    }

    _listeners[chat] = listener;
    chat.addListener(listener);
    return chat;
  }

  void select(AgentChat chat) {
    _active[chat.cwd] = _key(chat.agent.id, chat.cwd);
    notifyListeners();
  }

  /// Ends [chat] (its session stays remembered for next time).
  void close(AgentChat chat) {
    if (_chats.remove(_key(chat.agent.id, chat.cwd)) == null) return;
    final listener = _listeners.remove(chat);
    if (listener != null) chat.removeListener(listener);
    _seen.remove(chat);
    chat.dispose();
    notifyListeners();
  }

  /// A chat in [cwd] is waiting for the user (a permission request).
  bool needsInput(String cwd) => inProject(cwd).any((c) => c.permissions.isNotEmpty);

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
