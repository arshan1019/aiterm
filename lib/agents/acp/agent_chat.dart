import 'dart:async';
import 'package:flutter/foundation.dart';
import 'acp_agents.dart';
import 'acp_connection.dart';

/// One unit of a chat, shown as a block.
sealed class ChatEntry {
  ChatEntry(this.id);

  /// Stable within the chat (list keys).
  final int id;

  /// Whether its block is open; null until the user taps it (each kind has
  /// its default). Kept here, not in the widget, so an open block stays
  /// open while the agent streams more below it or the list scrolls.
  bool? open;
}

/// A file sent with a message: copied into Linux at [path] (a guest path,
/// [hostPath] on the device). Images carry their [imageData] (base64) to
/// go inline when the agent takes images.
class ChatAttachment {
  const ChatAttachment({required this.name, required this.path, required this.hostPath, this.imageData, this.mimeType});

  final String name;
  final String path;
  final String hostPath;
  final String? imageData;
  final String? mimeType;

  bool get isImage => imageData != null;
}

/// What the user sent.
class UserEntry extends ChatEntry {
  UserEntry(super.id, this.text, [this.attachments = const []]);
  String text;
  final List<ChatAttachment> attachments;
}

/// The agent's reply (Markdown), streamed in chunks.
class MessageEntry extends ChatEntry {
  MessageEntry(super.id, this.messageId);
  final String? messageId;
  final text = StringBuffer();
}

/// The agent's reasoning, streamed in chunks.
class ThoughtEntry extends ChatEntry {
  ThoughtEntry(super.id, this.messageId);
  final String? messageId;
  final text = StringBuffer();
}

enum ToolStatus { pending, running, done, failed }

/// What a tool call is doing (ACP's tool kinds).
enum ToolKind { read, edit, delete, move, search, execute, think, fetch, other }

/// Part of a tool call's output.
sealed class ToolContent {
  const ToolContent();
}

class ToolText extends ToolContent {
  const ToolText(this.text);
  final String text;
}

/// A file change: [oldText] null for a new file.
class ToolDiff extends ToolContent {
  const ToolDiff(this.path, this.oldText, this.newText);
  final String path;
  final String? oldText;
  final String newText;
}

/// A tool call: reading, editing, running a command…
class ToolEntry extends ChatEntry {
  ToolEntry(super.id, this.toolCallId);

  final String toolCallId;
  String title = '';
  ToolKind kind = ToolKind.other;
  ToolStatus status = ToolStatus.pending;
  List<ToolContent> content = const [];
  List<String> paths = const [];

  /// The command, for tools that run one.
  String? command;
}

enum PlanStatus { pending, running, done }

/// The agent's to-do list for the task; replaced whole on every update.
class PlanEntry extends ChatEntry {
  PlanEntry(super.id);
  List<(String, PlanStatus)> steps = const [];
}

/// Something about the chat itself: a refusal, a stop, an error.
class NoticeEntry extends ChatEntry {
  NoticeEntry(super.id, this.text, {this.error = false});
  final String text;
  final bool error;
}

/// A choice the agent offers on a permission request.
class PermissionChoice {
  const PermissionChoice(this.id, this.name, this.kind);
  final String id;
  final String name;

  /// allow_once, allow_always, reject_once or reject_always.
  final String kind;
  bool get allows => kind.startsWith('allow');
}

/// The agent asks before a tool call runs.
class PermissionRequest {
  PermissionRequest(this.tool, this.choices, this._answer);
  final ToolEntry? tool;
  final List<PermissionChoice> choices;
  final Completer<Object?> _answer;
}

/// A setting the agent offers for the session: mode (how much it asks)
/// or model.
class ChatOption {
  const ChatOption(this.id, this.name, this.value, this.choices, {this.legacyMode = false});

  final String id;
  final String name;
  final String value;

  /// (value, name).
  final List<(String, String)> choices;

  /// From session modes (session/set_mode) rather than config options.
  final bool legacyMode;

  String get valueName => choices.where((c) => c.$1 == value).firstOrNull?.$2 ?? value;

  ChatOption withValue(String v) => ChatOption(id, name, v, choices, legacyMode: legacyMode);
}

enum ChatState {
  /// Installing the agent's ACP adapter.
  preparing,
  starting,
  ready,

  /// A turn is running.
  working,

  /// The agent needs a sign-in (done in its own terminal UI).
  signedOut,
  failed,
}

