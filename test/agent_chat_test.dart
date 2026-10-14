import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/agents/acp/acp_agents.dart';
import 'package:aiterm/agents/acp/acp_connection.dart';
import 'package:aiterm/agents/acp/agent_chat.dart';

/// A scripted ACP agent: [onRequest] answers the client's requests (and may
/// push updates first); everything the client sent is kept.
class FakeAgent implements AcpTransport {
  FakeAgent(this.onRequest);

  final FutureOr<Object?> Function(FakeAgent agent, String method, Map<String, Object?> params) onRequest;
  final _out = StreamController<String>();
  final _exit = Completer<int>();
  final sent = <Map<String, Object?>>[];
  final _clientAnswers = <int, Completer<Map<String, Object?>>>{};
  var _nextId = 1000;

  @override
  String log = '';

  @override
  Stream<String> get lines => _out.stream;

  @override
  void send(String line) {
    final m = jsonDecode(line) as Map<String, Object?>;
    sent.add(m);
    if (m['method'] != null && m['id'] != null) {
      Future(() async {
        try {
          final result = await onRequest(this, m['method'] as String, (m['params'] as Map).cast());
          _push({'jsonrpc': '2.0', 'id': m['id'], 'result': result});
        } on AcpError catch (e) {
          _push({'jsonrpc': '2.0', 'id': m['id'], 'error': {'code': e.code, 'message': e.message}});
        }
      });
    } else if (m['method'] == null && m['id'] is int) {
      _clientAnswers.remove(m['id'])?.complete((m['result'] as Map).cast());
    }
  }

  void _push(Map<String, Object?> m) => _out.add(jsonEncode(m));

