import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/onboarding/setup_pipeline.dart';

void main() {
  late List<String> ran;
  late bool linux;
  late Map<String, String?> failures; // step id → error
  late SetupPipeline p;

  SetupPipeline make() => SetupPipeline(
        installLinux: (progress) async {
          ran.add('linux');
          progress('Downloading', 0.5);
          if (failures['linux'] case final e?) throw Exception(e);
          linux = true;
        },
        linuxReady: () => linux,
        installTools: () async {
          ran.add('tools');
          return failures['tools'];
        },
        installAgent: (id) async {
          ran.add(id);
          return failures[id];
        },
        agentName: (id) => id.toUpperCase(),
      );

  setUp(() {
    ran = [];
    linux = false;
    failures = {};
    p = make();
  });

  test('runs Linux, then git tools, then each chosen agent, in order, in one go', () async {
    expect(p.active, isFalse);
    final run = p.start(['claude', 'codex']);
    expect(p.active, isTrue);
    await run;
    expect(ran, ['linux', 'tools', 'claude', 'codex']);
    expect(p.steps.map((s) => s.label), ['Linux system', 'Git and GitHub tools', 'CLAUDE', 'CODEX']);
    expect(p.steps.every((s) => s.state == SetupState.done), isTrue);
    expect(p.active, isFalse); // all done: the app moves on
  });

  test('Linux already installed is not installed again', () async {
    linux = true;
    await p.start(['claude']);
    expect(ran, ['tools', 'claude']);
    expect(p.steps.first.state, SetupState.done);
  });

  test('progress of the running step is shown', () async {
    final seen = <String?>[];
    p.addListener(() => seen.add(p.steps.firstOrNull?.detail));
    await p.start([]);
    expect(seen, contains('Downloading'));
  });

  test('a Linux failure stops everything after it; retry continues from there', () async {
    failures['linux'] = 'network unreachable';
    await p.start(['claude']);
    expect(ran, ['linux']);
    expect(p.steps[0].state, SetupState.failed);
    expect(p.steps[0].error, contains('network unreachable'));
    expect(p.steps[1].state, SetupState.waiting);
    expect(p.active, isTrue); // stays on screen to retry

    failures.clear();
    await p.retry();
    expect(ran, ['linux', 'linux', 'tools', 'claude']);
    expect(p.active, isFalse);
  });

  test('an agent failure does not block the others; retry runs only what failed', () async {
    failures['claude'] = 'npm ERR';
    await p.start(['claude', 'gemini']);
    expect(ran, ['linux', 'tools', 'claude', 'gemini']);
    expect(p.steps[2].state, SetupState.failed);
    expect(p.steps[3].state, SetupState.done);
    expect(p.active, isTrue);

    failures.clear();
    await p.retry();
    expect(ran.skip(4), ['claude']);
    expect(p.active, isFalse);
  });

  test('continue without the failed parts leaves setup', () async {
    failures['tools'] = 'apk failed';
    await p.start(['claude']);
    expect(p.canSkip, isTrue);
    p.skip();
    expect(p.active, isFalse);
  });

  test('cannot continue without Linux', () async {
    failures['linux'] = 'x';
    await p.start([]);
    expect(p.canSkip, isFalse);
  });
}
