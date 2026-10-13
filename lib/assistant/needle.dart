import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../platform/android_env.dart';
import '../shared/download.dart';
import 'tool_call.dart';

class ModelFile {
  final String name, url, sha256;
  final int sizeMb;
  const ModelFile(this.name, this.url, this.sha256, this.sizeMb);
}

/// Cactus Needle, a small on-device tool-calling model, plus Whistle for
/// speech (android/.../NeedlePlugin.kt over libneedle). Needle only picks
/// one of the actions in assets/needle_tools.json and fills its arguments.
class Needle {
  Needle(this._paths);

  final AppPaths _paths;
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

  File _file(ModelFile m) => File('${_paths.filesDir}/${m.name}');

  Future<bool> isDownloaded(ModelFile m) => _file(m).exists();

  Future<void> download(ModelFile m, void Function(double? progress) onProgress) =>
      downloadVerified(Uri.parse(m.url), _file(m), sha256Hex: m.sha256, onProgress: onProgress);

  /// The model's tool calls for [request].
  Future<List<ToolCall>> complete(String request) async {
    if (!_textReady) {
      await _channel.invokeMethod('init', {
        'modelPath': _file(textModel).path,
        'system': "You turn a terminal user's request into actions.",
        'tools': await rootBundle.loadString('assets/needle_tools.json'),
        'toolIndexPath': '${_paths.cacheDir}/needle-tools.idx',
      });
      _textReady = true;
    }
    final raw = await _channel.invokeMethod<String>('complete', {'input': request, 'maxTokens': 256});
    final calls = (jsonDecode(raw!) as Map<String, dynamic>)['function_calls'] as List? ?? const [];
    return [
      for (final c in calls)
        ToolCall(c['name'] as String, (c['arguments'] as Map).map((k, v) => MapEntry('$k', '$v'.trim()))),
    ];
  }

  Future<void> startRecording() async {
    if (!await AndroidEnv.requestMic()) throw StateError('Microphone permission is needed for voice');
    await _channel.invokeMethod('startRecording');
  }

  /// Stops recording and returns the transcript ('' for silence).
  Future<String> stopAndTranscribe() async {
    if (!_voiceReady) {
      await _channel.invokeMethod('loadVoice', {'modelPath': _file(voiceModel).path});
      _voiceReady = true;
    }
    final raw = await _channel.invokeMethod<String>('stopAndTranscribe', {'keywords': _voiceKeywords.join('\n')});
    return ((jsonDecode(raw!) as Map<String, dynamic>)['text'] as String? ?? '').trim();
  }

  Future<void> cancelRecording() => _channel.invokeMethod('cancelRecording');
}
