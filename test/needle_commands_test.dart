import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/core/needle_service.dart';
import 'package:aiterm/core/tool_call.dart';

void main() {
  final n = NeedleService.instance;
  Suggestion? s(String tool, [Map<String, String> args = const {}, bool alpine = true]) =>
      n.fromCall(ToolCall(tool, args), alpine: alpine, source: 'model');
  String? cmd(String tool, [Map<String, String> args = const {}, bool alpine = true]) =>
      s(tool, args, alpine)?.command;

  test('maps actions to the expected commands', () {
    expect(cmd('install_package', {'name': 'node'}), 'apk add nodejs npm');
    expect(cmd('install_package', {'name': 'npm'}), 'apk add nodejs npm');
    expect(cmd('find_files', {'type': 'python'}), "find . -type f -name '*.py'");
    expect(cmd('find_files', {'type': 'config'}), "find . -iname '*config*'");
    expect(cmd('run_script', {'script': 'dev'}), 'npm run dev');
    expect(cmd('run_script', {'script': 'start'}), 'npm start');
    expect(cmd('create_folder', {'name': 'projects'}), 'mkdir -p projects');
    expect(cmd('move_file', {'source': 'a.txt', 'destination': 'b.txt'}), 'mv a.txt b.txt');
    expect(cmd('find_big_files', {'path': 'Download'}), 'du -ah Download 2>/dev/null | sort -rh | head -20');
  });

  test('missing names give a partial command to finish', () {
    final folder = s('create_folder');
    expect(folder?.command, 'mkdir -p ');
    expect(folder?.needsInput, isTrue);
    expect(s('install_package', {'name': ''})?.command, 'apk add ');
    expect(s('move_file', {'source': 'a.txt'})?.command, 'mv a.txt ');
    expect(s('delete_file'), isNull, reason: 'never insert a bare rm');
  });

  test('quotes arguments so model output cannot inject shell syntax', () {
    expect(cmd('git_commit', {'message': "it's done; rm -rf ~"}),
        "git add -A && git commit -m 'it'\\''s done; rm -rf ~'");
    expect(cmd('search_text', {'query': r'$(reboot)'}), r"grep -rn '$(reboot)' .");
    expect(cmd('change_directory', {'path': 'my dir`id`'}), "cd 'my dir`id`'");
  });

  test('app actions are not shell commands', () {
    final theme = s('set_theme', {'theme': 'dark'});
    expect(theme?.command, isNull);
    expect(theme?.appAction?.tool, 'set_theme');
    expect(s('open_tab', {'tab': 'nowhere'}), isNull);
  });

  test('refuses what the Android shell cannot do', () {
    expect(cmd('install_package', {'name': 'git'}, false), isNull);
    expect(cmd('unknown_tool'), isNull);
  });
}
