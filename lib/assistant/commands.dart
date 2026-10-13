import 'tool_call.dart';

enum SuggestionSource {
  /// An exact phrasing rule matched; the suggestion is certain.
  rules,

  /// Picked by the on-device model; the user should check it.
  model,
}

/// One thing the assistant offers to do.
class Suggestion {
  /// What the user sees: a shell command, or a description of an app action.
  final String label;

  /// Text to type into the shell; null for app actions.
  final String? command;

  /// The command still needs something typed after it (e.g. a folder name).
  final bool needsInput;

  /// Set for actions the app performs itself (theme, font size, tabs…).
  final ToolCall? appAction;

  final SuggestionSource source;

  const Suggestion({required this.label, this.command, this.needsInput = false, this.appAction, required this.source});
}

/// Turns a tool call into a command from a fixed template, with every
/// argument shell-quoted, so neither the rules nor the model can produce a
/// command we didn't write. Null when the action isn't available here
/// (e.g. package installs in the Android shell).
Suggestion? suggestionFor(ToolCall i, {required bool alpine, required SuggestionSource source}) {
  if (i.rawCommand case final cmd?) return Suggestion(label: cmd, command: cmd, source: source);
  String arg(String k) => i.args[k]?.trim() ?? '';
  final path = arg('path').isEmpty ? '.' : _q(arg('path'));

  Suggestion cmd(String c, {bool partial = false}) =>
      Suggestion(label: c, command: c, needsInput: partial, source: source);
  Suggestion app(String label) => Suggestion(label: label, appAction: i, source: source);
  Suggestion? needs(String key, String full, String partial) =>
      arg(key).isEmpty ? cmd(partial, partial: true) : cmd(full);

  switch (i.tool) {
    case 'install_package':
      if (!alpine) return null;
      final pkgs = _packageAliases[arg('name').toLowerCase()] ?? [arg('name')];
      return arg('name').isEmpty ? cmd('apk add ', partial: true) : cmd('apk add ${pkgs.map(_q).join(' ')}');
    case 'remove_package':
      if (!alpine) return null;
      return needs('name', 'apk del ${_q(arg('name'))}', 'apk del ');
    case 'update_packages':
      return alpine ? cmd('apk update && apk upgrade') : null;
    case 'install_dependencies':
      return cmd('npm install');
    case 'run_script':
      final s = arg('script');
      if (s.isEmpty) return cmd('npm run ', partial: true);
      return cmd(s == 'start' ? 'npm start' : 'npm run ${_q(s)}');
    case 'create_folder':
      return needs('name', 'mkdir -p ${_q(arg('name'))}', 'mkdir -p ');
    case 'create_file':
      return needs('name', 'touch ${_q(arg('name'))}', 'touch ');
    case 'delete_file':
      return arg('name').isEmpty ? null : cmd('rm -r ${_q(arg('name'))}');
    case 'move_file':
      if (arg('source').isEmpty) return cmd('mv ', partial: true);
      return needs('destination', 'mv ${_q(arg('source'))} ${_q(arg('destination'))}', 'mv ${_q(arg('source'))} ');
    case 'copy_file':
      if (arg('source').isEmpty) return cmd('cp -r ', partial: true);
      return needs('destination', 'cp -r ${_q(arg('source'))} ${_q(arg('destination'))}',
          'cp -r ${_q(arg('source'))} ');
    case 'show_file':
      return needs('name', 'cat ${_q(arg('name'))}', 'cat ');
    case 'edit_file':
      return needs('name', 'vi ${_q(arg('name'))}', 'vi ');
    case 'list_files':
      return cmd('ls -la $path');
    case 'change_directory':
      return needs('path', 'cd ${_q(arg('path'))}', 'cd ');
    case 'current_folder':
      return cmd('pwd');
    case 'find_files':
      final type = arg('type').toLowerCase();
      final name = arg('name');
      final ext = _extensions[type] ?? (type.length <= 4 && type.isNotEmpty ? [type] : null);
      if (ext != null) {
        final names = ext.map((e) => "-name '*.$e'").join(' -o ');
        return cmd(ext.length == 1 ? 'find $path -type f $names' : 'find $path -type f \\( $names \\)');
      }
      final term = name.isNotEmpty ? name : type;
      return term.isEmpty ? cmd('find $path -iname ', partial: true) : cmd('find $path -iname ${_q('*$term*')}');
    case 'search_text':
      return arg('query').isEmpty ? cmd('grep -rn ', partial: true) : cmd('grep -rn ${_q(arg('query'))} $path');
    case 'free_space':
      return cmd('df -h .');
    case 'find_big_files':
      return cmd('du -ah $path 2>/dev/null | sort -rh | head -20');
    case 'show_processes':
      return cmd(alpine ? 'ps' : 'ps -A');
    case 'kill_process':
      return needs('name', 'pkill ${_q(arg('name'))}', 'pkill ');
    case 'git_status':
      return cmd('git status');
    case 'git_commit':
      return arg('message').isEmpty
          ? cmd('git add -A && git commit -m ', partial: true)
          : cmd('git add -A && git commit -m ${_q(arg('message'))}');
    case 'git_push':
      return cmd('git push');
    case 'git_clone':
      return needs('url', 'git clone ${_q(arg('url'))}', 'git clone ');
    case 'download_file':
      if (!alpine) return null;
      return needs('url', 'wget ${_q(arg('url'))}', 'wget ');
    case 'start_claude':
      return cmd('command -v claude >/dev/null || npm i -g @anthropic-ai/claude-code; claude');
    case 'set_font_size':
      final bigger = arg('change') != 'smaller';
      return app(bigger ? 'Make the text bigger' : 'Make the text smaller');
    case 'set_theme':
      return app(arg('theme') == 'light' ? 'Switch to the light theme' : 'Switch to the dark theme');
    case 'open_tab':
      final tab = arg('tab');
      if (!const ['terminal', 'files', 'settings'].contains(tab)) return null;
      return app('Open ${tab[0].toUpperCase()}${tab.substring(1)}');
    case 'restart_shell':
      return app('Restart the shell');
    case 'show_in_files':
      return app('Show ${arg('path').isEmpty ? 'home' : arg('path')} in Files');
  }
  return null;
}

String _q(String s) =>
    RegExp(r'^[A-Za-z0-9._/@:=+,~-]+$').hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";

const _packageAliases = {
  'node': ['nodejs', 'npm'],
  'nodejs': ['nodejs', 'npm'],
  'npm': ['nodejs', 'npm'],
  'python': ['python3', 'py3-pip'],
  'python3': ['python3', 'py3-pip'],
  'pip': ['py3-pip'],
  'rg': ['ripgrep'],
  'rust': ['rust', 'cargo'],
  'java': ['openjdk17'],
  'openjdk': ['openjdk17'],
  'ssh': ['openssh'],
  'g++': ['g++'],
};

const _extensions = {
  'python': ['py'],
  'javascript': ['js'],
  'typescript': ['ts'],
  'dart': ['dart'],
  'kotlin': ['kt'],
  'java': ['java'],
  'markdown': ['md'],
  'images': ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  'image': ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  'photos': ['png', 'jpg', 'jpeg', 'heic'],
  'videos': ['mp4', 'mkv', 'mov', 'webm'],
  'pdfs': ['pdf'],
  'shell scripts': ['sh'],
  'shell': ['sh'],
};
