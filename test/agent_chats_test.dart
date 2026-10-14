import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/agents/acp/acp_agents.dart';
import 'package:aiterm/agents/acp/agent_chat.dart';
import 'package:aiterm/agents/acp/agent_chats.dart';
import 'agent_chat_test.dart' show FakeAgent;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chats'));
  tearDown(() => dir.deleteSync(recursive: true));

  AgentChats registry(List<String> started) {
    late AgentChats chats;
    chats = AgentChats(File('${dir.path}/agent_sessions.json'), (agent, cwd) {
      return AgentChat(
        agent: AcpAgent.of(agent)!,
        name: agent,
        cwd: cwd,
        start: (a, cwd) async {
          started.add('${a.id}@$cwd');
          return FakeAgent((f, method, p) => switch (method) {
                'initialize' => {'protocolVersion': 1, 'agentCapabilities': {}},
                'session/new' => {'sessionId': 'S-$agent'},
                _ => null,
              });
        },
        prepare: (a, o) async => null,
        sessions: chats,
      );
    });
    return chats;
  }

  test('one chat per agent per project; reopening goes back to it without restarting', () async {
    final started = <String>[];
    final chats = registry(started);
    final a = chats.open('claude', '/root/app');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(chats.open('claude', '/root/app'), same(a));
    chats.open('gemini', '/root/app');
    chats.open('claude', '/root/site');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(started, ['claude@/root/app', 'gemini@/root/app', 'claude@/root/site']);
    expect(chats.inProject('/root/app').map((c) => c.agent.id), ['claude', 'gemini']);
    expect(chats.active('/root/app')!.agent.id, 'gemini'); // the latest opened shows
    chats.select(a);
    expect(chats.active('/root/app'), same(a));
  });

  test('sessions are remembered across restarts; the view follows what opened last', () async {
    final chats = registry([]);
    chats.open('claude', '/root/app');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await chats.saved;
    expect(chats.viewOf('/root/app'), AgentView.blocks);
    chats.show('/root/app', AgentView.terminal);
    expect(chats.viewOf('/root/app'), AgentView.terminal);

    final again = registry([]);
    await again.load();
    expect(again.sessionFor('claude', '/root/app'), 'S-claude');
  });
}
