import 'dart:io';

class GitResult {
  const GitResult(this.code, this.stdout, this.stderr);
  final int code;
  final String stdout;
  final String stderr;
  bool get ok => code == 0;
}

/// Runs real git in a repository. [LinuxGitRunner] runs it inside Alpine;
/// [ProcessGitRunner] runs the host's git (tests, desktop).
abstract interface class GitRunner {
  Future<GitResult> run(String repo, List<String> args, {String? stdin});
}

/// Environment every git invocation gets: never prompt (the app asks
/// instead), accept a new host's SSH key once, stable English output.
const gitEnvironment = {
  'GIT_TERMINAL_PROMPT': '0',
  'GIT_SSH_COMMAND': 'ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes',
  'LC_ALL': 'C',
};

class ProcessGitRunner implements GitRunner {
  ProcessGitRunner({this.env = const {}});

  final Map<String, String> env;

  @override
  Future<GitResult> run(String repo, List<String> args, {String? stdin}) async {
    final p = await Process.start('git', args, workingDirectory: repo, environment: {...gitEnvironment, ...env});
    if (stdin != null) p.stdin.write(stdin);
    await p.stdin.close();
    final out = p.stdout.transform(const SystemEncoding().decoder).join();
    final err = p.stderr.transform(const SystemEncoding().decoder).join();
    final code = await p.exitCode;
    return GitResult(code, await out, await err);
  }
}

/// Single-quotes [s] for sh.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The sh command that runs git with [args] in [repo].
String gitCommandLine(String repo, List<String> args) =>
    'cd ${shellQuote(repo)} && exec git ${args.map(shellQuote).join(' ')}';

/// Runs a shell command line inside Linux: (stdout, stderr, exit code).
typedef LinuxCommand = Future<GitResult> Function(String commandLine, {Map<String, String> env, String? stdin});

/// Git inside Alpine (repo paths as the shell sees them, e.g. /root/proj).
class LinuxGitRunner implements GitRunner {
  LinuxGitRunner(this._command);

  final LinuxCommand _command;

  @override
  Future<GitResult> run(String repo, List<String> args, {String? stdin}) =>
      _command(gitCommandLine(repo, args), env: gitEnvironment, stdin: stdin);
}
