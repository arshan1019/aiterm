import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'distro_manager.dart';

class Suggestion {
  final String command;
  final String action;
  final double confidence;
  const Suggestion(this.command, this.action, this.confidence);
}

/// Turns "what do you want to do?" into shell commands with Needle, a small
/// on-device tool-calling model. Needle only picks a tool and fills its
/// arguments; the command itself always comes from a template below, so the
/// model can never produce a command we didn't write.
class NeedleService {
  NeedleService._();
  static final instance = NeedleService._();

  static const _channel = MethodChannel('aiterm/needle');
  static const _modelUrl =
      'https://huggingface.co/Cactus-Compute/needle3/resolve/93e88ede867e4311c39151285e74df513e4b835b/needle3.cact';
  static const _modelSha256 =
      'c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38';
  static const modelSizeMb = 35;

  bool _initialized = false;

  Future<String> get _modelPath async {
    final d = DistroManager.instance;
    await d.init();
    return '${d.filesDir}/needle3.cact';
  }

  Future<bool> isDownloaded() async => File(await _modelPath).exists();

  Future<void> download(void Function(double? progress) onProgress) async {
    final path = await _modelPath;
    final part = File('$path.part');
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(_modelUrl)));
      if (resp.statusCode != 200) {
        throw HttpException('Model download failed: HTTP ${resp.statusCode}');
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
    if (sha != _modelSha256) {
      await part.delete();
      throw StateError('Model checksum mismatch');
    }
    await part.rename(path);
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    final d = DistroManager.instance;
    await _channel.invokeMethod('init', {
      'modelPath': await _modelPath,
      'system': 'You turn a terminal user\'s request into actions.',
      'tools': jsonEncode(_tools),
      'toolIndexPath': '${d.cacheDir}/needle-tools.idx',
    });
    _initialized = true;
  }

  Future<List<Suggestion>> suggest(String request, {required bool alpine}) async {
    await _ensureInit();
    final raw = await _channel.invokeMethod<String>('complete', {
      'input': request,
      'maxTokens': 256,
    });
    final result = jsonDecode(raw!) as Map<String, dynamic>;
    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
    final calls = (result['function_calls'] as List?) ?? const [];
    return [
      for (final c in calls)
        if (buildCommand(c['name'] as String, (c['arguments'] as Map).cast<String, dynamic>(), alpine)
            case final cmd?)
          Suggestion(cmd, c['name'] as String, confidence),
    ];
  }

  @visibleForTesting
  String? buildCommand(String tool, Map<String, dynamic> a, bool alpine) {
    String arg(String k, [String fallback = '']) {
      final v = a[k]?.toString().trim() ?? '';
      return v.isEmpty ? fallback : v;
    }

    final path = _q(arg('path', '.'));
    switch (tool) {
      case 'install_package':
        final pkgs = _packageAliases[arg('name').toLowerCase()] ?? [arg('name')];
        if (pkgs.first.isEmpty) return null;
        return alpine ? 'apk add ${pkgs.map(_q).join(' ')}' : null;
      case 'remove_package':
        return alpine && arg('name').isNotEmpty ? 'apk del ${_q(arg('name'))}' : null;
      case 'find_files':
        final type = arg('type').toLowerCase();
        final name = arg('name');
        final ext = _extensions[type] ?? (type.length <= 4 && type.isNotEmpty ? [type] : null);
        if (ext != null) {
          final names = ext.map((e) => "-name '*.$e'").join(' -o ');
          return ext.length == 1
              ? 'find $path -type f $names'
              : 'find $path -type f \\( $names \\)';
        }
        final term = name.isNotEmpty ? name : type;
        return term.isEmpty ? null : 'find $path -iname ${_q('*$term*')}';
      case 'search_text':
        return arg('query').isEmpty ? null : 'grep -rn ${_q(arg('query'))} $path';
      case 'list_files':
        return 'ls -la $path';
      case 'change_directory':
        return arg('path').isEmpty ? null : 'cd ${_q(arg('path'))}';
      case 'find_big_files':
        return 'du -ah $path 2>/dev/null | sort -rh | head -20';
      case 'git_status':
        return 'git status';
      case 'git_commit':
        return arg('message').isEmpty ? null : 'git add -A && git commit -m ${_q(arg('message'))}';
      case 'git_push':
        return 'git push';
      case 'git_clone':
        return arg('url').isEmpty ? null : 'git clone ${_q(arg('url'))}';
      case 'run_script':
        return arg('script').isEmpty ? null : 'npm run ${_q(arg('script'))}';
      case 'install_dependencies':
        return 'npm install';
      case 'kill_process':
        return arg('name').isEmpty ? null : 'pkill ${_q(arg('name'))}';
      case 'start_claude':
        return 'command -v claude >/dev/null || npm i -g @anthropic-ai/claude-code; claude';
    }
    return null;
  }

  static String _q(String s) =>
      RegExp(r'^[A-Za-z0-9._/@:=+,~-]+$').hasMatch(s) ? s : "'${s.replaceAll("'", r"'\''")}'";

  static const _packageAliases = {
    'node': ['nodejs', 'npm'],
    'nodejs': ['nodejs', 'npm'],
    'python': ['python3', 'py3-pip'],
    'python3': ['python3', 'py3-pip'],
    'pip': ['py3-pip'],
    'rg': ['ripgrep'],
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
    'shell': ['sh'],
  };

  // Tuned against the model: names people would say, enums where the
  // argument has a fixed set of values.
  static const _tools = [
    {
      'name': 'install_package',
      'description': 'Install a software package or tool, e.g. node, git, python, ripgrep.',
      'parameters': {
        'type': 'object',
        'properties': {'name': {'type': 'string', 'description': 'package name'}},
        'required': ['name'],
      },
    },
    {
      'name': 'remove_package',
      'description': 'Uninstall a software package.',
      'parameters': {
        'type': 'object',
        'properties': {'name': {'type': 'string'}},
        'required': ['name'],
      },
    },
    {
      'name': 'find_files',
      'description': 'Find files of a type or with a name.',
      'parameters': {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'description': 'file type or extension, e.g. python, js, pdf, images'},
          'name': {'type': 'string', 'description': 'part of the file name'},
          'path': {'type': 'string'},
        },
      },
    },
    {
      'name': 'search_text',
      'description': 'Search inside files for text.',
      'parameters': {
        'type': 'object',
        'properties': {'query': {'type': 'string'}, 'path': {'type': 'string'}},
        'required': ['query'],
      },
    },
    {
      'name': 'list_files',
      'description': 'List the files in a folder (just names, not sizes).',
      'parameters': {
        'type': 'object',
        'properties': {'path': {'type': 'string'}},
      },
    },
    {
      'name': 'change_directory',
      'description': 'Go to a folder.',
      'parameters': {
        'type': 'object',
        'properties': {'path': {'type': 'string'}},
        'required': ['path'],
      },
    },
    {
      'name': 'find_big_files',
      'description': 'Find the biggest files and folders, what is taking up space.',
      'parameters': {
        'type': 'object',
        'properties': {'path': {'type': 'string'}},
      },
    },
    {
      'name': 'git_status',
      'description': 'Show what changed in the git repository.',
      'parameters': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'git_commit',
      'description': 'Stage all changes and commit them with a message.',
      'parameters': {
        'type': 'object',
        'properties': {'message': {'type': 'string'}},
        'required': ['message'],
      },
    },
    {
      'name': 'git_push',
      'description': 'Push commits to the remote repository.',
      'parameters': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'git_clone',
      'description': 'Download a git repository from a URL.',
      'parameters': {
        'type': 'object',
        'properties': {'url': {'type': 'string'}},
        'required': ['url'],
      },
    },
    {
      'name': 'run_script',
      'description': "Run a project's npm script: dev (dev server), build, test or start.",
      'parameters': {
        'type': 'object',
        'properties': {
          'script': {'type': 'string', 'enum': ['dev', 'build', 'test', 'start']},
        },
        'required': ['script'],
      },
    },
    {
      'name': 'install_dependencies',
      'description': 'Install the dependencies of the current project.',
      'parameters': {'type': 'object', 'properties': {}},
    },
    {
      'name': 'kill_process',
      'description': 'Stop a running program by name.',
      'parameters': {
        'type': 'object',
        'properties': {'name': {'type': 'string'}},
        'required': ['name'],
      },
    },
    {
      'name': 'start_claude',
      'description': 'Start Claude Code, the AI coding assistant.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  ];
}
