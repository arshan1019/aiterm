import 'dart:async';
import 'package:flutter/foundation.dart';
import 'acp_agents.dart';
import 'acp_connection.dart';
import 'acp_host.dart';

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

/// Something the agent is waiting on you for, oldest first ([seq]).
sealed class AgentAsk {
  AgentAsk(this.seq, this._answer);
  final int seq;
  final Completer<Object?> _answer;
}

/// The agent asks before a tool call runs.
class PermissionRequest extends AgentAsk {
  PermissionRequest(this.tool, this.choices, Completer<Object?> answer, {int seq = 0}) : super(seq, answer);
  final ToolEntry? tool;

  /// In the agent's order: its preferred answer first (some safety checks
  /// lead with No).
  final List<PermissionChoice> choices;
}

enum AskFieldKind { single, multi, text }

/// One question in an agent's form (ACP elicitation): pick one, pick
/// several, or type.
class AskField {
  const AskField(this.key, this.kind, {this.title, this.description, this.options = const []});
  final String key;
  final AskFieldKind kind;
  final String? title;
  final String? description;

  /// (value, label, description).
  final List<(String, String, String?)> options;
}

/// The agent asks you something (Claude's AskUserQuestion): a message and
/// fields; nothing is required, so Skip is always fine.
class QuestionRequest extends AgentAsk {
  QuestionRequest(this.message, this.fields, Completer<Object?> answer, {required int seq}) : super(seq, answer);
  final String message;
  final List<AskField> fields;

  /// Parses an ACP form's `requestedSchema` (an object of properties).
  static List<AskField> fieldsOf(Object? schema) {
    final props = schema is Map ? schema['properties'] : null;
    if (props is! Map) return const [];
    List<(String, String, String?)> options(Object? list) => [
          for (final o in (list is List ? list : const []).whereType<Map>())
            if (o['const'] != null)
              ('${o['const']}', (o['title'] as String?) ?? '${o['const']}', o['description'] as String?),
        ];
    return [
      for (final MapEntry(:key, :value) in props.entries)
        if (value is Map)
          switch (value) {
            {'type': 'array'} => AskField('$key', AskFieldKind.multi,
                title: value['title'] as String?,
                description: value['description'] as String?,
                options: options((value['items'] as Map?)?['anyOf'] ?? (value['items'] as Map?)?['oneOf'])),
            _ when value['oneOf'] is List || value['enum'] is List => AskField('$key', AskFieldKind.single,
                title: value['title'] as String?,
                description: value['description'] as String?,
                options: value['oneOf'] is List
                    ? options(value['oneOf'])
                    : [for (final e in value['enum'] as List) ('$e', '$e', null)]),
            _ => AskField('$key', AskFieldKind.text,
                title: value['title'] as String?, description: value['description'] as String?),
          },
    ];
  }
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

/// An agent as blocks: one ACP session in [cwd], turned into entries. The
/// agent process ([host]) may be shared with other chats in the folder.
class AgentChat extends ChangeNotifier implements AcpSessionHandler {
  AgentChat({
    required this.agent,
    required this.name,
    required this.cwd,
    AcpHost? host,
    AcpStarter? start,
    AcpPreparer? prepare,
    required this._sessions,
    this._preferred = const {},
    this._onOptionChosen,
    this.attachmentsDir,
    this.remembers = true,
  })  : host = host ?? AcpHost(agent: agent, cwd: cwd, start: start!, prepare: prepare!),
        _ownsHost = host == null;

  /// The agent process this chat's session runs on.
  final AcpHost host;
  final bool _ownsHost;

  /// This chat picks up (and keeps) the folder's remembered session; extra
  /// chats with the same agent start fresh.
  final bool remembers;

  /// Where attachments are copied (a guest path), granted to the session up
  /// front where the agent supports extra folders, so reading them asks
  /// nothing.
  final String? attachmentsDir;

  final AcpAgent agent;
  final String name;
  final String cwd;
  final ChatSessions _sessions;
  final Map<String, String> _preferred;
  final void Function(String option, String value)? _onOptionChosen;

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
  final questions = <QuestionRequest>[];
  var _askSeq = 0;

  /// Everything waiting on the user, oldest first.
  List<AgentAsk> get asks => [...permissions, ...questions]..sort((a, b) => a.seq.compareTo(b.seq));

  /// A message sent before the session was up, going out once it is.
  (String, List<ChatAttachment>)? _queued;

  /// A turn is running (or waiting for the session to go out).
  bool get busy => state == ChatState.working || _queued != null;

  /// The ACP session this chat is on (null while it opens one).
  String? get sessionId => _sessionId;

  /// The agent takes images inline (others get them as file links).
  bool get acceptsImages => (host.capabilities['promptCapabilities'] as Map?)?['image'] == true;

  /// The message box takes messages (queued while the agent starts).
  bool get accepting =>
      state == ChatState.ready || state == ChatState.working || state == ChatState.starting || state == ChatState.preparing;

  /// The session this chat opens; null: the remembered one (or a new one).
  String? _load;

