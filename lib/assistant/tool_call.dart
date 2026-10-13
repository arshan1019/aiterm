/// An action the user asked for, in the same shape Needle returns:
/// a tool name plus arguments. Produced either by [matchRules] or by Needle.
class ToolCall {
  final String tool;
  final Map<String, String> args;
  const ToolCall(this.tool, [this.args = const {}]);

  /// Set when the user typed a shell command outright; it is used verbatim.
  String? get rawCommand => tool == 'raw' ? args['command'] : null;

  @override
  String toString() => '$tool$args';
}

const _shellCommands = {
  'ls', 'cd', 'pwd', 'mkdir', 'touch', 'rm', 'rmdir', 'cp', 'mv', 'cat', 'less',
  'head', 'tail', 'grep', 'find', 'du', 'df', 'ps', 'top', 'kill', 'pkill',
  'git', 'npm', 'npx', 'node', 'apk', 'pip', 'pip3', 'python', 'python3',
  'vi', 'vim', 'nano', 'wget', 'curl', 'chmod', 'chown', 'tar', 'unzip',
  'echo', 'which', 'clear', 'claude', 'ssh', 'make',
};

/// Package names that are unambiguously software, so "remove vim" means
/// uninstall rather than delete a file called vim.
const knownPackages = {
  'node', 'nodejs', 'npm', 'python', 'python3', 'pip', 'git', 'curl', 'wget',
  'vim', 'nano', 'gcc', 'g++', 'make', 'go', 'rust', 'cargo', 'ripgrep', 'rg',
  'jq', 'htop', 'openssh', 'ssh', 'zip', 'unzip', 'bash', 'zsh', 'fish',
  'neovim', 'nvim', 'tmux', 'ffmpeg', 'sqlite', 'postgresql', 'redis', 'java',
  'openjdk', 'ruby', 'php', 'deno', 'bun', 'yarn', 'pnpm', 'docker', 'clang',
  'cmake', 'perl', 'lua', 'fzf', 'bat', 'fd', 'tree', 'gh',
};

final _url = RegExp(r'(https?://\S+|\b(?:github|gitlab)\.com/\S+)', caseSensitive: false);
final _fileLike = RegExp(r'[\w-]*\.\w{1,6}$|/');

String _clean(String s) => s
    .trim()
    .replaceAll(RegExp(r'[?.!]+$'), '')
    .replaceAll(RegExp(r'^(please|pls|can you|could you|i want to|i need to|help me|let\x27s)\s+',
        caseSensitive: false), '')
    .trim();

String _stripArticles(String s) =>
    s.replaceAll(RegExp(r'^(the|a|an|my|this|that)\s+', caseSensitive: false), '').trim();

String? _nameAfterCalled(String rest) {
  final m = RegExp(r'\b(?:called|named)\s+(\S+)', caseSensitive: false).firstMatch(rest);
  if (m != null) return m.group(1);
  final w = rest.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  // A single trailing word is the name ("new folder src"); longer phrases
  // without "called" are descriptions, so leave the name for the user.
  return w.length == 1 ? w.first : null;
}

