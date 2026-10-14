import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/github_auth.dart';
import 'package:aiterm/git/git_runner.dart';

/// gh's login, scripted: what it prints (and anything typed back).
class FakeGh implements InteractiveProcess {
  final _out = StreamController<String>();
  final typed = <String>[];
  final _exit = Completer<int>();

  void say(String text) => _out.add(text);
  void finish(int code) {
    _exit.complete(code);
    _out.close();
  }

  @override
  Stream<String> get output => _out.stream;
  @override
  void write(String text) => typed.add(text);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void kill() => finish(1);
}

void main() {
  group('gh output', () {
    // Verbatim output of `gh auth login --web` (gh 2.63) without a terminal.
    const ghOutput = '\n! First copy your one-time code: D00B-2297\n'
        'Open this URL to continue in your web browser: https://github.com/login/device\n';

    test('device code, page and success are recognised', () {
      expect(deviceCodeIn(ghOutput), 'D00B-2297');
      expect(deviceUrlIn(ghOutput), 'https://github.com/login/device');
      expect(deviceCodeIn('nothing here'), isNull);
      expect(loggedInAs('✓ Logged in as octocat\r\n'), 'octocat');
    });

    test('commit identity from the account; private email uses the noreply address', () {
      expect(identityFor(const GitHubUser(id: 42, login: 'octocat', name: 'Mona', email: 'mona@x.io')),
          ('Mona', 'mona@x.io'));
      expect(identityFor(const GitHubUser(id: 42, login: 'octocat')), ('octocat', '42+octocat@users.noreply.github.com'));
    });
  });

  group('sign in', () {
    late FakeGh gh;
    late List<List<String>> commands;
    late GitHubAuth auth;
    var userJson = '{"id":42,"login":"octocat","name":"Mona","email":null}';

    setUp(() {
      gh = FakeGh();
      commands = [];
      auth = GitHubAuth(
        startLogin: () async => gh,
        run: (args, {stdin}) async {
          commands.add(args);
          if (args.take(2).join(' ') == 'auth status') return const GitResult(1, '', 'not logged in');
          if (args.take(2).join(' ') == 'api user') return GitResult(0, userJson, '');
          return const GitResult(0, '', '');
        },
      );
    });

    test('code and page shown with nothing to answer; git set up; account read', () async {
      final done = auth.signIn();
      await pumpEventQueue();
      expect(auth.state, isA<SigningIn>());
      // The code may arrive split across reads.
      gh.say('\n! First copy your one-time co');
      gh.say('de: D00B-2297\nOpen this URL to continue in your web browser: https://github.com/login/device\n');
      await pumpEventQueue();
      expect(auth.state, isA<AwaitingCode>()
          .having((s) => s.code, 'code', 'D00B-2297')
          .having((s) => s.url, 'url', 'https://github.com/login/device'));
      expect(gh.typed, isEmpty); // no prompts without a terminal
      gh.say('✓ Authentication complete.\n✓ Logged in as octocat\n');
      gh.finish(0);
      await done;
      expect(auth.state, isA<SignedIn>().having((s) => s.user.login, 'login', 'octocat'));
      expect(commands.map((c) => c.join(' ')), contains('auth setup-git --hostname github.com'));
    });

    test('a failed login shows why and stays signed out', () async {
      final done = auth.signIn();
      await pumpEventQueue();
      gh.say('error connecting to github.com\r\n');
      gh.finish(1);
      await done;
      expect(auth.state, isA<SignInFailed>().having((s) => s.message, 'message', contains('github.com')));
    });

    test('repositories are listed for cloning, newest first', () async {
      final lister = GitHubAuth(
        startLogin: () async => gh,
        run: (args, {stdin}) async {
          commands.add(args);
          return const GitResult(0,
              '[{"nameWithOwner":"octocat/old","description":"","isPrivate":false,"updatedAt":"2024-01-01T00:00:00Z"},'
              '{"nameWithOwner":"octocat/new","description":"Fresh","isPrivate":true,"updatedAt":"2026-05-01T00:00:00Z"}]',
              '');
        },
      );
      final repos = await lister.repositories();
      expect(repos.map((r) => r.fullName), ['octocat/new', 'octocat/old']);
      expect(repos.first.private, isTrue);
      expect(repos.first.description, 'Fresh');
      expect(repos.last.description, isNull);
      expect(repos.first.cloneUrl, 'https://github.com/octocat/new.git');
      expect(commands.single.take(2), ['repo', 'list']);
    });

    test('publishing creates the GitHub repo from the folder and pushes', () async {
      await auth.publish('/root/projects/my app', name: 'my-app', private: true);
      expect(commands.last, ['repo', 'create', 'my-app', '--private', '--source', '/root/projects/my app', '--remote', 'origin', '--push']);
    });

    test('refresh picks up an existing sign-in', () async {
      final signedIn = GitHubAuth(
        startLogin: () async => gh,
        run: (args, {stdin}) async => args.first == 'api' ? GitResult(0, userJson, '') : const GitResult(0, '', ''),
      );
      await signedIn.refresh();
      expect(signedIn.state, isA<SignedIn>());
    });
  });
}
