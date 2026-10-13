/// Spots common errors in terminal output and proposes the usual fix.
/// Exact patterns, no model: for these errors a pattern is never wrong about
/// what happened, and the fix is still shown for the user to confirm.
class ErrorFix {
  final String problem;
  final String command;

  /// The command needs something typed after it (e.g. an email address).
  final bool needsInput;
  const ErrorFix(this.problem, this.command, {this.needsInput = false});

  @override
  bool operator ==(Object other) => other is ErrorFix && other.command == command;
  @override
  int get hashCode => command.hashCode;
}

final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07]*(\x07|\x1B\\)');

/// Packages that provide a missing command, where the names differ.
const _commandPackages = {
  'rg': 'ripgrep', 'python': 'python3', 'pip': 'py3-pip', 'pip3': 'py3-pip', 'node': 'nodejs npm',
  'npm': 'nodejs npm', 'npx': 'nodejs npm', 'g++': 'g++', 'cc': 'gcc', 'ssh': 'openssh', 'nvim': 'neovim',
  'fd': 'fd', 'bat': 'bat', 'gh': 'github-cli', 'java': 'openjdk17', 'javac': 'openjdk17', 'cargo': 'cargo',
  'rustc': 'rust', 'go': 'go', 'make': 'make', 'git': 'git', 'curl': 'curl', 'wget': 'wget', 'zip': 'zip',
  'unzip': 'unzip', 'jq': 'jq', 'htop': 'htop', 'tmux': 'tmux', 'vim': 'vim', 'nano': 'nano',
  'sqlite3': 'sqlite', 'ffmpeg': 'ffmpeg', 'claude': '', 'yarn': 'yarn', 'pnpm': 'pnpm', 'bash': 'bash',
};

String _q(String s) =>
    RegExp(r'^[A-Za-z0-9._/@:=+,~-]+$').hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";

/// Looks at the end of [output] (raw terminal bytes as text) and returns a fix
/// for the most recent recognised error, or null.
ErrorFix? detectFix(String output, {required bool alpine}) {
  final text = output.replaceAll(_ansi, '').replaceAll('\r', '');
  final tail = text.length > 3000 ? text.substring(text.length - 3000) : text;
  final lines = tail.split('\n');
  // Newest error wins: walk backwards.
  for (var i = lines.length - 1; i >= 0 && i >= lines.length - 40; i--) {
    final fix = _matchLine(lines[i], alpine);
    if (fix != null) return fix;
  }
  return null;
}

ErrorFix? _matchLine(String line, bool alpine) {
  RegExpMatch? m;

  m = RegExp(r"Cannot find module '([^']+)'").firstMatch(line);
  if (m != null) {
    final mod = m.group(1)!;
    if (mod.startsWith('.') || mod.startsWith('/')) return null; // a local file, not a package
    final pkg = mod.startsWith('@') ? mod.split('/').take(2).join('/') : mod.split('/').first;
    return ErrorFix('Missing Node module $pkg', 'npm install ${_q(pkg)}');
  }

  m = RegExp(r"ModuleNotFoundError: No module named '([^'.]+)").firstMatch(line);
  if (m != null) {
    final mod = m.group(1)!;
    final pkg = const {'cv2': 'opencv-python', 'PIL': 'pillow', 'yaml': 'pyyaml', 'bs4': 'beautifulsoup4',
            'sklearn': 'scikit-learn'}[mod] ??
        mod;
    // Alpine's Python is marked externally managed (PEP 668).
    return ErrorFix('Missing Python module $mod',
        alpine ? 'pip install --break-system-packages ${_q(pkg)}' : 'pip install ${_q(pkg)}');
  }

  // ash: "sh: rg: not found"   bash: "bash: rg: command not found"   zsh: "zsh: command not found: rg"
  m = RegExp(r'^(?:\S+: )?(?:line \d+: )?([\w.+-]+): (?:command )?not found\s*$').firstMatch(line.trim()) ??
      RegExp(r'command not found: ([\w.+-]+)').firstMatch(line);
  if (m != null) {
    final cmd = m.group(1)!;
    if (cmd == 'claude') {
      return const ErrorFix('Claude Code is not installed', 'npm i -g @anthropic-ai/claude-code');
    }
    if (!alpine) return null; // no package manager in the Android shell
    final pkg = _commandPackages[cmd] ?? cmd;
    return ErrorFix('$cmd is not installed', 'apk add $pkg');
  }

  m = RegExp(r'(\./[\w./-]+): Permission denied').firstMatch(line);
  if (m != null) {
    final file = m.group(1)!;
    return ErrorFix('$file is not executable', 'chmod +x ${_q(file)} && ${_q(file)}');
  }

  m = RegExp(r'EADDRINUSE[^\n]*?:(\d{2,5})').firstMatch(line) ??
      RegExp(r'[Aa]ddress already in use[^\n]*?:(\d{2,5})').firstMatch(line) ??
      RegExp(r'port (\d{2,5}) is already in use', caseSensitive: false).firstMatch(line);
  if (m != null) {
    final port = m.group(1)!;
    return ErrorFix('Port $port is already in use', 'fuser -k $port/tcp');
  }

  if (RegExp(r'fatal: not a git repository').hasMatch(line)) {
    return const ErrorFix('This folder is not a git repository', 'git init');
  }

  m = RegExp(r'has no upstream branch').firstMatch(line);
  if (m != null) {
    return const ErrorFix('Branch has no upstream', 'git push -u origin HEAD');
  }

  if (RegExp(r'Please tell me who you are|Author identity unknown').hasMatch(line)) {
    return const ErrorFix('Git needs your name and email', 'git config --global user.email ', needsInput: true);
  }

  if (RegExp(r"ENOENT: no such file or directory, open '[^']*package\.json'").hasMatch(line) ||
      RegExp(r'npm (ERR!|error) code ENOENT').hasMatch(line) && line.contains('package.json')) {
    return const ErrorFix('No package.json here', 'npm init -y');
  }

  m = RegExp(r'npm (?:ERR!|error) Missing script: "([\w:-]+)"').firstMatch(line);
  if (m != null) {
    return ErrorFix('No "${m.group(1)}" script in package.json', 'npm run');
  }

  return null;
}