/// Deterministic matches for phrasings that are unambiguous. Returns null when
/// the request should go to Needle instead.
ToolCall? matchRules(String input) {
  final text = _clean(input);
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  final first = lower.split(RegExp(r'\s+')).first;

  // Already a shell command: use it as typed.
  if (_shellCommands.contains(first) && !RegExp(r'^\w+\s+(the|a|my|all|every)\b').hasMatch(lower)) {
    return ToolCall('raw', {'command': text});
  }

  final url = _url.firstMatch(text)?.group(0);
  if (url != null) {
    final isRepo = RegExp(r'github\.com|gitlab\.com|\.git\b|\b(clone|repo|repository)\b')
        .hasMatch(lower);
    if (RegExp(r'\b(clone|repo|repository)\b').hasMatch(lower) || (isRepo && !lower.contains('download'))) {
      return ToolCall('git_clone', {'url': url});
    }
    if (RegExp(r'\b(download|fetch|get|save)\b').hasMatch(lower)) {
      return isRepo
          ? ToolCall('git_clone', {'url': url})
          : ToolCall('download_file', {'url': url});
    }
  }

  // Project tasks before packages: "install dependencies" is not a package.
  if (RegExp(r'\b(dependencies|deps|node_modules)\b|project.?s packages|\bnpm packages\b').hasMatch(lower) &&
      RegExp(r'\b(install|get|add|setup|set up)\b').hasMatch(lower)) {
    return const ToolCall('install_dependencies');
  }
  if (RegExp(r'\bdev server\b|\brun dev\b').hasMatch(lower)) return const ToolCall('run_script', {'script': 'dev'});
  if (RegExp(r'\b(run|start)\s+(the\s+)?tests?\b').hasMatch(lower)) return const ToolCall('run_script', {'script': 'test'});
  if (RegExp(r'^build( the)?( project| app)?$').hasMatch(lower)) return const ToolCall('run_script', {'script': 'build'});

  // Packages.
  var m = RegExp(r'^(?:uninstall|get rid of)\s+(.+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('remove_package', {'name': _pkg(m.group(1)!)});
  m = RegExp(r'^remove\s+(?:the\s+)?(.+?)(?:\s+package)?$', caseSensitive: false).firstMatch(text);
  if (m != null && knownPackages.contains(_pkg(m.group(1)!))) {
    return ToolCall('remove_package', {'name': _pkg(m.group(1)!)});
  }
  if (RegExp(r'^(update|upgrade)\b').hasMatch(lower) &&
      RegExp(r'\b(everything|all|packages|system|apps|software)\b|^(update|upgrade)$').hasMatch(lower)) {
    return const ToolCall('update_packages');
  }
  m = RegExp(r'^(?:download and install|install|add|setup|set up|get me|get|i need)\s+(.+)$', caseSensitive: false)
      .firstMatch(text);
  if (m != null) {
    final name = _pkg(m.group(1)!);
    if (lower.startsWith('install') || knownPackages.contains(name)) {
      return ToolCall('install_package', {'name': name});
    }
  }

  // Folders and files.
  m = RegExp(r'^(?:create|make|new|add)\s+(?:a\s+)?(?:new\s+)?(?:folder|directory|dir)\b\s*(.*)$', caseSensitive: false)
      .firstMatch(text);
  if (m != null) return ToolCall('create_folder', {'name': ?_nameAfterCalled(m.group(1)!)});
  m = RegExp(r'^(?:create|make|new|add)\s+(?:a\s+)?(?:new\s+)?(?:empty\s+)?file\b\s*(.*)$', caseSensitive: false)
      .firstMatch(text);
  if (m != null) return ToolCall('create_file', {'name': ?_nameAfterCalled(m.group(1)!)});
  m = RegExp(r'^rename\s+(\S+)\s+(?:to|as)\s+(\S+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('move_file', {'source': m.group(1)!, 'destination': m.group(2)!});
  m = RegExp(r'^move\s+(\S+)\s+(?:to|into)\s+(\S+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('move_file', {'source': m.group(1)!, 'destination': m.group(2)!});
  m = RegExp(r'^(?:copy|duplicate)\s+(\S+)\s+(?:to|as|into)\s+(\S+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('copy_file', {'source': m.group(1)!, 'destination': m.group(2)!});
  m = RegExp(r'^(?:delete|remove|erase)\s+(?:the\s+)?(.+?)(?:\s+(?:file|folder|directory))?$', caseSensitive: false)
      .firstMatch(text);
  if (m != null) {
    final name = m.group(1)!;
    final words = name.split(RegExp(r'\s+'));
    if (words.length == 1 && name.toLowerCase() != 'everything' && name.toLowerCase() != 'all') {
      return ToolCall('delete_file', {'name': name});
    }
  }
  m = RegExp(r'^(?:edit|modify|change(?: the contents of)?|open\s+(\S+)\s+in\s+(?:an?\s+)?editor)\s*(\S*)$',
          caseSensitive: false)
      .firstMatch(text);
  if (m != null) {
    final name = m.group(1) ?? m.group(2)!;
    if (_fileLike.hasMatch(name)) return ToolCall('edit_file', {'name': name});
  }
  m = RegExp(r'^(?:show(?: me)?|print|read|view|open|display)\s+(?:the\s+)?(\S+)$', caseSensitive: false)
      .firstMatch(text);
  if (m != null && _fileLike.hasMatch(m.group(1)!)) {
    return ToolCall('show_file', {'name': m.group(1)!});
  }
  m = RegExp(r'^what does\s+(\S+)\s+(?:say|contain)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('show_file', {'name': m.group(1)!});

  // Navigation.
  if (RegExp(r'^(where am i|what folder am i in|(show )?(the )?current (folder|directory|dir))$').hasMatch(lower)) {
    return const ToolCall('current_folder');
  }
  if (RegExp(r'^go (up|back)( one( folder| level)?)?$').hasMatch(lower)) {
    return const ToolCall('change_directory', {'path': '..'});
  }
  if (RegExp(r'^go home$|^go to (my )?home( folder)?$').hasMatch(lower)) {
    return const ToolCall('change_directory', {'path': '~'});
  }
  m = RegExp(r'^(?:go to|go into|cd into|open folder|enter)\s+(?:the\s+)?(\S+)(?:\s+folder)?$', caseSensitive: false)
      .firstMatch(text);
  if (m != null) return ToolCall('change_directory', {'path': m.group(1)!});
  m = RegExp(r"^(?:what'?s|what is) in (?:the\s+)?(\S+?)(?:\s+folder)?$", caseSensitive: false).firstMatch(text);
  if (m != null) {
    final p = m.group(1)!;
    return ToolCall('list_files', {if (p != 'this' && p != 'here') 'path': p});
  }
  if (RegExp(r'^(list|show)( all| me)?( the)?( hidden)? files$|^list$').hasMatch(lower)) {
    return const ToolCall('list_files');
  }

  // Storage and processes.
  if (RegExp(r'\b(space|storage)\b.*\b(left|free|full|available|have)\b|\bfree (space|storage)\b|\bdisk space\b')
      .hasMatch(lower)) {
    return const ToolCall('free_space');
  }
  if (RegExp(r'\b(biggest|largest|big) files\b|\btaking up (space|storage)\b|\beating (my )?(space|storage)\b')
      .hasMatch(lower)) {
    return const ToolCall('find_big_files');
  }
  if (RegExp(r"^(what'?s|what is) running$|\b(running|show) (processes|programs)\b").hasMatch(lower)) {
    return const ToolCall('show_processes');
  }
  m = RegExp(r'^(?:stop|kill|close)\s+(\S+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('kill_process', {'name': m.group(1)!});

  // Git.
  if (RegExp(r'^(what changed|show (me )?my changes|what did i change)$').hasMatch(lower)) {
    return const ToolCall('git_status');
  }
  if (RegExp(r'^push\b').hasMatch(lower) || RegExp(r'\bupload my commits\b').hasMatch(lower)) {
    return const ToolCall('git_push');
  }
  m = RegExp(r'\bcommit\b.*\b(?:message|saying|as)\s+(.+)$', caseSensitive: false).firstMatch(text);
  if (m != null) return ToolCall('git_commit', {'message': m.group(1)!});

  if (RegExp(r'^(bigger|larger) (font|text)$|^(increase|bigger) font( size)?$|^zoom in$').hasMatch(lower)) {
    return const ToolCall('set_font_size', {'change': 'bigger'});
  }
  if (RegExp(r'^smaller (font|text)$|^(decrease|smaller) font( size)?$|^zoom out$').hasMatch(lower)) {
    return const ToolCall('set_font_size', {'change': 'smaller'});
  }
  if (RegExp(r'^(dark|night) (mode|theme)$|^(switch to|use|turn on) dark( mode| theme)?$').hasMatch(lower)) {
    return const ToolCall('set_theme', {'theme': 'dark'});
  }
  if (RegExp(r'^(light|day) (mode|theme)$|^(switch to|use|turn on) light( mode| theme)?$').hasMatch(lower)) {
    return const ToolCall('set_theme', {'theme': 'light'});
  }
  if (RegExp(r'^(open|go to|show) (the )?settings$').hasMatch(lower)) return const ToolCall('open_tab', {'tab': 'settings'});
  if (RegExp(r'^restart (the )?(shell|terminal|session)$').hasMatch(lower)) return const ToolCall('restart_shell');

  if (RegExp(r'\bclaude\b|\bai (coding )?assistant\b').hasMatch(lower)) return const ToolCall('start_claude');

  return null;
}

String _pkg(String raw) {
  var s = _stripArticles(raw.toLowerCase())
      .replaceAll(RegExp(r'\s+(package|program|tool|app)s?$'), '')
      .trim();
  s = s.split(RegExp(r'\s+and\s+|,\s*')).first.trim();
  if (s.endsWith(' compiler')) s = s.substring(0, s.length - ' compiler'.length);
  return s;
}
