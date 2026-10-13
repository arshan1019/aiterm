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
