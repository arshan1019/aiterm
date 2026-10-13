/// What to exec on a PTY: argv, the environment for argv[0], and its cwd.
class SessionSpec {
  final List<String> argv;
  final Map<String, String> env;
  final String cwd;
  const SessionSpec(this.argv, this.env, this.cwd);
}
