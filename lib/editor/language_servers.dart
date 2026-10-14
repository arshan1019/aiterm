/// Language servers the editor uses for errors as you type, completion and
/// hover: real servers installed in Linux, one tap each (like the agents).
/// Several are VS Code's own (vscode-langservers-extracted).
library;

class LanguageServer {
  const LanguageServer({
    required this.id,
    required this.name,
    required this.languages,
    required this.binary,
    required this.command,
    required this.install,
  });

  final String id;

  /// Shown on the install button ("Install Python support").
  final String name;

  /// LSP language ids it handles.
  final Set<String> languages;

  /// The program `command -v` checks for.
  final String binary;

  /// How to start it (speaking LSP on stdio).
  final String command;

  /// POSIX sh, stopping at the first error.
  final String install;
}

const _node = 'apk add -q --no-cache nodejs npm';

const languageServers = [
  LanguageServer(
    id: 'typescript',
    name: 'JavaScript & TypeScript',
    languages: {'javascript', 'javascriptreact', 'typescript', 'typescriptreact'},
    binary: 'typescript-language-server',
    command: 'typescript-language-server --stdio',
    install: 'set -e\n$_node\nnpm install -g typescript typescript-language-server',
  ),
  LanguageServer(
    id: 'python',
    name: 'Python',
    languages: {'python'},
    binary: 'pyright-langserver',
    command: 'pyright-langserver --stdio',
    install: 'set -e\n$_node\nnpm install -g pyright',
  ),
  LanguageServer(
    id: 'html',
    name: 'HTML',
    languages: {'html'},
    binary: 'vscode-html-language-server',
    command: 'vscode-html-language-server --stdio',
    install: 'set -e\n$_node\nnpm install -g vscode-langservers-extracted',
  ),
  LanguageServer(
    id: 'css',
    name: 'CSS',
    languages: {'css', 'scss', 'less'},
    binary: 'vscode-css-language-server',
    command: 'vscode-css-language-server --stdio',
    install: 'set -e\n$_node\nnpm install -g vscode-langservers-extracted',
  ),
  LanguageServer(
    id: 'json',
    name: 'JSON',
    languages: {'json', 'jsonc'},
    binary: 'vscode-json-language-server',
    command: 'vscode-json-language-server --stdio',
    install: 'set -e\n$_node\nnpm install -g vscode-langservers-extracted',
  ),
  LanguageServer(
    id: 'shell',
    name: 'Shell',
    languages: {'shellscript'},
    binary: 'bash-language-server',
    command: 'bash-language-server start',
    install: 'set -e\n$_node\napk add -q --no-cache shellcheck\nnpm install -g bash-language-server',
  ),
  LanguageServer(
    id: 'yaml',
    name: 'YAML',
    languages: {'yaml'},
    binary: 'yaml-language-server',
    command: 'yaml-language-server --stdio',
    install: 'set -e\n$_node\nnpm install -g yaml-language-server',
  ),
  LanguageServer(
    id: 'c',
    name: 'C & C++',
    languages: {'c', 'cpp'},
    binary: 'clangd',
    command: 'clangd',
    install: 'set -e\napk add -q --no-cache clang-extra-tools',
  ),
  LanguageServer(
    id: 'go',
    name: 'Go',
    languages: {'go'},
    binary: 'gopls',
    command: 'gopls',
    install: 'set -e\napk add -q --no-cache go gopls',
  ),
  LanguageServer(
    id: 'rust',
    name: 'Rust',
    languages: {'rust'},
    binary: 'rust-analyzer',
    command: 'rust-analyzer',
    install: 'set -e\napk add -q --no-cache rust cargo rust-analyzer',
  ),
  LanguageServer(
    id: 'lua',
    name: 'Lua',
    languages: {'lua'},
    binary: 'lua-language-server',
    command: 'lua-language-server',
    install: 'set -e\napk add -q --no-cache lua-language-server',
  ),
];

const _byExtension = {
  'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript', 'jsx': 'javascriptreact',
  'ts': 'typescript', 'mts': 'typescript', 'cts': 'typescript', 'tsx': 'typescriptreact',
  'py': 'python', 'pyi': 'python',
  'html': 'html', 'htm': 'html',
  'css': 'css', 'scss': 'scss', 'less': 'less',
  'json': 'json', 'jsonc': 'jsonc',
  'sh': 'shellscript', 'bash': 'shellscript', 'zsh': 'shellscript',
  'yaml': 'yaml', 'yml': 'yaml',
  'c': 'c', 'h': 'c', 'cc': 'cpp', 'cpp': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hh': 'cpp',
  'go': 'go', 'rs': 'rust', 'lua': 'lua',
  'md': 'markdown', 'java': 'java', 'kt': 'kotlin', 'php': 'php', 'rb': 'ruby', 'toml': 'toml', 'sql': 'sql',
  'dart': 'dart',
};

/// The LSP language id of [path], by extension.
String? languageIdFor(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? null : _byExtension[name.substring(dot + 1).toLowerCase()];
}

/// The server for [path], if aiterm knows one.
LanguageServer? serverFor(String path) {
  final id = languageIdFor(path);
  return id == null ? null : languageServers.where((s) => s.languages.contains(id)).firstOrNull;
}