/// Remembers sessions so a chat picks up where it left off.
abstract class ChatSessions {
  String? sessionFor(String agent, String cwd);
  void remember(String agent, String cwd, String? sessionId);
}

/// An agent as blocks: its ACP session in [cwd], turned into entries.
class AgentChat extends ChangeNotifier {
  AgentChat({
    required this.agent,
    required this.name,
    required this.cwd,
    required this._start,
    required this._prepare,
    required this._sessions,
    this._preferred = const {},
    this._onOptionChosen,
    this.attachmentsDir,
  });

  /// Where attachments are copied (a guest path), granted to the session up
  /// front where the agent supports extra folders, so reading them asks
  /// nothing.
  final String? attachmentsDir;

  final AcpAgent agent;
  final String name;
  final String cwd;
  final AcpStarter _start;
  final AcpPreparer _prepare;
  final ChatSessions _sessions;
  final Map<String, String> _preferred;
  final void Function(String option, String value)? _onOptionChosen;

  AcpConnection? _connection;
  String? _sessionId;
  var _nextEntry = 0;
  var _disposed = false;

  final entries = <ChatEntry>[];
  final _tools = <String, ToolEntry>{};
  ChatState state = ChatState.starting;

  /// What's happening (installing step) or what went wrong.
  String? detail;
  List<ChatOption> options = const [];

  /// Slash commands the agent offers: (name, description).
  List<(String, String)> commands = const [];
  final permissions = <PermissionRequest>[];

  /// A message sent before the session was up, going out once it is.
  (String, List<ChatAttachment>)? _queued;
  Map<Object?, Object?> _capabilities = const {};

  /// A turn is running (or waiting for the session to go out).
  bool get busy => state == ChatState.working || _queued != null;

  /// The agent takes images inline (others get them as file links).
  bool get acceptsImages => (_capabilities['promptCapabilities'] as Map?)?['image'] == true;

  /// The message box takes messages (queued while the agent starts).
  bool get accepting =>
      state == ChatState.ready || state == ChatState.working || state == ChatState.starting || state == ChatState.preparing;

