import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'git_runner.dart';

/// Runs `gh` with [ghArgs] (and optional stdin) inside Linux.
typedef GhRunner = Future<GitResult> Function(List<String> ghArgs, {String? stdin});

/// A process on a PTY the app talks to (gh's interactive login).
abstract interface class InteractiveProcess {
  Stream<String> get output;
  void write(String text);
  Future<int> get exitCode;
  void kill();
}

class GitHubUser {
  const GitHubUser({required this.id, required this.login, this.name, this.email});
  final int id;
  final String login;
  final String? name;
  final String? email;

  static GitHubUser? fromJson(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return GitHubUser(
        id: m['id'] as int,
        login: m['login'] as String,
        name: (m['name'] as String?)?.trim().isEmpty ?? true ? null : m['name'] as String,
        email: (m['email'] as String?)?.trim().isEmpty ?? true ? null : m['email'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

sealed class GitHubAuthState {
  const GitHubAuthState();
}

class SignedOut extends GitHubAuthState {
  const SignedOut();
}

class SigningIn extends GitHubAuthState {
  const SigningIn();
}

/// Waiting for the user to enter [code] at [url].
class AwaitingCode extends GitHubAuthState {
  const AwaitingCode(this.code, this.url);
  final String code;
  final String url;
}

class SignedIn extends GitHubAuthState {
  const SignedIn(this.user);
  final GitHubUser user;
}

class SignInFailed extends GitHubAuthState {
  const SignInFailed(this.message);
  final String message;
}

enum GhPrompt { authenticateGit, pressEnter }

final _code = RegExp(r'one-time code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})');
final _ansi = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]');

String? deviceCodeIn(String text) => _code.firstMatch(text.replaceAll(_ansi, ''))?.group(1);

GhPrompt? ghPromptIn(String text) {
  final t = text.replaceAll(_ansi, '');
  if (t.contains('Authenticate Git with your GitHub credentials')) return GhPrompt.authenticateGit;
  if (t.contains('Press Enter to open')) return GhPrompt.pressEnter;
  return null;
}

String? loggedInAs(String text) => RegExp(r'Logged in as (\S+)').firstMatch(text.replaceAll(_ansi, ''))?.group(1);

/// Commit identity from a GitHub account: its public name and email, or
/// GitHub's noreply address when the email is private.
(String, String) identityFor(GitHubUser u) =>
    (u.name ?? u.login, u.email ?? '${u.id}+${u.login}@users.noreply.github.com');

/// "Sign in to GitHub" with GitHub's official CLI: its device-code login
/// (the app shows the code and opens the page), then `gh auth setup-git`
/// so git uses the same credentials over HTTPS.
class GitHubAuth extends ChangeNotifier {
  GitHubAuth({required this._startLogin, required this._run});

  static const deviceUrl = 'https://github.com/login/device';

  final Future<InteractiveProcess> Function() _startLogin;
  final GhRunner _run;
  GitHubAuthState state = const SignedOut();
  InteractiveProcess? _login;

  GitHubUser? get user => switch (state) {
        SignedIn(:final user) => user,
        _ => null,
      };

  void _set(GitHubAuthState s) {
    state = s;
    notifyListeners();
  }

  /// Reads the current sign-in (e.g. at startup).
  Future<void> refresh() async {
    final u = await _readUser();
    _set(u == null ? const SignedOut() : SignedIn(u));
  }

  Future<GitHubUser?> _readUser() async {
    final r = await _run(['api', 'user']);
    return r.ok ? GitHubUser.fromJson(r.stdout) : null;
  }

  Future<void> signIn() async {
    if (state is SigningIn || state is AwaitingCode) return;
    _set(const SigningIn());
    final log = StringBuffer();
    try {
      final gh = _login = await _startLogin();
      final answered = <GhPrompt>{};
      final sub = gh.output.listen((chunk) {
        log.write(chunk);
        final text = log.toString();
        final code = deviceCodeIn(text);
        if (code != null && state is! AwaitingCode) _set(AwaitingCode(code, deviceUrl));
        for (final prompt in GhPrompt.values) {
          if (!answered.contains(prompt) && ghPromptIn(chunk) == prompt) {
            answered.add(prompt);
            gh.write(prompt == GhPrompt.authenticateGit ? 'Y\r' : '\r');
          }
        }
      });
      final code = await gh.exitCode;
      await sub.cancel();
      if (code != 0) {
        final reason = log.toString().replaceAll(_ansi, '').trim().split('\n').where((l) => l.trim().isNotEmpty);
        _set(SignInFailed(reason.isEmpty ? 'Sign-in didn\'t finish.' : reason.last.trim()));
        return;
      }
      await _run(['auth', 'setup-git', '--hostname', 'github.com']);
      final u = await _readUser();
      _set(u == null ? const SignInFailed('Signed in, but couldn\'t read the account.') : SignedIn(u));
    } catch (e) {
      _set(SignInFailed('$e'));
    } finally {
      _login = null;
    }
  }

  void cancel() {
    _login?.kill();
    _set(const SignedOut());
  }

  Future<void> signOut() async {
    await _run(['auth', 'logout', '--hostname', 'github.com']);
    _set(const SignedOut());
  }

  /// Uploads an SSH public key to the signed-in account.
  Future<GitResult> addSshKey(String publicKey, String title) =>
      _run(['ssh-key', 'add', '-', '--title', title], stdin: '$publicKey\n');
}