  /// Starts the agent (or joins it, when another chat already runs it)
  /// and opens this chat's session: [load] (a past chat from History), or
  /// the remembered one.
  Future<void> start({String? load}) async {
    if (load != null) _load = load;
    state = ChatState.preparing;
    detail = null;
    _changed();
    try {
      await host.ensure(onProgress: (line) {
        detail = line;
        _changed();
      });
      if (_disposed) return;
      state = ChatState.starting;
      detail = null;
      _changed();
      await _openSession(resume: remembers || _load != null);
    } on AcpError catch (e) {
      if (e.code == AcpError.authRequired) {
        state = ChatState.signedOut;
        detail = e.message;
        _changed();
      } else {
        _fail(e.message);
      }
    } catch (e) {
      _fail(e is String ? e : '$e');
    }
  }

  @override
  void onUpdate(AcpParams params) => _onNotification('session/update', params);

  @override
  Future<Object?> onRequest(String method, AcpParams params) => _onRequest(method, params);

  @override
  void onHostExit(String reason) {
    if (!_disposed && state != ChatState.failed && state != ChatState.signedOut) _fail(reason);
  }

  /// Opens a session on the running agent: the remembered one when
  /// [resume] and the agent can load it, else a new one. Then sends any
  /// message typed meanwhile.
  Future<void> _openSession({required bool resume}) async {
    final saved = resume ? (_load ?? _sessions.sessionFor(agent.id, cwd)) : null;
    _load = null;
    final extra = attachmentsDir != null && host.can('additionalDirectories')
        ? {'additionalDirectories': [attachmentsDir]}
        : const <String, Object?>{};
    final session = await host.opening(this, () async {
      if (saved != null && host.capabilities['loadSession'] == true) {
        _sessionId = saved; // its replayed history arrives before the reply
        host.attach(saved, this);
        try {
          return await host.request('session/load', {'sessionId': saved, 'cwd': cwd, 'mcpServers': [], ...extra});
        } on AcpError catch (e) {
          host.detach(saved, this);
          if (e.code == AcpError.authRequired) rethrow;
          // Gone (or unreadable): start a new one.
        }
      }
      _sessionId = null;
      final created = await host.request('session/new', {'cwd': cwd, 'mcpServers': [], ...extra});
      _sessionId = created['sessionId'] as String?;
      if (_sessionId != null) host.attach(_sessionId!, this);
      return created;
    });
    if (_disposed) return;
    if (remembers) _sessions.remember(agent.id, cwd, _sessionId);
    _readOptions(session);
    state = ChatState.ready;
    _changed();
    await _applyPreferred();
    if (_queued case (final text, final files)?) {
      _queued = null;
      await _prompt(text, files);
    }
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
    final session = _sessionId;
    if (session == null) return;
    state = ChatState.working;
    _changed();
    try {
      final result = await host.request('session/prompt', {
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
    host.notify('session/cancel', {'sessionId': session});
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

  /// Answers [request]'s form with [content] (field key → value).
  void answerQuestion(QuestionRequest request, Map<String, Object?> content) {
    if (!questions.remove(request)) return;
    request._answer.complete({'action': 'accept', 'content': content});
    _changed();
  }

  /// Leaves [request] unanswered (the agent carries on without it).
  void skipQuestion(QuestionRequest request) {
    if (!questions.remove(request)) return;
    request._answer.complete({'action': 'decline'});
    _changed();
  }

  void _cancelPermissions() {
    for (final p in permissions) {
      p._answer.complete({
        'outcome': {'outcome': 'cancelled'},
      });
    }
    permissions.clear();
    for (final q in questions) {
      q._answer.complete({'action': 'cancel'});
    }
    questions.clear();
  }

  /// Picks [value] for [option] (mode or model), and remembers it.
  Future<void> choose(ChatOption option, String value) async {
    final session = _sessionId;
    if (session == null || option.value == value) return;
    try {
      if (option.legacyMode) {
        await host.request('session/set_mode', {'sessionId': session, 'modeId': value});
        _setOption(option.id, value);
      } else {
        final result = await host.request(
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
    final old = _sessionId;
    if (remembers) _sessions.remember(agent.id, cwd, null);
    entries.clear();
    _tools.clear();
    final wasBusy = busy;
    _cancelPermissions();
    _queued = null;
    if (!host.alive || state == ChatState.failed || state == ChatState.signedOut) return start();
    if (old != null) {
      if (wasBusy) host.notify('session/cancel', {'sessionId': old});
      _closeSession(old);
    }
    _sessionId = null;
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

  /// Lets go of session [id]; frees its agent process where the agent can.
  void _closeSession(String id) {
    host.detach(id, this);
    if (host.alive && host.can('close')) host.request('session/close', {'sessionId': id}).ignore();
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
    if (method == 'elicitation/create') {
      if (params['mode'] != 'form') return Future.value({'action': 'decline'});
      final answer = Completer<Object?>();
      questions.add(QuestionRequest((params['message'] as String?) ?? '', QuestionRequest.fieldsOf(params['requestedSchema']),
          answer,
          seq: _askSeq++));
      _changed();
      return answer.future;
    }
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
    permissions.add(PermissionRequest(tool, choices, answer, seq: _askSeq++));
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
    if (_sessionId case final id?) _closeSession(id);
    if (_ownsHost) host.dispose();
    super.dispose();
  }
}

extension _Let<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
