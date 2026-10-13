// ignore_for_file: avoid_print
// Scores the full suggestion pipeline (rules, then Needle) against a cases
// file. Needs a Needle server: ./needle --model needle3.cact --tools T --serve
//   dart run tool/eval_intents.dart <cases.tsv> <port> [--rules-only]
import 'dart:convert';
import 'dart:io';
import 'package:aiterm/core/tool_call.dart';

Future<void> main(List<String> argv) async {
  final cases = File(argv[0])
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .map((l) => l.split('\t'))
      .toList();
  final port = argv.length > 1 ? argv[1] : '8099';
  final rulesOnly = argv.contains('--rules-only');
  final client = HttpClient();

  Future<Map<String, dynamic>> post(String path, Object body) async {
    final req = await client.post('127.0.0.1', int.parse(port), path);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  var ok = 0, byRules = 0, rulesWrong = 0;
  final fails = <String>[];
  for (final c in cases) {
    final prompt = c[0], want = c[1];
    final checks = c.length > 2 && c[2].isNotEmpty
        ? c[2].split(',').map((kv) => kv.split('=')).toList()
        : <List<String>>[];
    final rule = matchRules(prompt);
    ToolCall? got;
    var source = 'rules';
    if (rule != null) {
      byRules++;
      got = rule;
    } else if (!rulesOnly) {
      source = 'needle';
      await post('/reset', {});
      final r = await post('/complete', {'input': prompt});
      final calls = (r['function_calls'] as List?) ?? const [];
      if (calls.isNotEmpty) {
        got = ToolCall(calls.first['name'] as String,
            (calls.first['arguments'] as Map).map((k, v) => MapEntry('$k', '$v')));
      }
    } else {
      continue;
    }
    bool good;
    if (got?.rawCommand != null) {
      good = want != 'NONE'; // the user typed a command; passing it through is right
    } else if (want == 'NONE') {
      good = got == null;
    } else {
      good = got != null &&
          got.tool == want &&
          checks.every((kv) => (got!.args[kv[0]] ?? '').toLowerCase().contains(kv[1].toLowerCase()));
    }
    if (good) ok++;
    if (!good) {
      if (source == 'rules') rulesWrong++;
      fails.add('  [$source] "$prompt": want $want ${c.length > 2 ? c[2] : ''} | got ${got ?? 'nothing'}');
    }
  }
  final n = rulesOnly ? byRules : cases.length;
  print('$ok/$n = ${(100 * ok / n).round()}%  (rules handled $byRules, rules wrong $rulesWrong)');
  fails.forEach(print);
  client.close();
}
