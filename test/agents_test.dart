import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/agents/agent_catalog.dart';
import 'package:aiterm/agents/agent_installer.dart';
import 'package:aiterm/linux/shell_profile.dart';

void main() {
  group('catalog', () {
    AgentRecipe byId(String id) => agentCatalog.firstWhere((a) => a.id == id);

    test('Claude Code, Gemini CLI and Codex CLI are offered', () {
      expect(agentCatalog.map((a) => a.id), ['claude', 'gemini', 'codex']);
    });

    test('Claude Code gets what its native musl build and tools need', () {
      final c = byId('claude');
      expect(c.packages, containsAll(['bash', 'curl', 'git', 'libgcc', 'libstdc++', 'ripgrep', 'ca-certificates']));
      expect(c.steps.last.script, contains('claude.ai/install.sh'));
      expect(c.command, 'claude');
    });

    test('npm-based agents get Node.js', () {
      for (final id in ['gemini', 'codex']) {
        expect(byId(id).packages, containsAll(['nodejs', 'npm', 'git', 'bash']), reason: id);
      }
      expect(byId('gemini').steps.last.script, contains('@google/gemini-cli'));
      expect(byId('codex').steps.last.script, contains('@openai/codex'));
    });

    test('every step stops at the first error and dependencies come first', () {
      for (final a in agentCatalog) {
        expect(a.steps.first.script, contains('apk add'), reason: a.id);
        for (final s in a.steps) {
          expect(s.script, startsWith('set -e'), reason: '${a.id}: ${s.label}');
        }
      }
    });
  });

  test('~/.local/bin is on PATH (where native installers put binaries)', () {
    expect(shellProfile, contains(r'$HOME/.local/bin'));
  });

  group('installer', () {
    late List<String> scripts;
    late List<(String, List<String>)> launched;
    late (String, int) Function(String) respond;

    AgentInstaller make() => AgentInstaller(
          run: (script, onOutput) async {
            scripts.add(script);
            final (out, code) = respond(script);
            for (final line in out.split('\n')) {
              if (line.isNotEmpty) onOutput(line);
            }
            return code;
          },
          launch: (title, commands) => launched.add((title, commands)),
        );

    setUp(() {
      scripts = [];
      launched = [];
      respond = (_) => ('', 0);
    });

    test('detects what is installed', () async {
      respond = (s) => s.contains('command -v') ? ('claude\ncodex\n', 0) : ('', 0);
      final i = make();
      await i.refresh();
      expect(i.stateOf('claude').status, AgentStatus.installed);
      expect(i.stateOf('codex').status, AgentStatus.installed);
      expect(i.stateOf('gemini').status, AgentStatus.notInstalled);
    });

    test('one tap runs every step with progress, then shows it installed', () async {
      final i = make();
      final labels = <String>[];
      i.addListener(() {
        final s = i.stateOf('claude');
        if (s.status == AgentStatus.installing && (labels.isEmpty || labels.last != s.step)) labels.add(s.step!);
      });
      respond = (s) => s.contains('command -v') ? ('claude\n', 0) : ('ok\n', 0);
      await i.install('claude');
      expect(labels, agentCatalog.first.steps.map((s) => s.label).toList());
      expect(i.stateOf('claude').status, AgentStatus.installed);
    });

    test('a failing step reports why and keeps the log', () async {
      respond = (s) => s.contains('apk add') ? ('fetch https://dl-cdn.alpinelinux.org\nERROR: network unreachable\n', 1) : ('', 0);
      final i = make();
      await i.install('gemini');
      final s = i.stateOf('gemini');
      expect(s.status, AgentStatus.failed);
      expect(s.message, contains('network unreachable'));
      expect(s.log, contains('fetch https://dl-cdn.alpinelinux.org'));
    });

    test('only one install runs at a time', () async {
      final i = make();
      final first = i.install('claude');
      expect(i.busy, isTrue);
      await i.install('codex'); // ignored while busy
      await first;
      expect(scripts.where((s) => s.contains('@openai/codex')), isEmpty);
    });

    test('open starts the agent in its own tab; login happens there', () {
      final i = make();
      i.open('claude');
      expect(launched.single.$1, 'Claude Code');
      expect(launched.single.$2, ['claude']);
    });
  });

  test('the install scripts are valid shell', () async {
    final sh = File('/bin/sh').existsSync() ? '/bin/sh' : null;
    if (sh == null) return;
    for (final a in agentCatalog) {
      for (final s in a.steps) {
        final r = await Process.run(sh, ['-n', '-c', s.script]);
        expect(r.exitCode, 0, reason: '${a.id}/${s.label}: ${r.stderr}');
      }
    }
  });
}
