import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'git_runner.dart';

/// Runs `gh` with [ghArgs] (and optional stdin) inside Linux.
typedef GhRunner = Future<GitResult> Function(List<String> ghArgs, {String? stdin});

/// A process the app reads (gh's login).
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

class GitHubRepo {
  const GitHubRepo({required this.fullName, this.description, required this.private, required this.updatedAt});
  final String fullName;
  final String? description;
  final bool private;
  final DateTime updatedAt;

  String get name => fullName.split('/').last;
  String get cloneUrl => 'https://github.com/$fullName.git';
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

final _code = RegExp(r'one-time code:\s*([A-Z0-9]{4}-[A-Z0-9]{4})');
final _url = RegExp(r'(https://\S+/login/device)\b');
final _ansi = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]');

String? deviceCodeIn(String text) => _code.firstMatch(text.replaceAll(_ansi, ''))?.group(1);

/// The page gh asks the user to open (GitHub's device activation page).
String? deviceUrlIn(String text) => _url.firstMatch(text.replaceAll(_ansi, ''))?.group(1);

String? loggedInAs(String text) => RegExp(r'Logged in as (\S+)').firstMatch(text.replaceAll(_ansi, ''))?.group(1);

/// Commit identity from a GitHub account: its public name and email, or
/// GitHub's noreply address when the email is private.
(String, String) identityFor(GitHubUser u) =>
    (u.name ?? u.login, u.email ?? '${u.id}+${u.login}@users.noreply.github.com');

/// "Sign in with GitHub" through GitHub's official CLI and its device flow
/// (docs.github.com: Authorizing OAuth apps, device flow): gh prints a
/// one-time code, the app shows it and opens github.com/login/device, gh
/// polls until the user approves; then `gh auth setup-git` so git uses the
/// same credentials over HTTPS.
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
      final sub = gh.output.listen((chunk) {
        log.write(chunk);
        final text = log.toString();
        final code = deviceCodeIn(text);
        if (code != null && state is! AwaitingCode) _set(AwaitingCode(code, deviceUrlIn(text) ?? deviceUrl));
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

  /// The account's repositories (own and member), most recently updated first.
  Future<List<GitHubRepo>> repositories() async {
    final r = await _run(['repo', 'list', '--limit', '200', '--json', 'nameWithOwner,description,isPrivate,updatedAt']);
    if (!r.ok) throw Exception(r.stderr.trim().isEmpty ? 'Couldn\'t list your repositories.' : r.stderr.trim());
    final list = (jsonDecode(r.stdout) as List).cast<Map<String, dynamic>>();
    return [
      for (final m in list)
        GitHubRepo(
          fullName: m['nameWithOwner'] as String,
          description: (m['description'] as String?)?.trim().isEmpty ?? true ? null : (m['description'] as String).trim(),
          private: m['isPrivate'] as bool? ?? false,
          updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime(1970),
        ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Creates a GitHub repository for the local repo at [folder], adds it
  /// as origin and pushes.
  Future<GitResult> publish(String folder, {required String name, required bool private}) => _run(
      ['repo', 'create', name, private ? '--private' : '--public', '--source', folder, '--remote', 'origin', '--push']);

  /// Uploads an SSH public key to the signed-in account.
  Future<GitResult> addSshKey(String publicKey, String title) =>
      _run(['ssh-key', 'add', '-', '--title', title], stdin: '$publicKey\n');
}
