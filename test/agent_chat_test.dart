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
      // Questions (AskUserQuestion) come as forms.
      'elicitation': {'form': {}},
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

  test('New chat reuses the running agent: no restart, the old session closed', () async {
    var starts = 0, sessions = 0;
    final agent = FakeAgent((a, method, p) => switch (method) {
          'initialize' => {
              'protocolVersion': 1,
              'agentCapabilities': {
                'sessionCapabilities': {'close': {}},
              },
            },
          'session/new' => {'sessionId': 's${++sessions}'},
          'session/close' => {},
          _ => null,
        });
    final c = AgentChat(
      agent: AcpAgent.of('claude')!,
      name: 'Claude Code',
      cwd: '/root/app',
      start: (a, cwd) async {
        starts++;
        return agent;
      },
      prepare: (a, o) async => null,
      sessions: MemorySessions(),
    );
    await c.start();
    c.entries.add(UserEntry(99, 'old'));
    await c.restart();
    expect(starts, 1);
    expect(c.entries, isEmpty);
    expect(c.state, ChatState.ready);
    final close = agent.sent.firstWhere((m) => m['method'] == 'session/close');
    expect(close['params'], {'sessionId': 's1'});
    // Updates from the old session no longer land here.
    agent.update('s1', {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'late'}});
    await settle();
    expect(c.entries, isEmpty);
  });

  test('a message sent while the agent starts shows at once and goes out when it is up', () async {
    final ready = Completer<void>();
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          await ready.future;
          return {'sessionId': 's1'};
        case 'session/prompt':
          a.update('s1', {'sessionUpdate': 'agent_message_chunk', 'content': {'type': 'text', 'text': 'Hi'}});
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
    final c = chat(agent);
    final starting = c.start();
    await settle();
    expect(c.state, ChatState.starting);
    expect(c.accepting, isTrue);
    await c.send('Hello');
    expect(c.entries.single, isA<UserEntry>());
    expect(c.busy, isTrue); // shows Stop, not Send
    expect(agent.sentMethod('session/prompt'), isFalse);
    ready.complete();
    await starting;
    await settle();
    expect(agent.sentMethod('session/prompt'), isTrue);
    expect((c.entries.last as MessageEntry).text.toString(), 'Hi');
    expect(c.busy, isFalse);
  });

  test('attachments: images inline when the agent takes them, other files as links; the folder is granted', () async {
    for (final images in [true, false]) {
      final agent = FakeAgent((a, method, p) => switch (method) {
            'initialize' => {
                'protocolVersion': 1,
                'agentCapabilities': {
                  'promptCapabilities': {'image': images},
                  'sessionCapabilities': {'additionalDirectories': {}},
                },
              },
            'session/new' => {'sessionId': 's1'},
            'session/prompt' => {'stopReason': 'end_turn'},
            _ => null,
          });
      final c = AgentChat(
        agent: AcpAgent.of('claude')!,
        name: 'Claude Code',
        cwd: '/root/app',
        start: (a, cwd) async => agent,
        prepare: (a, o) async => null,
        sessions: MemorySessions(),
        attachmentsDir: '/root/.cache/aiterm/attachments',
      );
      await c.start();
      const shot = ChatAttachment(
          name: 'shot.png', path: '/root/.cache/aiterm/attachments/shot.png', hostPath: '/x/shot.png', imageData: 'AAAA', mimeType: 'image/png');
      const doc = ChatAttachment(
          name: 'spec v2.pdf', path: '/root/.cache/aiterm/attachments/spec v2.pdf', hostPath: '/x/spec.pdf', mimeType: 'application/pdf');
      await c.send('Use these', attachments: [shot, doc]);
      final session = agent.sent.firstWhere((m) => m['method'] == 'session/new');
      expect((session['params'] as Map)['additionalDirectories'], ['/root/.cache/aiterm/attachments']);
      final prompt = ((agent.sent.firstWhere((m) => m['method'] == 'session/prompt')['params'] as Map)['prompt'] as List);
      expect(prompt.first, {'type': 'text', 'text': 'Use these'});
      expect(prompt[1], images
          ? {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'}
          : {'type': 'resource_link', 'uri': 'file:///root/.cache/aiterm/attachments/shot.png', 'name': 'shot.png', 'mimeType': 'image/png'});
      expect(prompt[2], {
        'type': 'resource_link',
        'uri': 'file:///root/.cache/aiterm/attachments/spec%20v2.pdf',
        'name': 'spec v2.pdf',
        'mimeType': 'application/pdf',
      });
      expect((c.entries.first as UserEntry).attachments, hasLength(2));
    }
  });

  test('questions arrive as forms; the answer (or Skip) goes back', () async {
    final answers = <Map<String, Object?>>[];
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          return {'sessionId': 's1'};
        case 'session/prompt':
          for (var i = 0; i < 2; i++) {
            answers.add(await a.ask('elicitation/create', {
              'mode': 'form',
              'sessionId': 's1',
              'message': 'Which database?',
              'requestedSchema': {
                'type': 'object',
                'properties': {
                  'question_0': {
                    'type': 'string',
                    'oneOf': [
                      {'const': 'Postgres', 'title': 'Postgres', 'description': 'Relational'},
                      {'const': 'SQLite', 'title': 'SQLite'},
                    ],
                  },
                  'question_0_custom': {'type': 'string', 'title': 'Other'},
                },
              },
            }));
          }
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    final turn = c.send('Set up storage');
    await settle();
    final q = c.asks.single as QuestionRequest;
    expect(q.message, 'Which database?');
    expect(q.fields.map((f) => f.kind), [AskFieldKind.single, AskFieldKind.text]);
    expect(q.fields.first.options, [('Postgres', 'Postgres', 'Relational'), ('SQLite', 'SQLite', null)]);
    c.answerQuestion(q, {'question_0': 'SQLite'});
    await settle();
    c.skipQuestion(c.questions.single);
    await turn;
    expect(answers, [
      {'action': 'accept', 'content': {'question_0': 'SQLite'}},
      {'action': 'decline'},
    ]);
    expect(c.asks, isEmpty);
  });

  test('permission choices keep the agent\'s order (some safety checks lead with No)', () async {
    final agent = FakeAgent((a, method, p) async {
      switch (method) {
        case 'initialize':
          return init();
        case 'session/new':
          return {'sessionId': 's1'};
        case 'session/prompt':
          await a.ask('session/request_permission', {
            'sessionId': 's1',
            'toolCall': {'toolCallId': 't1', 'title': 'rm -rf node_modules', 'kind': 'execute'},
            'options': [
              {'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
              {'optionId': 'yes', 'name': 'Yes', 'kind': 'allow_once'},
            ],
          });
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
    final c = chat(agent);
    await c.start();
    final turn = c.send('Clean up');
    await settle();
    expect(c.permissions.single.choices.map((o) => o.name), ['No', 'Yes']);
    c.answer(c.permissions.single, c.permissions.single.choices.first);
    await turn;
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
