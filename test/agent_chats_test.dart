import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/agents/acp/acp_agents.dart';
import 'package:aiterm/agents/acp/acp_host.dart';
import 'package:aiterm/agents/acp/agent_chat.dart';
import 'package:aiterm/agents/acp/agent_chats.dart';
import 'agent_chat_test.dart' show FakeAgent;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chats'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Each agent process numbers its sessions; `session/list` returns two
  /// past chats; a prompt answers with which session it ran in.
  FakeAgent agent(String id) {
    var sessions = 0;
    return FakeAgent((f, method, p) async {
      switch (method) {
        case 'initialize':
          return {
            'protocolVersion': 1,
            'agentCapabilities': {
              'loadSession': true,
              'sessionCapabilities': {'list': {}, 'close': {}},
            },
          };
        case 'session/new':
          return {'sessionId': '$id-${++sessions}'};
        case 'session/load':
          return {};
        case 'session/close':
          return {};
        case 'session/list':
          return {
            'sessions': [
              {'sessionId': 'old-1', 'cwd': p['cwd'], 'title': 'Fix the login bug', 'updatedAt': '2026-10-10T09:00:00Z'},
              {'sessionId': 'old-2', 'cwd': p['cwd'], 'title': 'Add dark mode', 'updatedAt': '2026-10-14T09:00:00Z'},
            ],
          };
        case 'session/prompt':
          f.update(p['sessionId'] as String, {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'in ${p['sessionId']}'},
          });
          return {'stopReason': 'end_turn'};
      }
      return null;
    });
  }

  AgentChats registry(List<String> started, {List<FakeAgent>? processes}) {
    late AgentChats chats;
    chats = AgentChats(
      File('${dir.path}/agent_sessions.json'),
      host: (id, cwd) => AcpHost(
        agent: AcpAgent.of(id)!,
        cwd: cwd,
        start: (a, cwd) async {
          started.add('${a.id}@$cwd');
          final p = agent(a.id);
          processes?.add(p);
          return p;
        },
        prepare: (a, o) async => null,
      ),
      chat: (id, cwd, host, number) => AgentChat(
        agent: host.agent,
        name: number == 1 ? id : '$id $number',
        cwd: cwd,
        host: host,
        sessions: chats,
        remembers: number == 1,
      ),
    );
    return chats;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

  test('reopening an agent goes back to its chat; other agents and folders get their own', () async {
    final started = <String>[];
    final chats = registry(started);
    final a = chats.open('claude', '/root/app');
    await settle();
    expect(chats.open('claude', '/root/app'), same(a));
    chats.open('gemini', '/root/app');
    chats.open('claude', '/root/site');
    await settle();
    expect(started, ['claude@/root/app', 'gemini@/root/app', 'claude@/root/site']);
    expect(chats.inProject('/root/app').map((c) => c.agent.id), ['claude', 'gemini']);
    expect(chats.active('/root/app')!.agent.id, 'gemini');
    chats.select(a);
    expect(chats.active('/root/app'), same(a));
  });

  test('several chats with one agent share its process, each with its own session', () async {
    final started = <String>[];
    final chats = registry(started);
    final first = chats.open('claude', '/root/app');
    await settle();
    final second = chats.open('claude', '/root/app', fresh: true);
    await settle();
    expect(started, ['claude@/root/app'], reason: 'one agent process');
    expect([first.name, second.name], ['claude', 'claude 2']);
    expect([first.sessionId, second.sessionId], ['claude-1', 'claude-2']);
    // Updates land in their own chat.
    await second.send('hi');
    await first.send('hello');
    await settle();
    expect((second.entries.last as MessageEntry).text.toString(), 'in claude-2');
    expect((first.entries.last as MessageEntry).text.toString(), 'in claude-1');
    // Only the first chat keeps the remembered session.
    await chats.saved;
    expect(chats.sessionFor('claude', '/root/app'), 'claude-1');
    // Closing frees its number; the process stays while a chat uses it.
    chats.close(second);
    expect(chats.open('claude', '/root/app', fresh: true).name, 'claude 2');
  });

  test('history lists past chats newest first; one opens in its own chat, or goes to it', () async {
    final started = <String>[];
    final processes = <FakeAgent>[];
    final chats = registry(started, processes: processes);
    final history = await chats.history('claude', '/root/app');
    expect(history!.map((c) => c.title), ['Add dark mode', 'Fix the login bug']);
    // Listing alone didn't leave the agent running.
    expect(chats.inProject('/root/app'), isEmpty);
    final opened = chats.open('claude', '/root/app', session: 'old-1');
    await settle();
    expect(opened.sessionId, 'old-1');
    expect(processes.last.sent.any((m) => m['method'] == 'session/load' && (m['params'] as Map)['sessionId'] == 'old-1'),
        isTrue);
    expect(chats.open('claude', '/root/app', session: 'old-1'), same(opened));
    expect(chats.showing('/root/app', 'old-1'), same(opened));
  });

  test('sessions are remembered across restarts; the view follows what opened last', () async {
    final chats = registry([]);
    chats.open('claude', '/root/app');
    await settle();
    await chats.saved;
    expect(chats.viewOf('/root/app'), AgentView.blocks);
    chats.show('/root/app', AgentView.terminal);
    expect(chats.viewOf('/root/app'), AgentView.terminal);
    final again = registry([]);
    await again.load();
    expect(again.sessionFor('claude', '/root/app'), 'claude-1');
  });
}