  void update(String sessionId, Map<String, Object?> update) => _push({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'sessionId': sessionId, 'update': update},
      });

  /// Asks the client something; completes with its answer.
  Future<Map<String, Object?>> ask(String method, Map<String, Object?> params) {
    final id = _nextId++;
    final done = Completer<Map<String, Object?>>();
    _clientAnswers[id] = done;
    _push({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return done.future;
  }

  bool sentMethod(String method) => sent.any((m) => m['method'] == method);

  void exit(int code) {
    _out.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    if (!_exit.isCompleted) exit(-9);
  }
}

class MemorySessions implements ChatSessions {
  final saved = <String, String>{};
  @override
  String? sessionFor(String agent, String cwd) => saved['$agent:$cwd'];
  @override
  void remember(String agent, String cwd, String? sessionId) =>
      sessionId == null ? saved.remove('$agent:$cwd') : saved['$agent:$cwd'] = sessionId;
}

Map<String, Object?> init({bool loadSession = false}) => {
      'protocolVersion': 1,
      'agentCapabilities': {'loadSession': loadSession},
      'authMethods': [],
    };

const claudeOptions = {
  'sessionId': 's1',
  'configOptions': [
    {
      'id': 'mode',
      'name': 'Mode',
      'type': 'select',
      'currentValue': 'default',
      'options': [
        {'value': 'default', 'name': 'Manual'},
        {'value': 'acceptEdits', 'name': 'Accept edits'},
      ],
    },
    {
      'id': 'model',
      'name': 'Model',
      'type': 'select',
      'currentValue': 'opus',
      'options': [
        {'value': 'opus', 'name': 'Opus'},
        {'value': 'sonnet', 'name': 'Sonnet'},
      ],
    },
  ],
};

void main() {
  late MemorySessions sessions;
  setUp(() => sessions = MemorySessions());

  AgentChat chat(FakeAgent agent, {Map<String, String> preferred = const {}, String? prepareError, List<String>? chosen}) =>
      AgentChat(
        agent: AcpAgent.of('claude')!,
        name: 'Claude Code',
        cwd: '/root/app',
        start: (a, cwd) async => agent,
        prepare: (a, onOutput) async {
          onOutput('added 30 packages');
          return prepareError;
        },
        sessions: sessions,
        preferred: preferred,
        onOptionChosen: (option, value) => chosen?.add('$option=$value'),
      );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

  test('starts a session, reads its modes and models, applies the remembered choice', () async {
    final agent = FakeAgent((a, method, p) => switch (method) {
          'initialize' => init(),
          'session/new' => claudeOptions,
          'session/set_config_option' => {},
          _ => throw const AcpError(AcpError.methodNotFound, 'no'),
        });
    final c = chat(agent, preferred: {'mode': 'acceptEdits'});
    await c.start();
    await settle();
    expect(c.state, ChatState.ready);
    expect(c.options.map((o) => '${o.id}:${o.valueName}'), ['mode:Accept edits', 'model:Opus']);
    final set = agent.sent.firstWhere((m) => m['method'] == 'session/set_config_option');
    expect(set['params'], {'sessionId': 's1', 'configId': 'mode', 'value': 'acceptEdits'});
    expect(sessions.saved['claude:/root/app'], 's1');
    // The client asks for no files or terminals: agents use their own tools.
    final initialize = agent.sent.firstWhere((m) => m['method'] == 'initialize');
    expect((initialize['params'] as Map)['clientCapabilities'], {
      'fs': {'readTextFile': false, 'writeTextFile': false},
      'terminal': false,
    });
  });

  test('a turn streams into one message, tool calls with commands and diffs, and a plan', () async {
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          return {'sessionId': 's1'};
        case 'session/prompt':
          a.update('s1', {
            'sessionUpdate': 'plan',
            'entries': [
              {'content': 'Read the code', 'priority': 'high', 'status': 'completed'},
              {'content': 'Add the view', 'priority': 'high', 'status': 'in_progress'},
            ],
          });
          a.update('s1', {'sessionUpdate': 'tool_call', 'toolCallId': 't1', 'title': 'Terminal', 'kind': 'execute', 'status': 'pending'});
          a.update('s1', {'sessionUpdate': 'tool_call_update', 'toolCallId': 't1', 'title': 'npm test', 'rawInput': {'command': 'npm test'}});
          a.update('s1', {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 't1',
            'status': 'completed',
            'content': [
              {'type': 'content', 'content': {'type': 'text', 'text': '3 passing'}},
            ],
          });
          a.update('s1', {
            'sessionUpdate': 'tool_call',
            'toolCallId': 't2',
            'title': 'Edit lib/app.dart',
            'kind': 'edit',
            'status': 'completed',
            'content': [
              {'type': 'diff', 'path': '/root/app/lib/app.dart', 'oldText': 'a\n', 'newText': 'b\n'},
            ],
            'locations': [
              {'path': '/root/app/lib/app.dart'},
            ],
          });
          a.update('s1', {'sessionUpdate': 'agent_message_chunk', 'messageId': 'm1', 'content': {'type': 'text', 'text': 'Done: '}});
          a.update('s1', {'sessionUpdate': 'agent_message_chunk', 'messageId': 'm1', 'content': {'type': 'text', 'text': 'tests pass.'}});
          a.update('s1', {'sessionUpdate': 'usage_update', 'used': 10, 'size': 100}); // ignored
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    await c.send('Add a forecast view');
    await settle();
    expect(c.state, ChatState.ready);
    expect(c.entries.map((e) => e.runtimeType), [UserEntry, PlanEntry, ToolEntry, ToolEntry, MessageEntry]);
    final plan = c.entries[1] as PlanEntry;
    expect(plan.steps, [('Read the code', PlanStatus.done), ('Add the view', PlanStatus.running)]);
    final run = c.entries[2] as ToolEntry;
    expect([run.title, run.command, run.kind, run.status], ['npm test', 'npm test', ToolKind.execute, ToolStatus.done]);
    expect((run.content.single as ToolText).text, '3 passing');
    final edit = c.entries[3] as ToolEntry;
    final diff = edit.content.single as ToolDiff;
    expect([diff.path, diff.oldText, diff.newText], ['/root/app/lib/app.dart', 'a\n', 'b\n']);
    expect(edit.paths, ['/root/app/lib/app.dart']);
    expect((c.entries[4] as MessageEntry).text.toString(), 'Done: tests pass.');
  });

  test('permission requests wait for an answer, which goes back to the agent', () async {
    Map<String, Object?>? answered;
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          return {'sessionId': 's1'};
        case 'session/prompt':
          answered = await a.ask('session/request_permission', {
            'sessionId': 's1',
            'toolCall': {'toolCallId': 't1', 'title': 'rm -rf build', 'kind': 'execute'},
            'options': [
              {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
              {'optionId': 'no', 'name': 'Reject', 'kind': 'reject_once'},
            ],
          });
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    final turn = c.send('Clean the build');
    await settle();
    expect(c.permissions, hasLength(1));
    final request = c.permissions.single;
    expect(request.tool?.title, 'rm -rf build');
    expect(request.choices.map((o) => (o.name, o.allows)), [('Allow', true), ('Reject', false)]);
    c.answer(request, request.choices.first);
    await turn;
    expect(answered, {
      'outcome': {'outcome': 'selected', 'optionId': 'yes'},
    });
    expect(c.permissions, isEmpty);
  });

  test('Stop cancels the turn and any open permission request', () async {
    Map<String, Object?>? answered;
    final prompt = Completer<Map<String, Object?>>();
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          return {'sessionId': 's1'};
        case 'session/prompt':
          a.update('s1', {'sessionUpdate': 'tool_call', 'toolCallId': 't1', 'title': 'Terminal', 'status': 'in_progress'});
          a.ask('session/request_permission', {
            'sessionId': 's1',
            'toolCall': {'toolCallId': 't1'},
            'options': [
              {'optionId': 'yes', 'name': 'Allow', 'kind': 'allow_once'},
            ],
          }).then((r) {
            answered = r;
            prompt.complete({'stopReason': 'cancelled'});
          });
          return prompt.future;
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    final turn = c.send('Do something long');
    await settle();
    c.cancel();
    await turn;
    expect(agent.sentMethod('session/cancel'), isTrue);
    expect(answered, {
      'outcome': {'outcome': 'cancelled'},
    });
    expect(c.entries.whereType<NoticeEntry>().single.text, 'Stopped.');
    // A tool the agent never closed stops spinning.
    expect(c.entries.whereType<ToolEntry>().single.status, ToolStatus.failed);
    expect(c.state, ChatState.ready);
  });

  test('an agent that needs signing in says so', () async {
    final agent = FakeAgent((a, method, p) => switch (method) {
          'initialize' => init(),
          'session/new' => throw const AcpError(AcpError.authRequired, 'Authentication required'),
          _ => null,
        });
    final c = chat(agent);
    await c.start();
    expect(c.state, ChatState.signedOut);
  });

  test('picks up the remembered session, replaying it', () async {
    sessions.saved['claude:/root/app'] = 'old';
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init(loadSession: true);
        case 'session/load':
          a.update('old', {'sessionUpdate': 'user_message_chunk', 'content': {'type': 'text', 'text': 'Earlier question'}});
          a.update('old', {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Earlier answer'}});
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return {};
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    await settle();
    expect(agent.sentMethod('session/new'), isFalse);
    expect(c.entries.map((e) => e.runtimeType), [UserEntry, MessageEntry]);
    expect((c.entries.first as UserEntry).text, 'Earlier question');
    // New chat forgets it.
    await c.restart();
    expect(sessions.saved['claude:/root/app'], isNot('old'));
  });

  test('an agent that exits, or an adapter that will not install, fails with the reason', () async {
    final agent = FakeAgent((a, method, p) => switch (method) {
          'initialize' => init(),
          'session/new' => {'sessionId': 's1'},
          _ => null,
        });
    final c = chat(agent);
    await c.start();
    agent.log = 'starting\nError: Claude Code not found';
    agent.exit(1);
    await settle();
    expect(c.state, ChatState.failed);
    expect(c.detail, 'Error: Claude Code not found');

    final broken = chat(FakeAgent((a, m, p) => null), prepareError: 'npm ERR! network');
    await broken.start();
    expect(broken.state, ChatState.failed);
    expect(broken.detail, 'npm ERR! network');
  });
}
