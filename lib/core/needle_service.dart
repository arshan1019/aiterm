import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'distro_manager.dart';
import 'tool_call.dart';

class Suggestion {
  /// What the user sees: a shell command, or a description of an app action.
  final String label;

  /// Text to type into the shell; null for app actions.
  final String? command;

  /// The command still needs something typed after it (e.g. a folder name).
  final bool needsInput;

  /// Set for actions the app performs itself (theme, font size, tabs…).
  final ToolCall? appAction;

  /// 'rules' or 'model', so the UI can say how sure it is.
  final String source;

  const Suggestion({
    required this.label,
    this.command,
    this.needsInput = false,
    this.appAction,
    required this.source,
  });
}

class ModelFile {
  final String name, url, sha256;
  final int sizeMb;
  const ModelFile(this.name, this.url, this.sha256, this.sizeMb);
}

/// Turns "what do you want to do?" into commands. Unambiguous phrasings are
/// handled by [matchRules]; everything else goes to Needle, a small on-device
/// tool-calling model. Needle only picks one of the actions in
/// assets/needle_tools.json and fills its arguments; the command itself always
/// comes from a template here, with every argument shell-quoted, so the model
/// can never produce a command we didn't write.
class NeedleService {
  NeedleService._();
  static final instance = NeedleService._();

  static const _channel = MethodChannel('aiterm/needle');

  static const textModel = ModelFile(
    'needle3.cact',
    'https://huggingface.co/Cactus-Compute/needle3/resolve/93e88ede867e4311c39151285e74df513e4b835b/needle3.cact',
    'c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38',
    35,
  );
  static const voiceModel = ModelFile(
    'whistle.cact',
    'https://huggingface.co/Cactus-Compute/whistle/resolve/ca5287601bef25af26dcf2e1b2bdc0843a7c19e5/whistle.cact',
    'b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb',
    17,
  );

  /// Words Whistle should favour when transcribing terminal requests.
  static const _voiceKeywords = [
    'npm', 'apk', 'git', 'node', 'nodejs', 'python', 'pip', 'claude', 'mkdir', 'folder', 'directory',
    'install', 'uninstall', 'commit', 'push', 'clone', 'grep', 'ripgrep', 'vim', 'ls', 'cd', 'repo',
  ];

  bool _textReady = false;
  bool _voiceReady = false;

  Future<String> _path(ModelFile m) async {
    final d = DistroManager.instance;
    await d.init();
    return '${d.filesDir}/${m.name}';
  }

  Future<bool> isDownloaded(ModelFile m) async => File(await _path(m)).exists();

  Future<void> download(ModelFile m, void Function(double? progress) onProgress) async {
    final path = await _path(m);
    final part = File('$path.part');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(m.url)));
      if (resp.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = part.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total == null ? null : received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    onProgress(null);
    final sha = (await sha256.bind(part.openRead()).first).toString();
    if (sha != m.sha256) {
      await part.delete();
      throw StateError('Checksum mismatch for ${m.name}');
    }
    await part.rename(path);
  }

  Future<void> _ensureText() async {
    if (_textReady) return;
    final d = DistroManager.instance;
    await _channel.invokeMethod('init', {
      'modelPath': await _path(textModel),
      'system': 'You turn a terminal user\'s request into actions.',
      'tools': await rootBundle.loadString('assets/needle_tools.json'),
      'toolIndexPath': '${d.cacheDir}/needle-tools.idx',
    });
    _textReady = true;
  }

  Future<List<Suggestion>> suggest(String request, {required bool alpine}) async {
    final rule = matchRules(request);
    if (rule != null) {
      final s = fromCall(rule, alpine: alpine, source: 'rules');
      return s == null ? const [] : [s];
    }
    await _ensureText();
    final raw = await _channel.invokeMethod<String>('complete', {'input': request, 'maxTokens': 256});
    final result = jsonDecode(raw!) as Map<String, dynamic>;
    final calls = (result['function_calls'] as List?) ?? const [];
    return [
      for (final c in calls)
        ?fromCall(
              ToolCall(c['name'] as String,
                  (c['arguments'] as Map).map((k, v) => MapEntry('$k', '$v'.trim()))),
              alpine: alpine,
              source: 'model',
        ),
    ];
  }

  Future<void> startRecording() async {
    final granted = await const MethodChannel('aiterm/env').invokeMethod<bool>('requestMic');
    if (granted != true) throw StateError('Microphone permission is needed for voice');
    await _channel.invokeMethod('startRecording');
  }

  /// Stops recording and returns the transcript ('' for silence).
  Future<String> stopAndTranscribe() async {
    if (!_voiceReady) {
      await _channel.invokeMethod('loadVoice', {'modelPath': await _path(voiceModel)});
      _voiceReady = true;
    }
    final raw = await _channel.invokeMethod<String>('stopAndTranscribe', {
      'keywords': _voiceKeywords.join('\n'),
    });
    final result = jsonDecode(raw!) as Map<String, dynamic>;
    return (result['text'] as String? ?? '').trim();
  }

  Future<void> cancelRecording() => _channel.invokeMethod('cancelRecording');

  Suggestion? fromCall(ToolCall i, {required bool alpine, required String source}) {
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
        if (!alpine) return null;
        return cmd('[ -x ~/.local/bin/claude ] || install-claude && claude');
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

  static String _q(String s) =>
      RegExp(r'^[A-Za-z0-9._/@:=+,~-]+$').hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";

  static const _packageAliases = {
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

  static const _extensions = {
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
}
