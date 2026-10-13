import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/github_auth.dart';
import 'package:aiterm/git/git_runner.dart';

/// gh running on a PTY, scripted: what it prints, what we type back.
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
    test('device code, prompts and success are recognised', () {
      expect(deviceCodeIn('! First copy your one-time code: 4E5C-1A2B\r\n'), '4E5C-1A2B');
      expect(deviceCodeIn('nothing here'), isNull);
      expect(ghPromptIn('? Authenticate Git with your GitHub credentials? (Y/n) '), GhPrompt.authenticateGit);
      expect(ghPromptIn('Press Enter to open https://github.com/login/device in your browser... '), GhPrompt.pressEnter);
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

    test('code shown, prompts answered, git set up, account read', () async {
      final states = <GitHubAuthState>[];
      auth.addListener(() => states.add(auth.state));
      final done = auth.signIn();
      await pumpEventQueue();
      gh.say('? Authenticate Git with your GitHub credentials? (Y/n) ');
      await pumpEventQueue();
      expect(gh.typed, ['Y\r']);
      gh.say('\r\n! First copy your one-time code: 4E5C-1A2B\r\nPress Enter to open https://github.com/login/device in your browser... ');
      await pumpEventQueue();
      expect(auth.state, isA<AwaitingCode>().having((s) => s.code, 'code', '4E5C-1A2B'));
      expect(gh.typed.last, '\r');
      gh.say('\r\n✓ Authentication complete.\r\n✓ Logged in as octocat\r\n');
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