  /// Starts (or restarts) the agent and its session.
  Future<void> start() async {
    await _connection?.close();
    _connection = null;
    state = ChatState.preparing;
    detail = null;
    _changed();
    final problem = await _prepare(agent, (line) {
      detail = line;
      _changed();
    });
    if (_disposed) return;
    if (problem != null) return _fail(problem);
    state = ChatState.starting;
    detail = null;
    _changed();
    try {
      final transport = await _start(agent, cwd);
      final connection = AcpConnection(transport, onNotification: _onNotification, onRequest: _onRequest);
      _connection = connection;
      transport.exitCode.then((_) {
        if (_connection == connection && !_disposed && state != ChatState.failed && state != ChatState.signedOut) {
          _fail(_lastLog(transport) ?? 'The agent stopped.');
        }
      });
      final init = await connection.request('initialize', {
        'protocolVersion': 1,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
        },
        'clientInfo': {'name': 'aiterm', 'version': '1.0.0'},
      });
      _capabilities = (init['agentCapabilities'] as Map?) ?? const {};
      await _openSession(resume: true);
    } on AcpError catch (e) {
      if (e.code == AcpError.authRequired) {
        state = ChatState.signedOut;
        detail = e.message;
        _changed();
      } else {
        _fail(e.message);
      }
    } catch (e) {
      _fail('$e');
    }
  }

  /// Opens a session on the running agent: the remembered one when
  /// [resume] and the agent can load it, else a new one. Then sends any
  /// message typed meanwhile.
  Future<void> _openSession({required bool resume}) async {
    final connection = _connection!;
    final saved = resume ? _sessions.sessionFor(agent.id, cwd) : null;
    final sessionCaps = _capabilities['sessionCapabilities'];
    final extra = attachmentsDir != null && sessionCaps is Map && sessionCaps.containsKey('additionalDirectories')
        ? {'additionalDirectories': [attachmentsDir]}
        : const <String, Object?>{};
    AcpParams? session;
    if (saved != null && _capabilities['loadSession'] == true) {
      _sessionId = saved; // its replayed history arrives before the reply
      try {
        session = await connection.request('session/load', {'sessionId': saved, 'cwd': cwd, 'mcpServers': [], ...extra});
      } on AcpError catch (e) {
        if (e.code == AcpError.authRequired) rethrow;
        // Gone (or unreadable): start a new one.
      }
    }
    if (session == null) {
      _sessionId = null;
      session = await connection.request('session/new', {'cwd': cwd, 'mcpServers': [], ...extra});
      _sessionId = session['sessionId'] as String?;
    }
    if (_disposed) return;
    _sessions.remember(agent.id, cwd, _sessionId);
    _readOptions(session);
    state = ChatState.ready;
    _changed();
    await _applyPreferred();
    if (_queued case (final text, final files)?) {
      _queued = null;
      await _prompt(text, files);
    }
  }

  String? _lastLog(AcpTransport t) {
    final lines = t.log.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.isEmpty ? null : lines.last;
  }

  void _fail(String why) {
    state = ChatState.failed;
    detail = why;
    _cancelPermissions();
    _changed();
  }

  /// Sends [text] as the next turn; while the agent is still starting it
  /// shows at once and goes out when the session is up.
  Future<void> send(String text, {List<ChatAttachment> attachments = const []}) async {
    if ((text.trim().isEmpty && attachments.isEmpty) || busy || !accepting) return;
    entries.add(UserEntry(_nextEntry++, text, attachments));
    if (state != ChatState.ready) {
      _queued = (text, attachments);
      _changed();
      return;
    }
    await _prompt(text, attachments);
  }

  /// The prompt's content: the text, then images inline (when the agent
  /// takes them) and every other file as a link the agent opens itself.
  List<Map<String, Object?>> _blocks(String text, List<ChatAttachment> files) => [
        if (text.trim().isNotEmpty) {'type': 'text', 'text': text},
        for (final f in files)
          if (f.isImage && acceptsImages)
            {'type': 'image', 'data': f.imageData, 'mimeType': f.mimeType ?? 'image/png'}
          else
            {'type': 'resource_link', 'uri': Uri.file(f.path).toString(), 'name': f.name, 'mimeType': ?f.mimeType},
      ];

  Future<void> _prompt(String text, [List<ChatAttachment> files = const []]) async {
    final connection = _connection;
    final session = _sessionId;
    if (connection == null || session == null) return;
    state = ChatState.working;
    _changed();
    try {
      final result = await connection.request('session/prompt', {
        'sessionId': session,
        'prompt': _blocks(text, files),
      });
      final note = switch (result['stopReason']) {
        'refusal' => 'The agent declined to continue.',
        'max_tokens' => 'The reply hit the length limit.',
        'max_turn_requests' => 'The agent stopped after too many steps.',
        'cancelled' => 'Stopped.',
        _ => null,
      };
      if (note != null) entries.add(NoticeEntry(_nextEntry++, note));
      _settleTools();
      if (state == ChatState.working) state = ChatState.ready;
    } on AcpError catch (e) {
      if (e.code == AcpError.closed) return; // The exit handler reports it.
      entries.add(NoticeEntry(_nextEntry++, e.message, error: true));
      _settleTools();
      if (e.code == AcpError.authRequired) {
        state = ChatState.signedOut;
      } else if (state == ChatState.working) {
        state = ChatState.ready;
      }
    }
    _changed();
  }

  /// Tool calls the agent never closed (a stopped turn) stop spinning.
  void _settleTools() {
    for (final t in _tools.values) {
      if (t.status == ToolStatus.pending || t.status == ToolStatus.running) t.status = ToolStatus.failed;
    }
  }

  /// Stops the running turn.
  void cancel() {
    if (_queued != null) {
      _queued = null;
      entries.add(NoticeEntry(_nextEntry++, 'Stopped.'));
      _changed();
      return;
    }
    final session = _sessionId;
    if (session == null || !busy) return;
    _cancelPermissions();
    _connection?.notify('session/cancel', {'sessionId': session});
    _changed();
  }

  /// Answers the oldest permission request.
  void answer(PermissionRequest request, PermissionChoice choice) {
    if (!permissions.remove(request)) return;
    request._answer.complete({
      'outcome': {'outcome': 'selected', 'optionId': choice.id},
    });
    _changed();
  }

  void _cancelPermissions() {
    for (final p in permissions) {
      p._answer.complete({
        'outcome': {'outcome': 'cancelled'},
      });
    }
    permissions.clear();
  }

  /// Picks [value] for [option] (mode or model), and remembers it.
  Future<void> choose(ChatOption option, String value) async {
    final connection = _connection;
    final session = _sessionId;
    if (connection == null || session == null || option.value == value) return;
    try {
      if (option.legacyMode) {
        await connection.request('session/set_mode', {'sessionId': session, 'modeId': value});
        _setOption(option.id, value);
      } else {
        final result = await connection.request(
          'session/set_config_option',
          {'sessionId': session, 'configId': option.id, 'value': value},
        );
        if (result['configOptions'] is List) {
          _readOptions(result);
        } else {
          _setOption(option.id, value);
        }
      }
      _onOptionChosen?.call(option.id, value);
    } on AcpError catch (e) {
      entries.add(NoticeEntry(_nextEntry++, e.message, error: true));
    }
    _changed();
  }

  Future<void> _applyPreferred() async {
    for (final option in options) {
      final want = _preferred[option.id];
      if (want != null && want != option.value && option.choices.any((c) => c.$1 == want)) {
        await choose(option, want);
      }
    }
  }

  /// A new conversation on the running agent (no restart): the old
  /// session is closed and forgotten, and the chat is usable at once.
  Future<void> restart() async {
    final connection = _connection;
    final old = _sessionId;
    _sessions.remember(agent.id, cwd, null);
    entries.clear();
    _tools.clear();
    _cancelPermissions();
    _queued = null;
    if (connection == null || connection.closed || state == ChatState.failed || state == ChatState.signedOut) {
      return start();
    }
    if (busy && old != null) connection.notify('session/cancel', {'sessionId': old});
    // Frees the old session's agent process, where the agent supports it.
    final sessionCaps = _capabilities['sessionCapabilities'];
    if (old != null && sessionCaps is Map && sessionCaps.containsKey('close')) {
      connection.request('session/close', {'sessionId': old}).ignore();
    }
    state = ChatState.starting;
    _changed();
    try {
      await _openSession(resume: false);
    } on AcpError catch (e) {
      if (e.code == AcpError.authRequired) {
        state = ChatState.signedOut;
        _changed();
      } else if (e.code != AcpError.closed) {
        _fail(e.message);
      }
    }
  }

  void _setOption(String id, String value) {
    options = [for (final o in options) o.id == id ? o.withValue(value) : o];
  }

  void _readOptions(AcpParams p) {
    final config = p['configOptions'];
    final read = <ChatOption>[];
    if (config is List) {
      for (final o in config.whereType<Map>()) {
        if (o['type'] != 'select') continue;
        final choices = [
          for (final c in (o['options'] as List? ?? const []).whereType<Map>())
            if (c['value'] is String) (c['value'] as String, (c['name'] as String?) ?? c['value'] as String),
        ];
        if (o['id'] is String && choices.isNotEmpty) {
          read.add(ChatOption(o['id'] as String, (o['name'] as String?) ?? o['id'] as String,
              (o['currentValue'] as String?) ?? choices.first.$1, choices));
        }
      }
    }
    final modes = p['modes'];
    if (!read.any((o) => o.id == 'mode') && modes is Map && modes['availableModes'] is List) {
      final choices = [
        for (final m in (modes['availableModes'] as List).whereType<Map>())
          if (m['id'] is String) (m['id'] as String, (m['name'] as String?) ?? m['id'] as String),
      ];
      if (choices.isNotEmpty) {
        read.insert(0, ChatOption('mode', 'Mode', (modes['currentModeId'] as String?) ?? choices.first.$1, choices,
            legacyMode: true));
      }
    }
    if (read.isNotEmpty || config is List) options = read;
  }

  // ---- From the agent ------------------------------------------------------

  void _onNotification(String method, AcpParams params) {
    if (method != 'session/update') return;
    // A session this chat moved on from (New chat) may still be talking.
    if (_sessionId != null && params['sessionId'] != null && params['sessionId'] != _sessionId) return;
    final u = params['update'];
    if (u is! Map) return;
    switch (u['sessionUpdate']) {
      case 'user_message_chunk':
        // A loaded session replaying what the user said.
        final text = _text(u['content']);
        if (text == null) break;
        final last = entries.lastOrNull;
        if (last is UserEntry && state != ChatState.working) {
          last.text += text;
        } else {
          entries.add(UserEntry(_nextEntry++, text));
        }
      case 'agent_message_chunk':
        final text = _text(u['content']);
        if (text != null) _chunk<MessageEntry>(u['messageId'] as String?, text, MessageEntry.new);
      case 'agent_thought_chunk':
        final text = _text(u['content']);
        if (text != null) _chunk<ThoughtEntry>(u['messageId'] as String?, text, ThoughtEntry.new);
      case 'tool_call':
      case 'tool_call_update':
        _tool(u.cast<String, Object?>());
      case 'plan':
        _plan(u['entries']);
      case 'available_commands_update':
        commands = [
          for (final c in (u['availableCommands'] as List? ?? const []).whereType<Map>())
            if (c['name'] is String) (c['name'] as String, (c['description'] as String?) ?? ''),
        ];
      case 'current_mode_update':
        if (u['currentModeId'] is String) _setOption('mode', u['currentModeId'] as String);
      case 'config_option_update':
        _readOptions(u.cast<String, Object?>());
      default:
        return; // usage, notices and newer updates aren't shown.
    }
    _changed();
  }

  static String? _text(Object? block) =>
      block is Map && block['type'] == 'text' && block['text'] is String ? block['text'] as String : null;

  void _chunk<T extends ChatEntry>(String? messageId, String text, T Function(int, String?) make) {
    final last = entries.lastOrNull;
    final same = switch (last) {
      MessageEntry m when T == MessageEntry => messageId == null || m.messageId == messageId,
      ThoughtEntry m when T == ThoughtEntry => messageId == null || m.messageId == messageId,
      _ => false,
    };
    final entry = same ? last! : (make(_nextEntry++, messageId)..let(entries.add));
    switch (entry) {
      case MessageEntry m:
        m.text.write(text);
      case ThoughtEntry m:
        m.text.write(text);
      default:
    }
  }

  ToolEntry _tool(AcpParams u) {
    final id = u['toolCallId'] as String? ?? '';
    final tool = _tools[id] ??= (ToolEntry(_nextEntry++, id)..let(entries.add));
    if (u['title'] is String) tool.title = u['title'] as String;
    if (u['kind'] is String) {
      tool.kind = ToolKind.values.asNameMap()[u['kind']] ?? ToolKind.other;
    }
    if (u['status'] is String) {
      tool.status = switch (u['status']) {
        'in_progress' => ToolStatus.running,
        'completed' => ToolStatus.done,
        'failed' => ToolStatus.failed,
        _ => ToolStatus.pending,
      };
    }
    final input = u['rawInput'];
    if (input is Map && input['command'] is String) tool.command = input['command'] as String;
    if (u['content'] is List) {
      tool.content = [
        for (final c in (u['content'] as List).whereType<Map>())
          if (c['type'] == 'diff' && c['path'] is String && c['newText'] is String)
            ToolDiff(c['path'] as String, c['oldText'] as String?, c['newText'] as String)
          else if (_text(c['content']) case final String text when c['type'] == 'content')
            ToolText(text),
      ];
    }
    if (u['locations'] is List) {
      tool.paths = [
        for (final l in (u['locations'] as List).whereType<Map>())
          if (l['path'] is String) l['path'] as String,
      ];
    }
    return tool;
  }

  void _plan(Object? raw) {
    if (raw is! List) return;
    final steps = [
      for (final e in raw.whereType<Map>())
        if (e['content'] is String)
          (
            e['content'] as String,
            switch (e['status']) {
              'in_progress' => PlanStatus.running,
              'completed' => PlanStatus.done,
              _ => PlanStatus.pending,
            }
          ),
    ];
    // One plan per turn, updated in place.
    final lastUser = entries.lastIndexWhere((e) => e is UserEntry);
    final existing = entries.skip(lastUser + 1).whereType<PlanEntry>().lastOrNull;
    (existing ?? (PlanEntry(_nextEntry++)..let(entries.add))).steps = steps;
  }

  Future<Object?> _onRequest(String method, AcpParams params) {
    if (method != 'session/request_permission') {
      return Future.error(const AcpError(AcpError.methodNotFound, 'Not supported'));
    }
    final call = params['toolCall'];
    final tool = call is Map ? _tool(call.cast<String, Object?>()) : null;
    final choices = [
      for (final o in (params['options'] as List? ?? const []).whereType<Map>())
        if (o['optionId'] is String)
          PermissionChoice(o['optionId'] as String, (o['name'] as String?) ?? o['optionId'] as String,
              (o['kind'] as String?) ?? 'allow_once'),
    ];
    final answer = Completer<Object?>();
    permissions.add(PermissionRequest(tool, choices, answer));
    _changed();
    return answer.future;
  }

  // ---- Change notification, at most once a frame ----------------------------

  Timer? _notify;

  void _changed() {
    if (_disposed) return;
    _notify ??= Timer(const Duration(milliseconds: 16), () {
      _notify = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _notify?.cancel();
    _cancelPermissions();
    _connection?.close();
    super.dispose();
  }
}

extension _Let<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
